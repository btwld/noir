@Tags(['safe-process-spawning'])
library;

import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  test('TextHighlight assert rejects reversed and negative ranges', () {
    expect(
      () => TextHighlight(start: -1, end: 2),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => TextHighlight(start: 3, end: 1),
      throwsA(isA<AssertionError>()),
    );
  });

  test(
    'assertion-disabled RenderParagraph rejects invalid highlights',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        '--no-enable-asserts',
        'test/fixtures/text_highlight_release_probe.dart',
      ], workingDirectory: Directory.current.path);

      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      final labels = RegExp('PASS:[a-z-]+')
          .allMatches(result.stdout as String)
          .map((match) => match.group(0)!)
          .toList();
      const expected = <String>{
        'PASS:construct-negative',
        'PASS:construct-reversed',
        'PASS:setter-negative',
        'PASS:setter-reversed',
        'PASS:valid-selection',
      };
      expect(labels.toSet(), expected);
      expect(labels.length, expected.length);
    },
  );
}
