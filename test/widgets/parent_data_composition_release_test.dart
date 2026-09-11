@Tags(['safe-process-spawning'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'parent metadata rejects invalid composition with assertions disabled',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        '--no-enable-asserts',
        'test/fixtures/parent_data_composition_release_probe.dart',
      ], workingDirectory: Directory.current.path);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        RegExp(
          'PASS:[a-z-]+',
        ).allMatches(result.stdout as String).map((match) => match.group(0)!),
        [
          'PASS:zero-flex',
          'PASS:negative-flex',
          'PASS:misplaced-flex',
          'PASS:duplicate-flex',
          'PASS:misplaced-position',
          'PASS:duplicate-position',
          'PASS:negative-position-width',
          'PASS:conflicting-position-size',
        ],
      );
    },
  );
}
