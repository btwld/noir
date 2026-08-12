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
    'normalizes Mach-O artifacts by discarding path-bearing local symbols',
    () async {
      final sandbox = Directory.systemTemp.createTempSync(
        'noir-normalization-policy-',
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
        (candidate) => candidate.name == 'x86_64-macos',
      );
      final builtFile =
          File(
              p.join(
                runDirectory.path,
                'build-roots',
                root.label,
                'output',
                'lib',
                target.name,
                target.outputFileName,
              ),
            )
            ..createSync(recursive: true)
            ..writeAsBytesSync(<int>[0x4d, 0x61, 0x63, 0x68, 0x4f]);
      expect(builtFile.existsSync(), isTrue);

      final runner = _RecordingRunner(target);
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
          'sha256:normalization-policy-test',
        );
      final sourceRoots =
          driverMirror.getField(privateSymbol('_sourceRoots')).reflectee
              as Map<String, Directory>;
      sourceRoots[root.label] = sourceDirectory;

      await driver.buildAndInspect(root, target);

      final stripCommand = runner.commands.singleWhere(
        (command) => command.contains('llvm-strip'),
      );
      expect(
        stripCommand,
        containsAllInOrder(<String>[
          'llvm-strip',
          '--discard-all',
          '/work/artifact/${target.outputFileName}',
        ]),
      );
      expect(stripCommand, isNot(contains('--strip-debug')));
    },
  );
}

final class _RecordingRunner implements CommandRunner {
  _RecordingRunner(this.target);

  final NativeBuildTarget target;
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
      _ when arguments.contains('llvm-readobj') =>
        'Format: Mach-O 64-bit x86-64\nArch: x86_64\n',
      _ when arguments.contains('llvm-nm') =>
        requiredOpenTuiNativeSymbolNames
            .map((symbol) => '00000000 T _$symbol')
            .join('\n'),
      _ when arguments.contains('llvm-strings') =>
        '/usr/lib/libSystem.B.dylib\nOpenTUI\n',
      _ when arguments.contains('llvm-objdump') =>
        'cmd LC_BUILD_VERSION\nplatform macos\nminos 15.0\nsdk 15.1\n',
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
