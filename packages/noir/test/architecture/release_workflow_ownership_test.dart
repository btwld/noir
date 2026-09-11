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

  test('release is manual for one explicit existing tag', () {
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains('inputs:'));
    expect(workflow, contains('tag:'));
    expect(
      RegExp(r'ref: refs/tags/\$\{\{ inputs\.tag \}\}').allMatches(workflow),
      hasLength(2),
    );
    expect(
      workflow,
      contains(r'git show-ref --verify --quiet "refs/tags/$RELEASE_TAG"'),
    );
    expect(workflow, isNot(contains('push:')));
    expect(workflow, isNot(contains('tags:')));
    expect(workflow, isNot(contains('branches:')));
    expect(workflow, contains('cancel-in-progress: false'));
    expect(workflow, contains('for example, v1.2.3'));
    expect(workflow, isNot(contains('pull_request:')));
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
    final release = workflow.substring(workflow.indexOf('  release:'));
    expect(release, contains('contents: write'));
    expect(release, isNot(contains('secrets.GITHUB_TOKEN')));
  });

  test('verified committed assets are packaged then tested cross-platform', () {
    final verify = workflow.indexOf(
      'dart run tool/fetch_opentui_binaries.dart --verify-only',
    );
    final ordinaryTests = workflow.indexOf('dart test --concurrency=1');
    final docs = workflow.indexOf(
      'dart doc --validate-links --output .context/dartdoc',
    );
    final dryRun = workflow.indexOf('dart pub publish --dry-run');
    final upload = workflow.indexOf('actions/upload-artifact@');
    final remove = workflow.indexOf('run: rm -rf native native_manifest.json');
    final download = workflow.indexOf('actions/download-artifact@');
    final health = workflow.indexOf('run: dart run noir:health_check');

    expect(verify, greaterThan(-1));
    expect(workflow, isNot(contains('--verify-urls')));
    expect(ordinaryTests, greaterThan(verify));
    expect(docs, greaterThan(ordinaryTests));
    expect(dryRun, greaterThan(docs));
    expect(upload, greaterThan(dryRun));
    expect(remove, greaterThan(upload));
    expect(download, greaterThan(remove));
    expect(health, greaterThan(download));
    expect(workflow, contains('native_manifest.json'));
    expect(workflow, contains('ubuntu-latest'));
    expect(workflow, contains('macos-latest'));
    expect(workflow, contains('windows-latest'));
    expect(workflow, contains('dart build cli -t bin/health_check.dart'));
    expect(workflow, contains('  verify:'));
    expect(workflow, contains('timeout-minutes: 12'));
    expect(workflow, contains('timeout-minutes: 5'));
    expect('actions/cache@'.allMatches(workflow), hasLength(2));
    expect(
      r'path: ${{ runner.temp }}/pub-cache'.allMatches(workflow),
      hasLength(2),
    );
    expect(
      r'run: echo "PUB_CACHE=$RUNNER_TEMP/pub-cache" >> "$GITHUB_ENV"'
          .allMatches(workflow),
      hasLength(2),
    );
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

  test('tag releases require an exact semantic-version/package match', () {
    expect(workflow, contains('name: Verify release tag'));
    expect(workflow, contains(r'RELEASE_TAG: ${{ inputs.tag }}'));
    expect(workflow, contains("semver='[0-9]+[.][0-9]+[.][0-9]+"));
    expect(
      workflow,
      contains(r'if [[ "$RELEASE_TAG" != "v$package_version" ]]'),
    );
  });

  test('release metadata is strict and states the macOS deployment floor', () {
    expect(workflow, contains('fail_on_unmatched_files: true'));
    expect(workflow, contains(r"prerelease: ${{ contains(inputs.tag, '-') }}"));
    expect(workflow, contains(r'tag_name: ${{ inputs.tag }}'));
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
