@Tags(['safe-process-spawning'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'entry point returns usage error for every implicit build spelling',
    () async {
      for (final args in <List<String>>[
        <String>[],
        <String>['--execute'],
        <String>['--plan', '--execute-native-build'],
        <String>['--unknown'],
      ]) {
        final result = await Process.run(Platform.resolvedExecutable, <String>[
          'run',
          'scripts/build_opentui_candidates.dart',
          ...args,
        ]);
        expect(result.exitCode, 64, reason: '$args\n${result.stderr}');
        expect('${result.stderr}', contains('Usage:'));
      }
    },
  );
}
