import 'dart:io';

import 'package:test/test.dart';

import '../../../scripts/build_opentui_candidates.dart' as application;
import '../../../scripts/native_build/driver.dart';
import '../../../scripts/native_build/preflight.dart';

void main() {
  test(
    'plan and explicit execution delegate to distinct injected actions',
    () async {
      final calls = <String>[];
      final snapshot = _snapshot();

      final planExit = await application.runNativeBuildCommand(
        <String>['--plan'],
        repoRoot: Directory.current,
        checkPreflight: (_) async {
          calls.add('preflight-plan');
          return snapshot;
        },
        printPlan: (_, _) {
          calls.add('plan');
        },
        executeBuild: (_, _) async {
          calls.add('execute-plan');
        },
        emitError: (message) => calls.add('error:$message'),
      );
      expect(planExit, 0);
      expect(calls, <String>['preflight-plan', 'plan']);

      calls.clear();
      final executeExit = await application.runNativeBuildCommand(
        <String>['--execute-native-build'],
        repoRoot: Directory.current,
        checkPreflight: (_) async {
          calls.add('preflight-execute');
          return snapshot;
        },
        printPlan: (_, _) {
          calls.add('plan-execute');
        },
        executeBuild: (_, _) async {
          calls.add('execute');
        },
        emitError: (message) => calls.add('error:$message'),
      );
      expect(executeExit, 0);
      expect(calls, <String>['preflight-execute', 'execute']);
    },
  );

  test('usage and operation failures return distinct nonzero exits', () async {
    final errors = <String>[];
    final usageExit = await application.runNativeBuildCommand(
      const <String>['--execute'],
      repoRoot: Directory.current,
      checkPreflight: (_) async => _snapshot(),
      printPlan: (_, _) {},
      executeBuild: (_, _) async {},
      emitError: errors.add,
    );
    expect(usageExit, 64);
    expect(errors.single, contains('Usage:'));

    errors.clear();
    final operationExit = await application.runNativeBuildCommand(
      const <String>['--plan'],
      repoRoot: Directory.current,
      checkPreflight: (_) async => throw StateError('forced failure'),
      printPlan: (_, _) {},
      executeBuild: (_, _) async {},
      emitError: errors.add,
    );
    expect(operationExit, 1);
    expect(errors.single, contains('forced failure'));
  });

  test('packaged CLI path follows the dart build bundle layout', () {
    expect(
      packagedCliExecutablePath('/tmp/output', 'bin/health_check.dart'),
      '/tmp/output/bundle/bin/health_check',
    );
  });
}

PreflightSnapshot _snapshot() => const PreflightSnapshot(
  repoRootMatches: true,
  originUrl: requiredNoirOrigin,
  headContainsPreparation: true,
  worktreeClean: true,
  recipeCommitted: true,
  gitlink: requiredOpenTuiCommit,
  submoduleHead: requiredOpenTuiCommit,
  submoduleClean: true,
  dockerAvailable: true,
  contextIgnored: true,
);
