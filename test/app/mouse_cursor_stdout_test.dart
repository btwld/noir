@Tags(['safe-process-spawning'])
library;

import 'dart:io';
import 'package:test/test.dart';

void main() {
  test(
    'iTerm uses legacy pointer names and resets without a shape stack',
    () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'test/fixtures/mouse_cursor_stdout_probe.dart'],
        workingDirectory: Directory.current.path,
        environment: {'TERM_PROGRAM': 'iTerm.app'},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final output = result.stdout as String;
      final commands = RegExp(
        r'\x1b\]22;([^\x1b]*)\x1b\\',
      ).allMatches(output).map((match) => match[1]).toList();
      expect(commands, ['arrow', 'hand2', '', 'arrow', 'xterm', '']);
      expect(output, contains('PASS:mouse-pointer-startup-and-cleanup'));
    },
  );

  test(
    'blocking stdout permits immediate mouse setup, updates and cleanup',
    () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'test/fixtures/mouse_cursor_stdout_probe.dart'],
        workingDirectory: Directory.current.path,
        environment: {'TERM_PROGRAM': 'kitty'},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('PASS:mouse-pointer-startup-and-cleanup'));
      expect(result.stdout, contains('\x1b]22;pointer\x1b\\'));
      expect(result.stdout, contains('\x1b]22;text\x1b\\'));
      expect(
        RegExp(
          RegExp.escape('\x1b]22;<\x1b\\'),
        ).allMatches(result.stdout as String),
        hasLength(2),
      );
    },
  );
}
