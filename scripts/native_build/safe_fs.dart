import 'dart:io';

import 'package:path/path.dart' as p;

const String nativeBuildRunMarkerName = '.noir-native-build-run';
const String _markerVersion = 'noir-native-build-run-v1';

String nativeBuildRunMarker(String runId) => '$_markerVersion\n$runId\n';

final class UnsafeNativeBuildPathException implements Exception {
  const UnsafeNativeBuildPathException(this.message);

  final String message;

  @override
  String toString() => 'Unsafe native build path: $message';
}

Directory createOwnedRunDirectory({
  required Directory repoRoot,
  required String runId,
}) {
  if (!RegExp(r'^\d{8}T\d{6}Z-[a-f0-9]{8}$').hasMatch(runId)) {
    throw UnsafeNativeBuildPathException('invalid run ID $runId');
  }
  final contextRoot = p.normalize(
    p.absolute(p.join(repoRoot.path, '.context', 'native-build-runs')),
  );
  final runPath = p.normalize(p.join(contextRoot, runId));
  if (!p.isWithin(contextRoot, runPath)) {
    throw const UnsafeNativeBuildPathException('run escaped .context/');
  }
  final runDirectory = Directory(runPath);
  if (runDirectory.existsSync()) {
    _requireMarker(runDirectory, runId);
    return runDirectory;
  }
  runDirectory.createSync(recursive: true);
  File(
    p.join(runPath, nativeBuildRunMarkerName),
  ).writeAsStringSync(nativeBuildRunMarker(runId), flush: true);
  return runDirectory;
}

void cleanupOwnedRunDirectory({
  required Directory repoRoot,
  required Directory runDirectory,
}) {
  final contextRoot = p.normalize(
    p.absolute(p.join(repoRoot.path, '.context', 'native-build-runs')),
  );
  final runPath = p.normalize(p.absolute(runDirectory.path));
  if (!p.isWithin(contextRoot, runPath) || p.equals(contextRoot, runPath)) {
    throw UnsafeNativeBuildPathException('$runPath is not an owned run path');
  }
  _requireMarker(runDirectory, p.basename(runPath));
  runDirectory.deleteSync(recursive: true);
}

void _requireMarker(Directory directory, String runId) {
  final marker = File(p.join(directory.path, nativeBuildRunMarkerName));
  if (!marker.existsSync() ||
      marker.readAsStringSync() != nativeBuildRunMarker(runId)) {
    throw UnsafeNativeBuildPathException(
      '${directory.path} lacks its exact run marker',
    );
  }
}

void requireUntrackedBuildDestination({
  required Directory repoRoot,
  required String destination,
}) {
  final root = p.normalize(p.absolute(repoRoot.path));
  final context = p.join(root, '.context');
  final candidate = p.normalize(p.absolute(destination));
  if (!p.isWithin(context, candidate)) {
    throw UnsafeNativeBuildPathException(
      '$candidate is not beneath the ignored .context/ directory',
    );
  }
}

void requireExternalRecoveryDestination({
  required String destination,
  required List<String> workspaceRoots,
}) {
  final candidate = p.normalize(p.absolute(destination));
  if (candidate == p.rootPrefix(candidate) || candidate == p.current) {
    throw UnsafeNativeBuildPathException('$candidate is too broad');
  }
  for (final workspaceRoot in workspaceRoots) {
    final root = p.normalize(p.absolute(workspaceRoot));
    if (p.equals(candidate, root) || p.isWithin(root, candidate)) {
      throw UnsafeNativeBuildPathException(
        '$candidate is inside Conductor workspace $root',
      );
    }
  }
  if (candidate.contains(
    '${p.separator}conductor${p.separator}workspaces${p.separator}',
  )) {
    throw UnsafeNativeBuildPathException(
      '$candidate is inside a Conductor workspace hierarchy',
    );
  }
}
