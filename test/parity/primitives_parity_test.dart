import 'dart:io' as io;

import 'package:test/test.dart';

import '../../bin/parity_compare.dart' as parity_compare;

void main() {
  group('Primitives Parity (Dart vs Go baseline)', () {
    final goCmd = io.Platform.environment['GO_SNAPSHOT_CMD'];

    test(
      'S1,S2,S3 parity',
      () async {
        final result = await io.Process.run('dart', [
          'run',
          'bin/parity_compare.dart',
          '--scenes',
          'S1,S2,S3',
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
        expect(out.contains('PASS: S1'), isTrue);
        expect(out.contains('PASS: S2'), isTrue);
        expect(out.contains('PASS: S3'), isTrue);
      },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: (goCmd == null || goCmd.isEmpty)
          ? 'GO_SNAPSHOT_CMD not set; skipping parity test.'
          : false,
    );

    test('parses snapshot JSON after build hook chatter', () {
      final snapshot = parity_compare.parseSnapshotJsonForTest(
        'Running build hooks...Running build hooks...\n'
        '{"version":"1","width":1,"height":1,"cells":[]}',
      );

      expect(snapshot['version'], '1');
      expect(snapshot['width'], 1);
      expect(snapshot['height'], 1);
    });
  });
}
