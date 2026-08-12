import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../scripts/native_build/safe_fs.dart';

void main() {
  late Directory sandbox;
  late Directory repoRoot;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('noir_native_safe_fs.');
    repoRoot = Directory(p.join(sandbox.path, 'repo'))..createSync();
    Directory(p.join(repoRoot.path, '.context')).createSync();
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('creates and cleans only an exact marker-owned run directory', () {
    final run = createOwnedRunDirectory(
      repoRoot: repoRoot,
      runId: '20260811T120000Z-abcdef12',
    );
    File(p.join(run.path, 'evidence.txt')).writeAsStringSync('retained');

    expect(
      File(p.join(run.path, nativeBuildRunMarkerName)).readAsStringSync(),
      nativeBuildRunMarker('20260811T120000Z-abcdef12'),
    );
    cleanupOwnedRunDirectory(repoRoot: repoRoot, runDirectory: run);
    expect(run.existsSync(), isFalse);
    expect(repoRoot.existsSync(), isTrue);
  });

  test('refuses missing or incorrect markers and paths outside .context', () {
    final unmarked = Directory(p.join(repoRoot.path, '.context', 'unmarked'))
      ..createSync(recursive: true);
    expect(
      () =>
          cleanupOwnedRunDirectory(repoRoot: repoRoot, runDirectory: unmarked),
      throwsA(isA<UnsafeNativeBuildPathException>()),
    );

    final outside = Directory(p.join(sandbox.path, 'outside'))..createSync();
    File(
      p.join(outside.path, nativeBuildRunMarkerName),
    ).writeAsStringSync(nativeBuildRunMarker('outside'));
    expect(
      () => cleanupOwnedRunDirectory(repoRoot: repoRoot, runDirectory: outside),
      throwsA(isA<UnsafeNativeBuildPathException>()),
    );
  });

  test('refuses every tracked-artifact destination', () {
    for (final destination in <String>[
      p.join(repoRoot.path, 'native'),
      p.join(repoRoot.path, 'native', 'macos', 'arm64'),
      p.join(repoRoot.path, 'native_manifest.json'),
      p.join(repoRoot.path, 'external', 'opentui'),
      p.join(repoRoot.path, 'lib', 'src', 'ffi', 'abi_contract.dart'),
    ]) {
      expect(
        () => requireUntrackedBuildDestination(
          repoRoot: repoRoot,
          destination: destination,
        ),
        throwsA(isA<UnsafeNativeBuildPathException>()),
        reason: destination,
      );
    }
    expect(
      () => requireUntrackedBuildDestination(
        repoRoot: repoRoot,
        destination: p.join(repoRoot.path, '.context', 'native-build-runs'),
      ),
      returnsNormally,
    );
  });

  test('requires recovery mirrors outside Conductor workspaces', () {
    expect(
      () => requireExternalRecoveryDestination(
        destination: '/Users/me/conductor/workspaces/noir/run/recovery',
        workspaceRoots: const <String>[
          '/Users/me/conductor/workspaces/noir/run',
        ],
      ),
      throwsA(isA<UnsafeNativeBuildPathException>()),
    );
    expect(
      () => requireExternalRecoveryDestination(
        destination: '/Users/me/noir-release-recovery',
        workspaceRoots: const <String>[
          '/Users/me/conductor/workspaces/noir/run',
        ],
      ),
      returnsNormally,
    );
  });
}
