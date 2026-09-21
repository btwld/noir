import 'dart:io';

import 'package:test/test.dart';

const _cacheAction =
    'uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0';

void main() {
  final workflows = <String, String>{
    for (final name in <String>['ci', 'release', 'publish'])
      name: _read('../../.github/workflows/$name.yml'),
  };
  final publish = workflows['publish']!;

  for (final (name, jobName) in [
    ('release', 'verify'),
    ('publish', 'preflight'),
  ]) {
    test('$name validation is bounded step by step and as a whole', () {
      // Not which steps exist — that is the workflow's business — but that
      // every step it does declare is bounded, and that the job ceiling
      // covers the sum. An unbounded release step is a release that can hang
      // holding the publish queue.
      final job = _job(workflows[name]!, jobName);
      final steps = RegExp(
        r'^      - name: (.+)$',
        multiLine: true,
      ).allMatches(job).map((match) => match.group(1)!).toList();
      expect(steps, isNotEmpty);

      final budgets = <int>[];
      for (final step in steps) {
        final budget = _optionalStepBudget(job, step);
        if (budget != null) budgets.add(budget);
        // Every step that runs work of its own carries its own ceiling.
        // Checkout, SDK setup, cache restore and artifact upload are bounded
        // by the action itself; a `dart`, `melos` or `npm` invocation is not.
        if (_runsAToolchain(job, step)) {
          expect(
            budget,
            isNotNull,
            reason: '$name/$jobName step "$step" has no ceiling',
          );
        }
      }
      final jobBudget = int.parse(
        RegExp(
          r'^    timeout-minutes: (\d+)',
          multiLine: true,
        ).firstMatch(job)!.group(1)!,
      );
      expect(
        jobBudget,
        greaterThanOrEqualTo(budgets.reduce((a, b) => a + b)),
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
    // Only a Melos release tag publishes. `v*` would match the unprefixed
    // tags used before 0.0.3, which name no package, and a branch trigger
    // would publish on an ordinary merge.
    expect(publish, contains("tags: ['*-v*']"));
    expect(publish, isNot(contains('branches:')));
    expect(publish, isNot(contains('workflow_dispatch:')));

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
    final preflight = _job(publish, 'preflight');
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
    // Every release rule lives in `tool/release.dart`, which
    // `test/tools/release_cli_test.dart` exercises on ordinary CI. The
    // workflow calls it and must not grow a second copy in shell.
    expect(preflight, contains('tool/release.dart resolve-tag'));
    expect(preflight, contains('tool/release.dart check'));
    expect(preflight, contains('tool/release.dart preflight'));
    expect(
      preflight,
      isNot(contains('curl')),
      reason: 'the registry query belongs to the tool, not to the workflow',
    );
    expect(
      preflight,
      isNot(contains('semver=')),
      reason: 'version parsing belongs to the tool, not to the workflow',
    );
    // A companion ships against the Noir in this same commit, so a release
    // runs the whole ladder rather than one package's slice of it.
    expect(preflight, contains('dart run melos:melos run verify'));
    expect(preflight, contains('dart run melos:melos run native:verify'));
    expect(preflight, contains('dart pub publish --dry-run'));
    expect(preflight, isNot(contains('continue-on-error')));
    expect(preflight, isNot(contains('.dart_tool')));
  });

  test('publish job owns pinned steps instead of a reusable workflow', () {
    final publishJob = _job(publish, 'publish');

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
    // re-run or a retagged commit must skip rather than fail. The decision is
    // the preflight job's, so the publish job is simply conditional on it.
    expect(
      publishJob,
      contains("if: needs.preflight.outputs.publish == 'true'"),
    );
  });

  test('publication waits for an approval a workflow edit cannot skip', () {
    final publishJob = _job(publish, 'publish');

    // pub.dev reflects the environment in the OIDC subject claim, so
    // requiring one here is the release approval boundary rather than a
    // decoration: someone who can push to the repository still cannot
    // publish by editing this file.
    expect(publishJob, contains('environment:'));
    expect(publishJob, contains('name: pub.dev'));
  });

  test('the publication record is proposed, never pushed to main', () {
    final recordJob = _job(publish, 'record');

    // publication.json caches pub.dev and the availability labels derive from
    // it, so it is regenerated rather than hand-written — but it is still
    // website content, and it goes through review.
    expect(recordJob, contains('needs: [preflight, publish]'));
    expect(recordJob, contains('tool/release.dart record'));
    expect(recordJob, contains('gh pr create'));
    expect(
      recordJob,
      isNot(contains('git push origin main')),
      reason: 'the record must not land without review',
    );
  });

  test('publication itself never goes through Melos', () {
    // `melos publish` sorts `dependencies` and `dev_dependencies` into one
    // graph. Noir dev-depends on noir_driver and noir_driver depends on Noir,
    // so it sees a cycle, falls back to name length, and offers noir_driver
    // first — before the Noir it requires exists.
    final invocations = RegExp(
      r'^\s*run: (.+)$',
      multiLine: true,
    ).allMatches(publish).map((match) => match.group(1)!);
    for (final invocation in invocations) {
      expect(invocation, isNot(contains('melos publish')), reason: invocation);
      expect(invocation, isNot(contains('melos version')), reason: invocation);
    }
    expect(publish, contains('dart pub publish --force'));
  });

  test('OIDC publication depends on preflight with least privilege', () {
    expect(publish, contains('permissions:\n  contents: read'));
    final publishJob = _job(publish, 'publish');
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
  // Anchored: `publish` is also a job output key at deeper indentation, and
  // an unanchored search finds that first.
  final start = workflow.indexOf(RegExp('^  $name:', multiLine: true));
  expect(start, isNonNegative, reason: 'missing job $name');
  final end = workflow.indexOf(
    RegExp('^  [a-z][a-z-]+:', multiLine: true),
    start + 3,
  );
  return workflow.substring(start, end < 0 ? workflow.length : end);
}

/// The body of one named step, or null when the job has no such step.
String? _step(String job, String name) {
  final start = job.indexOf('      - name: $name\n');
  if (start < 0) return null;
  final end = job.indexOf('      - name:', start + 7);
  return job.substring(start, end < 0 ? job.length : end);
}

/// Whether [name] runs a Dart, Melos or Node command rather than an action.
bool _runsAToolchain(String job, String name) {
  final step = _step(job, name);
  if (step == null) return false;
  final commands = RegExp(
    r'^\s*run: (.+)$',
    multiLine: true,
  ).allMatches(step).map((match) => match.group(1)!);
  return commands.any(
    (command) =>
        command.startsWith('dart ') ||
        command.startsWith('npm ') ||
        command.contains('melos:melos'),
  );
}

int? _optionalStepBudget(String job, String name) {
  final start = job.indexOf('      - name: $name\n');
  if (start < 0) return null;
  final end = job.indexOf('      - name:', start + 7);
  final step = job.substring(start, end < 0 ? job.length : end);
  final timeout = RegExp(
    r'^        timeout-minutes: (\d+)',
    multiLine: true,
  ).firstMatch(step);
  return timeout == null ? null : int.parse(timeout.group(1)!);
}
