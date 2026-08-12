import 'dart:io';
import 'dart:mirrors';

import 'package:noir/src/ffi/abi_contract.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../scripts/native_build/driver.dart';
import '../../../scripts/native_build/plan.dart';
import '../../../scripts/native_build/preflight.dart';

void main() {
  test(
    'selects and renames the pinned Windows DLL without designating its PDB',
    () async {
      final sandbox = Directory.systemTemp.createTempSync(
        'noir-windows-output-policy-',
      );
      addTearDown(() => sandbox.deleteSync(recursive: true));

      final repoRoot = Directory(p.join(sandbox.path, 'repo'))..createSync();
      final runDirectory = Directory(p.join(repoRoot.path, '.context', 'run'))
        ..createSync(recursive: true);
      final evidenceDirectory = Directory(p.join(runDirectory.path, 'evidence'))
        ..createSync();
      final logsDirectory = Directory(
        p.join(evidenceDirectory.path, 'commands'),
      )..createSync();
      final sourceDirectory = Directory(
        p.join(runDirectory.path, 'sources', 'root-a', 'opentui'),
      )..createSync(recursive: true);
      final root = nativeBuildRoots.first;
      final target = nativeBuildTargets.singleWhere(
        (candidate) => candidate.name == 'x86_64-windows',
      );
      final builtDirectory = Directory(
        p.join(
          runDirectory.path,
          'build-roots',
          root.label,
          'output',
          'lib',
          target.name,
        ),
      )..createSync(recursive: true);
      final installedDll = File(p.join(builtDirectory.path, 'opentui.dll'))
        ..writeAsBytesSync(<int>[0x4d, 0x5a]);
      File(
        p.join(builtDirectory.path, 'opentui.pdb'),
      ).writeAsBytesSync(<int>[0x50, 0x44, 0x42]);

      final runner = _RecordingRunner();
      final driver = IoNativeBuildDriver(
        repoRoot: repoRoot,
        preflight: _preflight,
        runner: runner,
        now: () => DateTime.utc(2026, 8, 12),
        recoveryMirrorRoot: Directory(p.join(sandbox.path, 'recovery')),
      );
      final driverMirror = reflect(driver);
      final driverLibrary = driverMirror.type.owner! as LibraryMirror;
      Symbol privateSymbol(String name) =>
          MirrorSystem.getSymbol(name, driverLibrary);

      driverMirror
        ..setField(privateSymbol('_runDirectory'), runDirectory)
        ..setField(privateSymbol('_evidenceDirectory'), evidenceDirectory)
        ..setField(privateSymbol('_logsDirectory'), logsDirectory)
        ..setField(
          privateSymbol('_imageDigest'),
          'sha256:windows-output-policy-test',
        );
      final sourceRoots =
          driverMirror.getField(privateSymbol('_sourceRoots')).reflectee
              as Map<String, Directory>;
      sourceRoots[root.label] = sourceDirectory;

      await driver.buildAndInspect(root, target);

      final rawCandidate = File(
        p.join(
          evidenceDirectory.path,
          'artifacts',
          root.label,
          target.name,
          'raw',
          target.outputFileName,
        ),
      );
      expect(rawCandidate.readAsBytesSync(), installedDll.readAsBytesSync());
      expect(
        evidenceDirectory
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => p.basename(file.path)),
        isNot(contains('opentui.pdb')),
      );
      expect(
        runner.commands,
        contains(
          containsAllInOrder(<String>[
            'llvm-readobj',
            '--coff-exports',
            '/work/artifact/${target.outputFileName}',
          ]),
        ),
      );
      expect(
        runner.commands.any((command) => command.contains('llvm-nm')),
        isFalse,
      );
    },
  );
}

final class _RecordingRunner implements CommandRunner {
  final List<List<String>> commands = <List<String>>[];

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    commands.add(<String>[executable, ...arguments]);
    final stdout = switch (arguments) {
      _ when arguments.contains('--coff-exports') =>
        requiredOpenTuiNativeSymbolNames
            .map((symbol) => 'Export {\n  Name: $symbol\n}')
            .join('\n'),
      _ when arguments.contains('llvm-readobj') =>
        'Format: COFF-x86-64\nArch: x86_64\n',
      _ when arguments.contains('llvm-nm') =>
        requiredOpenTuiNativeSymbolNames
            .map((symbol) => '00000000 T $symbol')
            .join('\n'),
      _ when arguments.contains('llvm-strings') => 'OpenTUI\n',
      _ => '',
    };
    return CommandResult(exitCode: 0, stdout: stdout, stderr: '');
  }
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
