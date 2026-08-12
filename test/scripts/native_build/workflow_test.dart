import 'package:test/test.dart';

import '../../../scripts/native_build/plan.dart';
import '../../../scripts/native_build/workflow.dart';

void main() {
  test(
    'workflow builds both roots in their approved orders and finalizes',
    () async {
      final driver = _FakeDriver();
      final result = await NativeBuildWorkflow(driver).execute();

      expect(driver.builds, <String>[
        for (final target in nativeBuildTargets) 'root-a/${target.name}',
        for (final target in nativeBuildTargets.reversed)
          'root-b/${target.name}',
      ]);
      expect(driver.preparedRoots, <String>['root-a', 'root-b']);
      expect(driver.verifiedRoots, <String>['root-a', 'root-b']);
      expect(driver.healthChecks, 1);
      expect(driver.protectedChecks, 1);
      expect(driver.finalizations, 1);
      expect(driver.failures, isEmpty);
      expect(result.normalizedHashes, hasLength(6));
    },
  );

  test(
    'workflow records failure and never designates mismatched candidates',
    () async {
      final driver = _FakeDriver(mismatchedTarget: 'aarch64-macos');

      await expectLater(
        NativeBuildWorkflow(driver).execute(),
        throwsA(isA<NativeBuildWorkflowException>()),
      );
      expect(driver.healthChecks, 0);
      expect(driver.finalizations, 0);
      expect(driver.failures, hasLength(1));
      expect(driver.failures.single, contains('aarch64-macos'));
    },
  );
}

final class _FakeDriver implements NativeBuildDriver {
  _FakeDriver({this.mismatchedTarget});

  final String? mismatchedTarget;
  final List<String> builds = <String>[];
  final List<String> preparedRoots = <String>[];
  final List<String> verifiedRoots = <String>[];
  final List<String> failures = <String>[];
  int healthChecks = 0;
  int protectedChecks = 0;
  int finalizations = 0;

  @override
  Future<void> begin() async {}

  @override
  Future<NativeArtifactEvidence> buildAndInspect(
    NativeBuildRoot root,
    NativeBuildTarget target,
  ) async {
    builds.add('${root.label}/${target.name}');
    final suffix = root.label == 'root-b' && mismatchedTarget == target.name
        ? '-different'
        : '';
    return NativeArtifactEvidence(
      targetName: target.name,
      rawSha256: 'raw-${root.label}-${target.name}',
      normalizedSha256: 'normalized-${target.name}$suffix',
    );
  }

  @override
  Future<void> finalizeSuccess(NativeBuildResult result) async {
    finalizations++;
  }

  @override
  Future<void> prepareRoot(NativeBuildRoot root) async {
    preparedRoots.add(root.label);
  }

  @override
  Future<void> recordFailure(Object error, StackTrace stackTrace) async {
    failures.add('$error');
  }

  @override
  Future<void> verifyHealthAndPackage(NativeBuildResult result) async {
    healthChecks++;
  }

  @override
  Future<void> verifyProtectedState() async {
    protectedChecks++;
  }

  @override
  Future<void> verifyRoot(NativeBuildRoot root) async {
    verifiedRoots.add(root.label);
  }
}
