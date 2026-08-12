import 'dart:io';
import 'dart:mirrors';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../scripts/native_build/driver.dart';
import '../../../scripts/native_build/preflight.dart';

void main() {
  test('source mtime normalization preserves directories and Git metadata', () {
    final sandbox = Directory.systemTemp.createTempSync('noir-source-mtime-');
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final source = Directory(p.join(sandbox.path, 'opentui'))..createSync();
    final sourceDirectory = Directory(p.join(source.path, 'packages'))
      ..createSync();
    final sourceFile = File(p.join(sourceDirectory.path, 'build.zig'))
      ..writeAsStringSync('const std = @import("std");');
    final gitDirectory = Directory(p.join(source.path, '.git'))..createSync();
    final gitFile = File(p.join(gitDirectory.path, 'HEAD'))
      ..writeAsStringSync('ref: refs/heads/test\n');
    final originalGitFileMtime = DateTime.utc(2001, 2, 3, 4, 5, 6);
    gitFile.setLastModifiedSync(originalGitFileMtime);
    final originalSourceMtime = source.statSync().modified;
    final originalSourceDirectoryMtime = sourceDirectory.statSync().modified;
    final originalGitDirectoryMtime = gitDirectory.statSync().modified;

    final driver = IoNativeBuildDriver(
      repoRoot: sandbox,
      preflight: _preflight,
      recoveryMirrorRoot: Directory(p.join(sandbox.path, 'recovery')),
    );
    final driverMirror = reflect(driver);
    final driverLibrary = driverMirror.type.owner! as LibraryMirror;
    driverMirror.invoke(
      MirrorSystem.getSymbol('_normalizeSourceMtimes', driverLibrary),
      <Object>[source],
    );

    final normalizedMtime = DateTime.fromMillisecondsSinceEpoch(
      requiredSourceDateEpoch * 1000,
      isUtc: true,
    );
    expect(sourceFile.lastModifiedSync().toUtc(), normalizedMtime);
    expect(sourceDirectory.statSync().modified, originalSourceDirectoryMtime);
    expect(source.statSync().modified, originalSourceMtime);
    expect(gitFile.lastModifiedSync().toUtc(), originalGitFileMtime);
    expect(gitDirectory.statSync().modified, originalGitDirectoryMtime);
  });
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
);
