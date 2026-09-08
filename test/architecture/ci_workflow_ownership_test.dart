import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const _safeProcessTests = <String>[
  'test/bin/health_check_test.dart',
  'test/rendering/flex_validation_release_test.dart',
  'test/rendering/geometry_constraints_test.dart',
  'test/rendering/paragraph_max_lines_test.dart',
  'test/rendering/render_setter_invalidation_release_test.dart',
  'test/source_package_consumer_test.dart',
  'test/tools/patch_manager_git_test.dart',
  'test/widgets/geometry_validation_test.dart',
  'test/widgets/text_editing_owner_release_test.dart',
  'test/widgets/text_max_lines_release_test.dart',
];

void main() {
  final workflow = _read('.github/workflows/ci.yml');

  test('CI targets main and every pull-request base with cancellation', () {
    expect(workflow, contains('push:\n    branches: [main]'));
    expect(workflow, contains('  pull_request:'));
    expect(workflow, isNot(contains('pull_request:\n    branches:')));
    expect(workflow, contains('permissions:\n  contents: read'));
    expect(
      workflow,
      contains(r'group: ${{ github.workflow }}-${{ github.ref }}'),
    );
    expect(workflow, contains('cancel-in-progress: true'));
  });

  test('all workflow actions use immutable full SHA references', () {
    final actionLines = workflow
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('uses:'));

    expect(actionLines, isNotEmpty);
    for (final line in actionLines) {
      expect(
        line,
        matches(RegExp(r'^uses: [^@ ]+@[0-9a-f]{40}(?: # v[^ ]+)?$')),
        reason: 'mutable or malformed action reference: $line',
      );
    }
  });

  test('CI gates bounded platform jobs behind analysis', () {
    final analyze = _job(workflow, 'analyze');
    final ubuntu = _job(workflow, 'ubuntu-test');
    final desktop = _job(workflow, 'desktop-test');

    expect(analyze, contains('runs-on: ubuntu-latest'));
    expect(analyze, contains('    timeout-minutes: 15\n'));
    expect(analyze, contains('timeout-minutes: 3\n        run: dart pub get'));
    expect(analyze, contains('timeout-minutes: 2\n        run: dart format'));
    expect(analyze, contains('timeout-minutes: 4\n        run: dart analyze'));

    expect(ubuntu, contains('needs: analyze'));
    expect(ubuntu, contains('    timeout-minutes: 24\n'));
    expect(
      ubuntu,
      contains(
        'timeout-minutes: 2\n        run: dart run scripts/fetch_opentui_binaries.dart --verify-only',
      ),
    );
    expect(
      ubuntu,
      contains('timeout-minutes: 15\n        run: dart test --concurrency=1'),
    );

    expect(desktop, contains('needs: analyze'));
    expect(desktop, isNot(contains('needs: ubuntu-test')));
    expect(desktop, contains('    timeout-minutes: 29\n'));
    expect(desktop, contains('os: [macos-latest, windows-latest]'));
    expect(
      desktop,
      contains(
        'timeout-minutes: 2\n        run: dart run scripts/fetch_opentui_binaries.dart --verify-only',
      ),
    );
    expect(
      desktop,
      contains('timeout-minutes: 20\n        run: dart test --concurrency=1'),
    );
  });

  test('each job budget equals the sum of its step ceilings', () {
    // A step timeout then always reports before the job timeout, so a slow
    // step is named instead of the whole job being killed anonymously.
    for (final name in const <String>[
      'analyze',
      'ubuntu-test',
      'desktop-test',
    ]) {
      final job = _job(workflow, name);
      final budget = int.parse(
        RegExp(
          r'^    timeout-minutes: (\d+)',
          multiLine: true,
        ).firstMatch(job)!.group(1)!,
      );
      final ceilings = RegExp(
        r'^        timeout-minutes: (\d+)',
        multiLine: true,
      ).allMatches(job).map((match) => int.parse(match.group(1)!)).toList();
      expect(ceilings, isNotEmpty, reason: name);
      expect(
        budget,
        ceilings.reduce((a, b) => a + b),
        reason: '$name: job budget must equal the sum of its step ceilings',
      );
    }
  });

  test('every platform job also checks the companion package', () {
    const companionTest =
        'timeout-minutes: 4\n'
        '        working-directory: packages/noir_signals\n'
        '        run: dart test --concurrency=1';

    expect(companionTest.allMatches(workflow), hasLength(2));
    expect(_job(workflow, 'ubuntu-test'), contains(companionTest));
    expect(_job(workflow, 'desktop-test'), contains(companionTest));

    final analyze = _job(workflow, 'analyze');
    expect(
      analyze,
      contains(
        'timeout-minutes: 2\n'
        '        working-directory: packages/noir_signals\n'
        '        run: dart format --output=none --set-exit-if-changed '
        'lib/ test/ example/',
      ),
    );
    expect(
      analyze,
      contains(
        'timeout-minutes: 4\n'
        '        working-directory: packages/noir_signals\n'
        '        run: dart analyze --fatal-infos',
      ),
    );
  });

  test(
    'each CI job caches only the isolated pub cache and always resolves',
    () {
      expect('actions/cache@'.allMatches(workflow), hasLength(3));
      expect(
        r'path: ${{ runner.temp }}/pub-cache'.allMatches(workflow),
        hasLength(3),
      );
      expect(
        r"key: ${{ runner.os }}-Dart-3.10.0-${{ hashFiles('pubspec.yaml', "
                "'packages/noir_signals/pubspec.yaml') }}"
            .allMatches(workflow),
        hasLength(3),
      );
      expect(
        r'run: echo "PUB_CACHE=$RUNNER_TEMP/pub-cache" >> "$GITHUB_ENV"'
            .allMatches(workflow),
        hasLength(3),
      );
      expect(
        workflow,
        isNot(contains(r'PUB_CACHE: ${{ runner.temp }}/pub-cache')),
        reason: 'runner context is unavailable in job-level env',
      );
      expect('run: dart pub get'.allMatches(workflow), hasLength(3));
      expect(workflow, isNot(contains('.dart_tool')));
    },
  );

  test('ordinary suite has no removed wrapper, parity, or restricted lane', () {
    for (final stale in <String>[
      'native-wrapper',
      'parity:',
      'GO_SNAPSHOT_CMD',
      'restricted-process-lifecycle',
      'build_opentui_candidates',
    ]) {
      expect(workflow, isNot(contains(stale)), reason: stale);
    }

    for (final file in _safeProcessTests) {
      final source = _read(file);
      expect(source, contains('safe-process-spawning'), reason: file);
    }

    final restrictedOwners = <String>[];
    for (final entity in Directory('test').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = path
          .relative(entity.path, from: Directory.current.path)
          .replaceAll(Platform.pathSeparator, '/');
      if (normalized.startsWith('test/architecture/')) continue;
      if (_read(entity.path).contains('restricted-process-lifecycle')) {
        restrictedOwners.add(normalized);
      }
    }
    expect(restrictedOwners, isEmpty);
    expect(
      _read('dart_test.yaml'),
      isNot(contains('restricted-process-lifecycle')),
    );
  });
}

String _job(String workflow, String name) {
  final start = workflow.indexOf('  $name:');
  expect(start, isNonNegative, reason: 'missing job $name');
  final end = workflow.indexOf(
    RegExp('^  [a-z][a-z-]+:', multiLine: true),
    start + 3,
  );
  return workflow.substring(start, end < 0 ? workflow.length : end);
}

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');
