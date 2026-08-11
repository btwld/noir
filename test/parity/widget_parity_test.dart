import 'dart:io' as io;

import 'package:test/test.dart';

void main() {
  group('Widget Parity (Dart vs Go baseline)', () {
    final goCmd = io.Platform.environment['GO_SNAPSHOT_CMD'];

    test(
      'W1,W2,W3 parity',
      () async {
        final result = await io.Process.run('dart', [
          'run',
          'bin/parity_compare.dart',
          '--scenes',
          'W1,W2,W3',
          '--width',
          '20',
          '--height',
          '5',
        ], environment: io.Platform.environment);

        final out = result.stdout.toString();
        final err = result.stderr.toString();

        expect(
          result.exitCode,
          0,
          reason: 'Comparator failed.\nSTDOUT:\n$out\nSTDERR:\n$err',
        );
        expect(out, contains('PASS: W1'));
        expect(out, contains('PASS: W2'));
        expect(out, contains('PASS: W3'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: (goCmd == null || goCmd.isEmpty)
          ? 'GO_SNAPSHOT_CMD not set; skipping parity test.'
          : false,
    );
  });
}
