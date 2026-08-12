import 'dart:io';

import 'package:test/test.dart';

void main() {
  final workflows = <String, String>{
    for (final name in <String>['ci', 'release', 'publish'])
      name: _read('.github/workflows/$name.yml'),
  };
  final publish = workflows['publish']!;

  test('workflows never depend on Git LFS restoration', () {
    for (final entry in workflows.entries) {
      expect(
        entry.value,
        isNot(matches(RegExp(r'^\s*lfs\s*:', multiLine: true))),
        reason: '${entry.key}.yml must use committed native assets',
      );
      expect(
        entry.value,
        isNot(matches(RegExp(r'\bgit(?:-|\s+)lfs\b'))),
        reason: '${entry.key}.yml must not invoke Git LFS',
      );
    }
  });

  test('publish configuration names Noir and immutable actions', () {
    expect(publish, contains('repository: leoafarias/noir'));
    expect(publish, isNot(contains('leoafarias/cli_ui')));
    expect(publish, contains("tags: ['v*']"));

    for (final line
        in publish
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.startsWith('uses:'))) {
      expect(
        line,
        matches(RegExp(r'^uses: [^@ ]+@[0-9a-f]{40}(?: # v[^ ]+)?$')),
        reason: 'publish action must be immutable: $line',
      );
    }
  });

  test('publish preflight validates exact semantic version and package', () {
    final preflightStart = publish.indexOf('  preflight:');
    final publishStart = publish.indexOf('  publish:', preflightStart + 1);
    expect(preflightStart, greaterThan(-1));
    expect(publishStart, greaterThan(preflightStart));

    final preflight = publish.substring(preflightStart, publishStart);
    expect(preflight, contains('timeout-minutes: 15'));
    expect(
      preflight,
      contains(
        r'run: echo "PUB_CACHE=$RUNNER_TEMP/pub-cache" >> "$GITHUB_ENV"',
      ),
    );
    expect(
      preflight,
      isNot(contains(r'PUB_CACHE: ${{ runner.temp }}/pub-cache')),
      reason: 'runner context is unavailable in job-level env',
    );
    expect(preflight, contains('actions/cache@'));
    expect(preflight, contains(r'path: ${{ runner.temp }}/pub-cache'));
    expect(preflight, contains('semver='));
    expect(preflight, contains(r'package_version="${BASH_REMATCH[1]}"'));
    expect(preflight, contains(r'"v$package_version"'));
    expect(
      preflight,
      contains('dart run scripts/fetch_opentui_binaries.dart --verify-only'),
    );
    expect(preflight, contains('dart test --concurrency=1'));
    expect(preflight, contains('dart doc --validate-links'));
    expect(preflight, contains('dart pub publish --dry-run'));
    expect(preflight, isNot(contains('continue-on-error')));
    expect(preflight, isNot(contains('.dart_tool')));
  });

  test('OIDC publication depends on preflight with least privilege', () {
    expect(publish, contains('permissions:\n  contents: read'));
    final publishJob = publish.substring(publish.indexOf('  publish:'));
    expect(publishJob, contains('needs: preflight'));
    expect(publishJob, contains('id-token: write'));
    expect(publishJob, contains('contents: read'));
    expect(publishJob, isNot(contains('secrets.')));
    expect(publishJob, isNot(contains('continue-on-error')));
  });
}

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');
