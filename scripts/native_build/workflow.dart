import 'inspect.dart';
import 'plan.dart';

final class NativeArtifactEvidence {
  const NativeArtifactEvidence({
    required this.targetName,
    required this.rawSha256,
    required this.normalizedSha256,
  });

  final String targetName;
  final String rawSha256;
  final String normalizedSha256;
}

final class NativeBuildResult {
  const NativeBuildResult({
    required this.rootA,
    required this.rootB,
    required this.normalizedHashes,
  });

  final List<NativeArtifactEvidence> rootA;
  final List<NativeArtifactEvidence> rootB;
  final Map<String, String> normalizedHashes;
}

abstract interface class NativeBuildDriver {
  Future<void> begin();

  Future<void> prepareRoot(NativeBuildRoot root);

  Future<NativeArtifactEvidence> buildAndInspect(
    NativeBuildRoot root,
    NativeBuildTarget target,
  );

  Future<void> verifyRoot(NativeBuildRoot root);

  Future<void> verifyHealthAndPackage(NativeBuildResult result);

  Future<void> verifyProtectedState();

  Future<void> finalizeSuccess(NativeBuildResult result);

  Future<void> recordFailure(Object error, StackTrace stackTrace);
}

final class NativeBuildWorkflowException implements Exception {
  const NativeBuildWorkflowException(this.message);

  final String message;

  @override
  String toString() => 'Native build workflow failed: $message';
}

final class NativeBuildWorkflow {
  const NativeBuildWorkflow(this.driver);

  final NativeBuildDriver driver;

  Future<NativeBuildResult> execute() async {
    try {
      await driver.begin();
      final evidenceByRoot = <String, List<NativeArtifactEvidence>>{};
      for (final root in nativeBuildRoots) {
        await driver.prepareRoot(root);
        final evidence = <NativeArtifactEvidence>[];
        for (final target in root.targets) {
          evidence.add(await driver.buildAndInspect(root, target));
        }
        await driver.verifyRoot(root);
        evidenceByRoot[root.label] = evidence;
      }

      final rootA = evidenceByRoot['root-a']!;
      final rootB = evidenceByRoot['root-b']!;
      final rootAHashes = <String, String>{
        for (final artifact in rootA)
          artifact.targetName: artifact.normalizedSha256,
      };
      final rootBHashes = <String, String>{
        for (final artifact in rootB)
          artifact.targetName: artifact.normalizedSha256,
      };
      try {
        verifyIdenticalArtifacts(rootAHashes, rootBHashes);
      } on ArtifactInspectionException catch (error) {
        throw NativeBuildWorkflowException(error.message);
      }
      final result = NativeBuildResult(
        rootA: rootA,
        rootB: rootB,
        normalizedHashes: rootAHashes,
      );
      await driver.verifyHealthAndPackage(result);
      await driver.verifyProtectedState();
      await driver.finalizeSuccess(result);
      return result;
    } on Object catch (error, stackTrace) {
      await driver.recordFailure(error, stackTrace);
      rethrow;
    }
  }
}
