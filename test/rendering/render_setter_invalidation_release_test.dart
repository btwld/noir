@Tags(['safe-process-spawning'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('assertion-disabled rejected setters schedule no work', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      '--no-enable-asserts',
      'test/fixtures/render_setter_invalidation_release_probe.dart',
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
    final expectedLabels = <String>{
      'PASS:constraints',
      'PASS:padding',
      'PASS:select-rows',
      'PASS:textarea-height',
      'PASS:textarea-width',
      'PASS:obscuring-character',
    };
    expect(labels.toSet(), expectedLabels);
    expect(labels.length, expectedLabels.length);
  });
}
