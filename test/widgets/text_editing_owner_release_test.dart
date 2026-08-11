@Tags(['process-spawning'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('assertion-disabled selection ownership fails loudly', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      '--no-enable-asserts',
      'test/fixtures/p9_024_release_probe.dart',
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
    const expected = {'PASS:connection-invalid', 'PASS:owner-reentrant'};
    expect(labels.toSet(), expected);
    expect(labels.length, expected.length);
  });
}
