import 'dart:io' as io;

import 'package:noir/noir.dart';
import 'package:noir/src/tools/patch_manager/patch_manager.dart';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    io.stdout.writeln('Interactive Patch Manager');
    io.stdout.writeln();
    io.stdout.writeln('Usage: dart run bin/patch_manager.dart [worktree]');
    io.stdout.writeln();
    io.stdout.writeln(
      'Reviews tracked unstaged changes, split sections, and untracked files.',
    );
    return;
  }

  final worktreePath = args.isEmpty ? io.Directory.current.path : args.single;
  late final TuiApp app;

  void quit() {
    app.dispose();
    io.exit(0);
  }

  app =
      runTuiApp(
          PatchManagerApp(
            repository: GitPatchRepository(worktreePath: worktreePath),
            onQuit: quit,
          ),
        )
        ..enableMouse(enableMovement: true)
        ..enableKittyKeyboard();
}
