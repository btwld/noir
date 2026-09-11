@Tags(['safe-process-spawning'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('assertion-disabled maxLines fails at render boundary', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      '--no-enable-asserts',
      'test/fixtures/text_max_lines_release_probe.dart',
    ], workingDirectory: Directory.current.path);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final labels = RegExp('PASS:[a-z0-9-]+')
        .allMatches(result.stdout as String)
        .map((match) => match.group(0)!)
        .toList();
    const expected = {
      'PASS:render-construct-zero',
      'PASS:render-construct-neg',
      'PASS:render-set-zero',
      'PASS:render-set-neg',
      'PASS:text-update-zero',
      'PASS:text-rich-update-neg',
      'PASS:richtext-update-zero',
      'PASS:text-create-0',
      'PASS:text-create--1',
      'PASS:text-rich-create-0',
      'PASS:text-rich-create--1',
      'PASS:richtext-create-0',
      'PASS:richtext-create--1',
    };
    expect(labels.toSet(), expected);
    expect(labels.length, expected.length);
  });
}
