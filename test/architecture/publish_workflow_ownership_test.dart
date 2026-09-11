import 'dart:io';

import 'package:test/test.dart';

const _cacheAction =
    'uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0';

void main() {
  final workflows = <String, String>{
    for (final name in <String>['ci', 'release', 'publish'])
      name: _read('.github/workflows/$name.yml'),
  };
  final publish = workflows['publish']!;

  for (final (name, jobName) in [
    ('release', 'verify'),
    ('publish', 'preflight'),
  ]) {
    test('$name preflight budgets cover CI tests and each bounded stage', () {
      final job = _job(workflows[name]!, jobName);
      final ordinaryBudget = _stepBudget(job, 'Run ordinary tests');
      expect(
        ordinaryBudget,
        greaterThanOrEqualTo(
          _stepBudget(
            _job(workflows['ci']!, 'ubuntu-test'),
            'Run ordinary tests',
          ),
        ),
        reason: 'release validation runs the same ordinary suite as Ubuntu CI',
      );
      final checkBudgets = [
        for (final name in [
          'Install dependencies',
          'Verify bundled native assets',
          'Check formatting',
          'Run strict analysis',
          'Run ordinary tests',
          'Validate documentation links',
          'Validate publish archive',
        ])
          _stepBudget(job, name),
      ];
      expect(checkBudgets, everyElement(greaterThan(0)));
      final jobBudget = int.parse(
        RegExp(
          r'^    timeout-minutes: (\d+)',
          multiLine: true,
        ).firstMatch(job)!.group(1)!,
      );
      expect(
        jobBudget,
        greaterThanOrEqualTo(checkBudgets.reduce((a, b) => a + b)),
        reason: 'the job must cover its individual validation ceilings',
      );
    });
  }

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

  test('workflows pin the official Node 24 cache action consistently', () {
    for (final entry in workflows.entries) {
      final cacheLines = entry.value
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.startsWith('uses: actions/cache@'))
          .toList();
      expect(cacheLines, isNotEmpty, reason: '${entry.key}.yml has no cache');
      expect(
        cacheLines,
        everyElement(equals(_cacheAction)),
        reason: '${entry.key}.yml has a stale or inconsistent cache pin',
      );
    }
  });

  test('publish configuration names Noir and immutable actions', () {
    expect(publish, contains('repository: conceptadev/noir'));
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

  test('publish job owns pinned steps instead of a reusable workflow', () {
    final publishJob = publish.substring(publish.indexOf('  publish:'));

    // A pinned reference to a reusable workflow is not enough. The previous
    // call pinned dart-lang/setup-dart's publish workflow, whose own steps
    // use an unpinned actions/checkout, so every tag run failed before it
    // could publish. The job must therefore own its steps.
    expect(
      publishJob,
      isNot(contains('.github/workflows/')),
      reason: 'publish must not delegate to an external reusable workflow',
    );
    expect(publishJob, contains('runs-on: ubuntu-latest'));
    expect(publishJob, contains('steps:'));
    expect(publishJob, contains('dart pub publish --force'));

    // Republishing an existing version is a hard error on pub.dev, so a
    // re-run or a retagged commit must skip rather than fail.
    expect(publishJob, contains('publish=false'));
    expect(publishJob, contains(r'>> "$GITHUB_OUTPUT"'));
    expect(publishJob, contains("if: steps.state.outputs.publish == 'true'"));
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

String _job(String workflow, String name) {
  final start = workflow.indexOf('  $name:');
  expect(start, isNonNegative, reason: 'missing job $name');
  final end = workflow.indexOf(
    RegExp('^  [a-z][a-z-]+:', multiLine: true),
    start + 3,
  );
  return workflow.substring(start, end < 0 ? workflow.length : end);
}

int _stepBudget(String job, String name) {
  final start = job.indexOf('      - name: $name\n');
  expect(start, isNonNegative, reason: 'missing step $name');
  final end = job.indexOf('      - name:', start + 7);
  final step = job.substring(start, end < 0 ? job.length : end);
  final timeout = RegExp(
    r'^        timeout-minutes: (\d+)',
    multiLine: true,
  ).firstMatch(step);
  expect(timeout, isNotNull, reason: '$name must have an explicit ceiling');
  return int.parse(timeout!.group(1)!);
}
