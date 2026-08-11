import 'dart:io';

import 'package:test/test.dart';

void main() {
  final workflows = <String, String>{
    for (final name in <String>['ci', 'release', 'publish'])
      name: File(
        '.github/workflows/$name.yml',
      ).readAsStringSync().replaceAll('\r\n', '\n'),
  };
  final publish = workflows['publish']!;

  test('workflows use directly committed native assets without Git LFS', () {
    final lfsKey = RegExp(
      r'^[ \t]*lfs[ \t]*:',
      caseSensitive: false,
      multiLine: true,
    );
    final lfsCommand = RegExp(r'\bgit(?:-|[ \t]+)lfs\b', caseSensitive: false);

    for (final entry in workflows.entries) {
      expect(
        entry.value,
        isNot(matches(lfsKey)),
        reason: '${entry.key}.yml must not restore an LFS checkout key',
      );
      final executableSource = entry.value
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('#'))
          .join('\n');
      expect(
        executableSource,
        isNot(matches(lfsCommand)),
        reason: '${entry.key}.yml must not restore an LFS command',
      );
    }
  });

  test('pub.dev preflight rejects a tag that differs from pubspec version', () {
    const tagGate = r'''
      - name: Verify tag matches pubspec version
        shell: bash
        env:
          RELEASE_TAG: ${{ github.ref_name }}
        run: |
          set -euo pipefail
          version_declarations="$(grep -E '^version:' pubspec.yaml || true)"
          if [[ ! "$version_declarations" =~ ^version:[[:space:]]+([0-9A-Za-z.+-]+)[[:space:]]*$ ]]; then
            echo "::error::pubspec.yaml must declare exactly one plain version"
            exit 1
          fi
          package_version="${BASH_REMATCH[1]}"
          expected_tag="v$package_version"
          if [[ "$RELEASE_TAG" != "$expected_tag" ]]; then
            echo "::error::tag $RELEASE_TAG does not match pubspec version $package_version"
            exit 1
          fi''';

    final preflightStart = publish.indexOf('  preflight:');
    final publishStart = publish.indexOf('  publish:', preflightStart + 1);
    expect(preflightStart, greaterThan(-1));
    expect(publishStart, greaterThan(preflightStart));

    final preflight = publish.substring(preflightStart, publishStart);
    final checkout = preflight.indexOf('uses: actions/checkout@v4');
    final gate = preflight.indexOf(tagGate);
    final setup = preflight.indexOf('uses: dart-lang/setup-dart@v1');
    final dryRun = preflight.indexOf('run: dart pub publish --dry-run');
    final publishJob = publish.substring(publishStart);
    final failureOverride = RegExp(
      r'^[ \t]*(?:continue-on-error|if)[ \t]*:',
      multiLine: true,
    );

    expect(checkout, greaterThan(-1));
    expect(gate, greaterThan(checkout));
    expect(setup, greaterThan(gate));
    expect(dryRun, greaterThan(gate));
    expect(preflight, isNot(matches(failureOverride)));
    expect(publishJob, contains('    needs: preflight'));
    expect(publishJob, isNot(matches(failureOverride)));
  });
}
