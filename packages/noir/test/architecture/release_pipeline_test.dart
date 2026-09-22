import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// What the release pipeline does on a tag, decided without pushing one.
///
/// The job graph is the part of this repository that a real release would
/// otherwise exercise first. These cases read the workflow itself and evaluate
/// each job's condition against the outcomes a release can actually produce,
/// so a wrong `if:` or a wrong `needs:` fails here rather than in front of a
/// published version.
void main() {
  final workflow =
      loadYaml(File('../../.github/workflows/publish.yml').readAsStringSync())
          as YamlMap;
  final jobs = workflow['jobs'] as YamlMap;

  /// The tag has been resolved and every gate before `publish` has passed.
  Map<String, _JobState> releasing(String package) => <String, _JobState>{
    'preflight': _JobState.success({
      'package': package,
      'publish': 'true',
      'directory': 'packages/$package',
    }),
  };

  group('a Noir release', () {
    test('announces and records once the upload succeeds', () {
      final state = releasing('noir')
        ..['test-package'] = _JobState.success()
        ..['publish'] = _JobState.success();

      expect(_runs(jobs, 'publish', state), isTrue);
      expect(_runs(jobs, 'announce', state), isTrue);
      expect(_runs(jobs, 'record', state), isTrue);
    });

    test('cannot start anything while approval is still pending', () {
      // An environment holds `publish` before it reaches a runner, and it
      // reports no result at all until a reviewer decides. Nothing downstream
      // is evaluated in that window, so the guarantee is the edge itself:
      // both the announcement and the record wait on `publish`.
      for (final job in const ['announce', 'record']) {
        expect(
          _needs(jobs, job),
          contains('publish'),
          reason: '$job must not be reachable around the approval gate',
        );
      }
      expect(
        _needs(jobs, 'publish'),
        contains('test-package'),
        reason: 'and approval is only asked for once the assets are proven',
      );
    });

    test('announces nothing when the upload fails', () {
      final state = releasing('noir')
        ..['test-package'] = _JobState.success()
        ..['publish'] = const _JobState('failure');

      expect(_runs(jobs, 'announce', state), isFalse);
      expect(_runs(jobs, 'record', state), isFalse);
    });

    test('announces nothing when the reviewer cancels', () {
      final state = releasing('noir')
        ..['test-package'] = _JobState.success()
        ..['publish'] = const _JobState('cancelled');

      expect(_runs(jobs, 'announce', state), isFalse);
      expect(_runs(jobs, 'record', state), isFalse);
    });

    test('uploads nothing when the packaged assets fail a platform', () {
      final state = releasing('noir')
        ..['test-package'] = const _JobState('failure');

      expect(_runs(jobs, 'publish', state), isFalse);
      expect(_runs(jobs, 'announce', state), isFalse);
    });
  });

  group('a re-pushed tag whose version is already out', () {
    // preflight succeeds and reports nothing to do, so `publish` is skipped —
    // and a skipped `needs` skips its dependents unless a job says otherwise.
    Map<String, _JobState> alreadyPublished() => <String, _JobState>{
      'preflight': _JobState.success({
        'package': 'noir',
        'publish': 'false',
        'directory': 'packages/noir',
      }),
      'test-package': const _JobState('skipped'),
      'publish': const _JobState('skipped'),
    };

    test('publishes nothing a second time', () {
      expect(_runs(jobs, 'publish', alreadyPublished()), isFalse);
    });

    test('announces nothing, because nothing new shipped', () {
      expect(_runs(jobs, 'announce', alreadyPublished()), isFalse);
    });

    test('still reconciles the publication record', () {
      // The recovery case: the upload landed, the record did not. Re-pushing
      // the tag must be able to finish the job.
      expect(_runs(jobs, 'record', alreadyPublished()), isTrue);
    });
  });

  group('a companion release', () {
    test('publishes even though the platform check does not apply', () {
      // `test-package` is Noir-only, and a skipped `needs` would skip the
      // upload if the condition did not name the result.
      final state = releasing('noir_driver')
        ..['test-package'] = const _JobState('skipped');

      expect(_runs(jobs, 'publish', state), isTrue);
    });

    test('never cuts a GitHub release', () {
      // Only Noir carries the bundled native artifacts a release attaches.
      for (final package in const ['noir_driver', 'noir_signals']) {
        final state = releasing(package)
          ..['test-package'] = const _JobState('skipped')
          ..['publish'] = _JobState.success();

        expect(
          _runs(jobs, 'announce', state),
          isFalse,
          reason: '$package has no native assets to attach',
        );
        expect(_runs(jobs, 'record', state), isTrue);
      }
    });

    test('runs no native packaging or platform matrix', () {
      final state = releasing('noir_driver');

      expect(_runs(jobs, 'test-package', state), isFalse);
    });
  });

  group('a blocked or broken preflight', () {
    test('stops the whole chain', () {
      const state = <String, _JobState>{'preflight': _JobState('failure')};

      for (final job in const [
        'test-package',
        'publish',
        'announce',
        'record',
      ]) {
        expect(_runs(jobs, job, state), isFalse, reason: job);
      }
    });
  });
}

