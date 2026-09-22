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
    ('release', 'announce'),
    ('publish', 'preflight'),
    ('publish', 'test-package'),
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
      // A workflow in this repository is checked out at the same commit, so
      // it has no SHA of its own to pin. Everything else must be immutable.
      if (line.startsWith('uses: ./.github/workflows/')) continue;
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
    expect(preflight, contains('dart pub publish --dry-run'));
    // The ladder ends with `native:verify`, so running it again afterwards
    // would only repeat a digest check that cannot have changed.
    // `melos_workspace_ownership_test` pins what the ladder contains.
    expect(
      'dart run melos:melos run native:verify'.allMatches(preflight),
      isEmpty,
    );
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
    expect(publishJob, contains("needs.preflight.outputs.publish == 'true'"));
  });

  test('nothing is uploaded until the packaged assets load everywhere', () {
    final publishJob = _job(publish, 'publish');
    final packaged = _job(publish, 'test-package');

    // Publication is irreversible, so the cross-platform check on the bytes
    // being shipped runs before the upload, not after it.
    expect(publishJob, contains('needs: [preflight, test-package]'));
    expect(packaged, contains('dart run noir:health_check'));
    expect(packaged, contains('rm -rf native native_manifest.json'));
    expect(packaged, contains('ubuntu-latest'));
    expect(packaged, contains('macos-latest'));
    expect(packaged, contains('windows-latest'));
    // Skipped for a companion tag, and a skipped `needs` skips its
    // dependents, so the publish job must name the result rather than
    // silently inherit a skip.
    expect(publishJob, contains("needs.test-package.result != 'failure'"));
    expect(publishJob, contains("needs.test-package.result != 'cancelled'"));
  });

  test('a release run never cancels another release run', () {
    // GitHub keeps one pending run per concurrency group and cancels the one
    // it displaces. A group shared across tags would drop a companion release
    // queued behind Noir without saying so.
    expect(publish, contains('cancel-in-progress: false'));
    expect(
      publish,
      contains(r'group: publish-${{ github.ref }}'),
      reason: 'the group must be per tag, not per repository',
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

  test('the announcement is reachable only through a successful publish', () {
    final announce = _job(publish, 'announce');

    // The defect: release.yml used to trigger on `noir-v*` itself, so the
    // GitHub release raced the upload and could go public while approval was
    // pending or after publication failed. It is now a called workflow with
    // no trigger of its own, and ordinary `needs` semantics skip it unless
    // `publish` actually succeeded.
    expect(announce, contains('uses: ./.github/workflows/release.yml'));
    expect(announce, contains('needs: [preflight, publish]'));
    expect(
      announce,
      isNot(contains('always()')),
      reason: 'a skipped or failed publish must skip the announcement',
    );
    // Only Noir carries the bundled native artifacts a release attaches.
    expect(announce, contains("needs.preflight.outputs.package == 'noir'"));
    // Permissions only flow down a reusable-workflow chain, so the caller
    // grants what the announcement needs and nothing else.
    expect(announce, contains('contents: write'));
    expect(
      announce,
      isNot(contains('id-token')),
      reason: 'announcing needs no publish credential',
    );

    expect(
      workflows['release'],
      isNot(contains('push:')),
      reason: 'release.yml must not start itself on a tag',
    );
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

  test('the record survives a skipped publish but not a failed one', () {
    // A skipped `needs` skips its dependents, and `publish` is skipped
    // whenever the version is already on pub.dev — the re-run after a
    // half-finished release, which is exactly when the record is the thing
    // still missing. Without an explicit condition this job would silently
    // never run in that case, and the run would still be green.
    final recordJob = _job(publish, 'record');

    expect(recordJob, contains('always()'));
    expect(recordJob, contains("needs.preflight.result == 'success'"));
    expect(recordJob, contains("needs.publish.result != 'failure'"));
    expect(recordJob, contains("needs.publish.result != 'cancelled'"));
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
    expect(publishJob, contains('needs: [preflight, test-package]'));
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
