@TestOn('vm')
@Tags(['safe-process-spawning'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'helpers/tool_json_output.dart';

void main() {
  test('JSON decoding retains output after Dart build-hook progress', () {
    expect(
      decodeToolJsonObjects(
        'Running build hooks...Running build hooks...{"width": 16}\n'
        '{"root": null}\n',
      ),
      <Map<String, Object?>>[
        <String, Object?>{'width': 16},
        <String, Object?>{'root': null},
      ],
    );
  });

  test(
    'noir_drive accepts locator find, wait, and click grammar',
    () async {
      final process = await Process.start(Platform.resolvedExecutable, <String>[
        'run',
        '--verbosity=error',
        'scripts/noir_drive.dart',
        'test/fixtures/noir_drive_cli_probe.dart',
        '--size',
        '16x3',
        '--json',
      ]);
      addTearDown(() => process.kill(ProcessSignal.sigkill));

      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      process.stdin.write('''
tree 2
find key increment
find type Button
find text ADD
find focused
wait key increment
wait type Button
wait text ADD
wait focused
click key increment
capture --plain
click 0 1
capture --plain
quit
''');
      await process.stdin.close();

      final code = await process.exitCode.timeout(const Duration(minutes: 2));
      final stdoutText = await stdoutFuture;
      final stderrText = await stderrFuture;
      expect(code, 0, reason: 'stdout:\n$stdoutText\n\nstderr:\n$stderrText');

      final messages = decodeToolJsonObjects(stdoutText);
      expect(messages, hasLength(11), reason: stdoutText);
      expect(messages.first['root'], isA<Map<String, Object?>>());
      expect(messages[1]['key'], 'increment');
      expect(messages[2]['type'], 'Button');
      expect(messages[3]['text'], 'ADD');
      expect(messages[4]['focused'], isTrue);
      expect(messages[9]['lines']! as List<Object?>, contains('COUNT 1'));
      expect(messages[10]['lines']! as List<Object?>, contains('COUNT 2'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
