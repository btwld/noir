@Tags(['safe-process-spawning'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  final workflow = File(
    '../../.github/workflows/release.yml',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  test('a release never starts itself from a tag push', () {
    // The defect this shape exists to remove: release.yml used to trigger on
    // `noir-v*` independently of publish.yml, so a GitHub release could go
    // public while pub.dev approval was still pending, or after the upload
    // had failed outright.
    expect(
      workflow,
      isNot(contains('push:')),
      reason: 'a tag push must reach this only through publish.yml',
    );
    expect(workflow, isNot(contains('branches:')));
    expect(workflow, isNot(contains('pull_request:')));
    expect(workflow, contains('workflow_call:'));
    // Dispatch stays so a release whose creation failed after a successful
    // publication can be re-cut without moving a published tag.
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains(r'ref: refs/tags/${{ inputs.tag }}'));
    expect(
      workflow,
      contains(r'git show-ref --verify --quiet "refs/tags/$RELEASE_TAG"'),
    );
    expect(workflow, contains('cancel-in-progress: false'));
  });

  test('the announcement asks pub.dev before it announces anything', () {
    // The second, independent gate. `needs: publish` orders the chained path;
    // this one also covers a manual dispatch, which has no such ordering.
    expect(workflow, contains('dart run tool/release.dart published'));
    final gate = workflow.indexOf('tool/release.dart published');
    final create = workflow.indexOf('softprops/action-gh-release@');
    expect(gate, greaterThan(-1));
    expect(
      create,
      greaterThan(gate),
      reason: 'the registry check must precede creating the release',
    );
  });

  test('release uses immutable actions and explicit permissions', () {
    for (final line
        in workflow
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.startsWith('uses:'))) {
      expect(
        line,
        matches(RegExp(r'^uses: [^@ ]+@[0-9a-f]{40}(?: # v[^ ]+)?$')),
        reason: 'release action must be immutable: $line',
      );
    }

    expect(workflow, contains('permissions:\n  contents: read'));
    final announce = workflow.substring(workflow.indexOf('  announce:'));
    expect(announce, contains('contents: write'));
    expect(announce, isNot(contains('secrets.GITHUB_TOKEN')));
  });

  test('the release archive is rebuilt from the tagged commit', () {
    // Not carried between jobs. These files are committed, preflight has
    // already matched them against their manifest digests, and a manual
    // dispatch has no earlier job to inherit an artifact from — so the
    // archive is built here, from this checkout, on both paths.
    final tar = workflow.indexOf('run: tar -czf');
    final create = workflow.indexOf('softprops/action-gh-release@');

    expect(tar, greaterThan(-1));
    expect(create, greaterThan(tar));
    expect(workflow, contains('native_manifest.json'));
    expect(
      workflow,
      isNot(contains('actions/download-artifact@')),
      reason: 'the archive comes from the checkout, not from another job',
    );
    expect(workflow, isNot(contains('--verify-urls')));
    expect(
      workflow,
      isNot(contains(r'PUB_CACHE: ${{ runner.temp }}/pub-cache')),
      reason: 'runner context is unavailable in job-level env',
    );
  });

  test(
    'downloadable native archive carries unchanged assets and notices',
    () async {
      // Exercise the workflow's actual tar inputs without running release jobs
      // or evaluating shell code. The output is redirected to a temporary file.
      final command = RegExp(
        r'^\s+run: tar -czf "opentui-binaries-\$RELEASE_TAG\.tar\.gz" '
        r'([A-Za-z0-9_./ -]+)$',
        multiLine: true,
      ).firstMatch(workflow);
      expect(
        command,
        isNotNull,
        reason: 'native archive command must be explicit',
      );
      final inputs = command!.group(1)!.trim().split(RegExp(r'\s+'));
      final temporary = Directory.systemTemp.createTempSync(
        'noir_native_archive.',
      );
      addTearDown(() => temporary.deleteSync(recursive: true));
      final output = File('${temporary.path}/native.tar.gz');

      final result = await Process.run(
        'tar',
        <String>['-czf', output.path, ...inputs],
        environment: <String, String>{'COPYFILE_DISABLE': '1'},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

      final extracted = Directory('${temporary.path}/extracted')..createSync();
      final extraction = await Process.run('tar', <String>[
        '-xzf',
        output.path,
        '-C',
        extracted.path,
      ]);
      expect(extraction.exitCode, 0, reason: '${extraction.stderr}');
      final files = <String, File>{
        for (final entry
            in extracted.listSync(recursive: true).whereType<File>())
          path
                  .relative(entry.path, from: extracted.path)
                  .replaceAll(Platform.pathSeparator, '/'):
              entry,
      };
      final manifest =
          jsonDecode(File('native_manifest.json').readAsStringSync())
              as Map<String, Object?>;
      final assets = (manifest['assets']! as Map<String, Object?>).values
          .cast<Map<String, Object?>>();
      final expectedFiles = <String>{
        'LICENSE',
        'THIRD_PARTY_NOTICES.md',
        'native_manifest.json',
        'native/opentui_v0_5_1.h',
        for (final asset in assets) asset['path']! as String,
        ..._thirdPartyNotices,
      };
      expect(files.keys, unorderedEquals(expectedFiles));
      for (final name in expectedFiles) {
        expect(
          sha256.convert(files[name]!.readAsBytesSync()).toString(),
          sha256.convert(File(name).readAsBytesSync()).toString(),
          reason: '$name must be archived without modification',
        );
      }
      for (final asset in assets) {
        final name = asset['path']! as String;
        expect(
          sha256.convert(files[name]!.readAsBytesSync()).toString(),
          asset['sha256'],
          reason: '$name must retain its pinned native digest',
        );
      }
    },
  );

  test('the tag is checked against the manifest by the shared tool', () {
    // The same rule the publish workflow applies, from the same place, so a
    // GitHub release cannot be cut for a tag pub.dev would have refused.
    // `test/tools/release_cli_test.dart` covers the rule itself.
    expect(workflow, contains('dart run tool/release.dart resolve-tag'));
    expect(
      workflow,
      isNot(contains("semver='[0-9]+")),
      reason: 'version parsing belongs to the tool, not to the workflow',
    );
  });

  test('release metadata is strict and states the macOS deployment floor', () {
    expect(workflow, contains('fail_on_unmatched_files: true'));
    expect(workflow, contains(r'tag_name: ${{ inputs.tag }}'));
    // Every release tag carries a `-` between the package and the version, so
    // no rule that reads the tag text can answer this. It comes from the
    // parsed version, via the same tool the publish workflow uses;
    // `test/tools/release_cli_test.dart` covers the rule itself.
    expect(
      workflow,
      contains(r'prerelease: ${{ steps.tag.outputs.prerelease }}'),
    );
    expect(
      workflow,
      isNot(contains('contains(env.RELEASE_TAG')),
      reason: 'a substring test cannot decide what a prerelease is',
    );
    expect(workflow, contains('generate_release_notes: true'));
    expect(workflow, contains('macOS 13.0 or later (x64, arm64)'));
    expect(workflow, isNot(contains('dart run example/')));
  });
}

const _thirdPartyNotices = <String>{
  'third_party/opentui-v0.5.1/LICENSE',
  'third_party/opentui-v0.5.1/LICENSE-WUFFS',
  'third_party/opentui-v0.5.1/LICENSE-LIBWEBP',
  'third_party/opentui-v0.5.1/AUTHORS-LIBWEBP',
  'third_party/opentui-v0.5.1/PATENTS-LIBWEBP',
  'third_party/opentui-v0.5.1/LICENSE-STB',
  'third_party/opentui-v0.5.1/LICENSE-LCMS2',
  'third_party/opentui-v0.5.1/LICENSE-YOGA',
  'third_party/uucode-84ceda/LICENSE.md',
  'third_party/uucode-84ceda/LICENSE_unicode',
};
