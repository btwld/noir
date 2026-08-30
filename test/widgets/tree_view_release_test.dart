@Tags(['safe-process-spawning'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('assertion-disabled TreeView rejects negative dimensions', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      '--no-enable-asserts',
      'test/fixtures/tree_view_validation_release_probe.dart',
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
    expect(labels, {'PASS:negative-height', 'PASS:negative-indentation'});
  });
}
