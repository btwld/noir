import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'help describes tracked changes, split sections, and untracked files',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'bin/patch_manager.dart',
        '--help',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final stdout = result.stdout.toString();
      expect(stdout, contains('tracked unstaged changes'));
      expect(stdout, contains('split sections'));
      expect(stdout, contains('untracked files'));
    },
  );
}
