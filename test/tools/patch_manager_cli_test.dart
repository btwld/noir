import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'help describes tracked changes, split sections, and untracked files',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'scripts/patch_manager.dart',
        '--help',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final stdout = result.stdout.toString();
      expect(stdout, contains('tracked unstaged changes'));
      expect(stdout, contains('split sections'));
      expect(stdout, contains('untracked files'));
    },
  );

  test('entrypoint quits through the tree', () {
    final source = File('scripts/patch_manager.dart').readAsStringSync();
    expect(source, isNot(contains('onQuit')));
    expect(source, isNot(contains('io.exit(')));
    expect(source, contains('runTuiApp('));
    expect(source, contains('enableMouse(enableMovement: true)'));
  });
}
