import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

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
  final workflow = _read('../../.github/workflows/ci.yml');

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

  test('draft pull requests run no jobs', () {
    // `ready_for_review` is not a default pull_request type. Marking a draft
    // ready fires that event, so leaving it off means CI never starts.
    // Skipping is the gate: a job that runs only on drafts and exits non-zero
    // would still be a job, and would block the pull request.
    final workflows =
        Directory('../../.github/workflows')
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('.yml') || file.path.endsWith('.yaml'),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(workflows, isNotEmpty);

    final triggered = <String>[];
    for (final file in workflows) {
      final source = file.readAsStringSync().replaceAll('\r\n', '\n');
      final document = loadYaml(source) as YamlMap;
      final triggers = document['on'] as YamlMap;
      if (!triggers.containsKey('pull_request')) continue;
      final name = path.basename(file.path);
      triggered.add(name);

      final pullRequest = triggers['pull_request'];
      expect(pullRequest, isA<YamlMap>(), reason: name);
      expect(
        List<String>.from((pullRequest as YamlMap)['types'] as YamlList),
        ['opened', 'synchronize', 'reopened', 'ready_for_review'],
        reason: name,
      );

      final jobs = document['jobs'] as YamlMap;
      expect(jobs.keys, isNotEmpty, reason: name);
      for (final entry in jobs.entries) {
        final condition = (entry.value as YamlMap)['if']?.toString();
        expect(
          condition,
          contains('github.event.pull_request.draft == false'),
          reason: '$name job ${entry.key} runs on a draft pull request',
        );
        expect(
          condition,
          isNot(contains('draft == true')),
          reason: '${entry.key} skips drafts instead of failing a gate',
        );
      }
    }

    expect(triggered, ['ci.yml']);

    // Push, schedule, and workflow_dispatch have no pull request, so the
    // first clause keeps those jobs. Website validation stays pull-request
    // only. Desktop stays paused on every event, with the same draft term.
    const unlessDraft =
        "github.event_name != 'pull_request' || "
        'github.event.pull_request.draft == false';
    expect(_job(workflow, 'analyze'), contains('if: $unlessDraft'));
    expect(_job(workflow, 'ubuntu-test'), contains('if: $unlessDraft'));
    expect(
      _job(workflow, 'ubuntu-test'),
      isNot(contains('always()')),
      reason: 'always() would run tests after analyze failed or was skipped',
    );
    expect(
      _job(workflow, 'website'),
      contains(
        "if: github.event_name == 'pull_request' && "
        'github.event.pull_request.draft == false',
      ),
    );
    expect(
      _job(workflow, 'desktop-test'),
      contains('if: false && ($unlessDraft)'),
    );
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
    expect(analyze, contains('timeout-minutes: 3\n        run: dart pub get'));
    expect(
      analyze,
      contains(
        'timeout-minutes: 2\n        run: dart run melos:melos run format:noir',
      ),
    );
    expect(
      analyze,
      contains(
        'timeout-minutes: 4\n        run: dart run melos:melos run analyze',
      ),
    );

    expect(ubuntu, contains('needs: analyze'));
    expect(
      ubuntu,
      contains(
        'timeout-minutes: 2\n        run: dart run melos:melos run native:verify',
      ),
    );
    expect(
      ubuntu,
      contains(
        'timeout-minutes: 15\n        run: dart run melos:melos run test:noir',
      ),
    );

    expect(desktop, contains('needs: analyze'));
    expect(desktop, isNot(contains('needs: ubuntu-test')));
    expect(desktop, contains('os: [macos-latest, windows-latest]'));
    expect(
      desktop,
      contains(
        'timeout-minutes: 2\n        run: dart run melos:melos run native:verify',
      ),
    );
    expect(
      desktop,
      contains(
        'timeout-minutes: 20\n        run: dart run melos:melos run test:noir',
      ),
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
        '        run: dart run melos:melos run test:signals';

    expect(companionTest.allMatches(workflow), hasLength(2));
    expect(_job(workflow, 'ubuntu-test'), contains(companionTest));
    expect(_job(workflow, 'desktop-test'), contains(companionTest));

    final analyze = _job(workflow, 'analyze');
    expect(
      analyze,
      contains(
        'timeout-minutes: 2\n'
        '        run: dart run melos:melos run format:signals',
      ),
    );
    expect(
      analyze,
      contains(
        'timeout-minutes: 4\n'
        '        run: dart run melos:melos run analyze:signals',
      ),
    );
  });

  test('every platform job also checks the driver package', () {
    const driverTest =
        'timeout-minutes: 8\n'
        '        run: dart run melos:melos run test:driver';

    expect(driverTest.allMatches(workflow), hasLength(2));
    expect(_job(workflow, 'ubuntu-test'), contains(driverTest));
    expect(_job(workflow, 'desktop-test'), contains(driverTest));

    final analyze = _job(workflow, 'analyze');
    expect(
      analyze,
      contains(
        'timeout-minutes: 2\n'
        '        run: dart run melos:melos run format:driver',
      ),
    );
    expect(
      analyze,
      contains(
        'timeout-minutes: 4\n'
        '        run: dart run melos:melos run analyze:driver',
      ),
    );
  });

  test('every Dart job check runs through a workspace Melos script', () {
    for (final name in const <String>[
      'analyze',
      'ubuntu-test',
      'desktop-test',
    ]) {
      final job = _job(workflow, name);
      expect(
        job,
        isNot(contains('working-directory:')),
        reason:
            '$name: a Melos script owns the directory its command runs in, '
            'so the workflow must not name one as well',
      );
      final checks = RegExp(
        r'^        run: (.+)$',
        multiLine: true,
      ).allMatches(job).map((match) => match.group(1)!).toList();
      expect(checks, isNotEmpty, reason: name);
      for (final check in checks) {
        expect(
          check,
          anyOf(
            equals('dart pub get'),
            startsWith('dart run melos:melos run '),
            startsWith('echo "PUB_CACHE='),
          ),
          reason: '$name runs $check outside the Melos scripts',
        );
      }
    }
  });

  test('each CI job caches only the isolated pub cache and always resolves', () {
    expect('actions/cache@'.allMatches(workflow), hasLength(3));
    expect(
      r'path: ${{ runner.temp }}/pub-cache'.allMatches(workflow),
      hasLength(3),
    );
    expect(
      r"key: ${{ runner.os }}-Dart-3.10.0-${{ hashFiles('pubspec.yaml', 'packages/noir/pubspec.yaml', "
              "'packages/noir_driver/pubspec.yaml', "
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
  });

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
