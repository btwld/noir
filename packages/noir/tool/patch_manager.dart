import 'dart:io' as io;

import 'package:noir/noir.dart';

import 'patch_manager/patch_manager.dart';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    io.stdout.writeln('Interactive Patch Manager');
    io.stdout.writeln();
    io.stdout.writeln('Usage: dart run tool/patch_manager.dart [worktree]');
    io.stdout.writeln();
    io.stdout.writeln(
      'Reviews tracked unstaged changes, split sections, and untracked files.',
    );
    return;
  }

  final worktreePath = args.isEmpty ? io.Directory.current.path : args.single;
  runTuiApp(
      PatchManagerApp(
        repository: GitPatchRepository(worktreePath: worktreePath),
      ),
    )
    ..enableMouse()
    ..enableKittyKeyboard();
}
