@Tags(['safe-process-spawning'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('assertion-disabled release boundaries reject invalid values', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      '--no-enable-asserts',
      'test/fixtures/release_runtime_validation_probe.dart',
    ], workingDirectory: Directory.current.path);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final labels = RegExp('PASS:[a-z-]+')
        .allMatches(result.stdout as String)
        .map((match) => match.group(0)!)
        .toSet();
    expect(labels, {
      'PASS:ffi-color-range',
      'PASS:direct-color-finite',
      'PASS:animation-bounds',
      'PASS:animation-value',
      'PASS:animation-set-value',
      'PASS:animation-duration',
      'PASS:animation-reverse-duration',
      'PASS:animation-duration-setter',
      'PASS:animation-reverse-duration-setter',
      'PASS:box-options-border-chars',
      'PASS:border-border-chars',
      'PASS:container-color-decoration',
    });
  });
}
