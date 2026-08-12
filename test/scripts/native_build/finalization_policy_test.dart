import 'dart:io';
import 'dart:mirrors';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../scripts/native_build/driver.dart';
import '../../../scripts/native_build/preflight.dart';
import '../../../scripts/native_build/workflow.dart';

void main() {
  test(
    'does not designate success before the recovery mirror exists',
    () async {
      final sandbox = Directory.systemTemp.createTempSync(
        'noir-finalization-policy-',
      );
      addTearDown(() => sandbox.deleteSync(recursive: true));

      final repoRoot = Directory(p.join(sandbox.path, 'repo'))..createSync();
      final evidenceDirectory = Directory(p.join(repoRoot.path, 'evidence'))
        ..createSync();
      final recoveryDirectory = Directory(p.join(repoRoot.path, 'recovery'))
        ..createSync();
      final runnerArchive = File(p.join(recoveryDirectory.path, 'runner.tar'))
        ..writeAsStringSync('runner');
      File('${runnerArchive.path}.sha256').writeAsStringSync('runner-hash');
      final blockedMirror = File(p.join(sandbox.path, 'blocked-mirror'))
        ..writeAsStringSync('not a directory');

      final driver = IoNativeBuildDriver(
        repoRoot: repoRoot,
        preflight: _preflight,
        recoveryMirrorRoot: Directory(blockedMirror.path),
        now: () => DateTime.utc(2026, 8, 12),
      );
      final driverMirror = reflect(driver);
      final driverLibrary = driverMirror.type.owner! as LibraryMirror;
      Symbol privateSymbol(String name) =>
          MirrorSystem.getSymbol(name, driverLibrary);

      driverMirror
        ..setField(privateSymbol('_startedAt'), DateTime.utc(2026, 8, 12))
        ..setField(privateSymbol('_runId'), '20260812T000000Z-policy')
        ..setField(privateSymbol('_evidenceDirectory'), evidenceDirectory)
        ..setField(privateSymbol('_recoveryDirectory'), recoveryDirectory)
        ..setField(privateSymbol('_runnerArchive'), runnerArchive)
        ..setField(privateSymbol('_runnerArchiveHash'), 'runner-hash')
        ..setField(privateSymbol('_recipeDigest'), 'recipe-digest')
        ..setField(privateSymbol('_imageDigest'), 'sha256:image');

      await expectLater(
        driver.finalizeSuccess(
          const NativeBuildResult(
            rootA: <NativeArtifactEvidence>[],
            rootB: <NativeArtifactEvidence>[],
            normalizedHashes: <String, String>{},
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(
        File(p.join(evidenceDirectory.path, 'success.json')).existsSync(),
        isFalse,
      );
    },
  );
}

const _preflight = PreflightSnapshot(
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
  noirCommit: 'noir-commit',
  noirTree: 'noir-tree',
  openTuiTree: requiredOpenTuiTree,
  dockerVersion: 'docker-version',
);