/// One job's outcome, and the outputs it published.
class _JobState {
  const _JobState(this.result, [this.outputs = const <String, String>{}]);

  factory _JobState.success([Map<String, String> outputs = const {}]) =>
      _JobState('success', outputs);

  /// `success`, `failure`, `cancelled` or `skipped`, as GitHub reports it to
  /// a dependent job.
  final String result;
  final Map<String, String> outputs;
}

/// Whether GitHub would run [name] given the outcomes in [state].
///
/// Two rules, in the order GitHub applies them: a job whose `needs` did not
/// all succeed is skipped unless its condition opts out with `always()`, and
/// then the condition itself decides.
bool _runs(YamlMap jobs, String name, Map<String, _JobState> state) {
  final job = jobs[name] as YamlMap;
  final needs = _needs(jobs, name);
  final condition = (job['if'] as String?)?.trim();
  final optsOut = condition != null && condition.contains('always()');

  if (!optsOut) {
    for (final dependency in needs) {
      if (state[dependency]?.result != 'success') return false;
    }
  }
  if (condition == null) return true;
  return _evaluate(condition, state);
}

/// The jobs [name] waits for.
List<String> _needs(YamlMap jobs, String name) =>
    switch ((jobs[name] as YamlMap)['needs']) {
      final String one => <String>[one],
      final YamlList many => many.cast<String>().toList(),
      _ => const <String>[],
    };

/// Evaluates the subset of the expression language these conditions use:
/// `always()`, `&&`, `==`, `!=`, string literals, `needs.<job>.result` and
/// `needs.<job>.outputs.<name>`. Any `||` would need adding here first, which
/// is deliberate — an unreadable release condition is its own defect.
bool _evaluate(String condition, Map<String, _JobState> state) {
  expect(
    condition,
    isNot(contains('||')),
    reason: 'release conditions stay conjunctive so they can be reasoned about',
  );
  return condition
      .split('&&')
      .map((term) => term.trim())
      .where((term) => term.isNotEmpty && term != 'always()')
      .every((term) => _comparison(term, state));
}

bool _comparison(String term, Map<String, _JobState> state) {
  final match = RegExp(r"^(\S+)\s*(==|!=)\s*'([^']*)'$").firstMatch(term);
  expect(match, isNotNull, reason: 'unsupported condition term: $term');
  final actual = _read(match!.group(1)!, state);
  final expected = match.group(3)!;
  return match.group(2) == '==' ? actual == expected : actual != expected;
}

String? _read(String reference, Map<String, _JobState> state) {
  final result = RegExp(r'^needs\.([\w-]+)\.result$').firstMatch(reference);
  if (result != null) return state[result.group(1)!]?.result;

  final output = RegExp(
    r'^needs\.([\w-]+)\.outputs\.([\w-]+)$',
  ).firstMatch(reference);
  expect(output, isNotNull, reason: 'unsupported reference: $reference');
  return state[output!.group(1)!]?.outputs[output.group(2)!];
}
