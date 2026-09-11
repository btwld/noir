@Tags(['safe-process-spawning'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'assertion-disabled overlay validation rejects invalid states',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        '--no-enable-asserts',
        'test/fixtures/overlay_portal_release_probe.dart',
      ], workingDirectory: Directory.current.path);

      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      final labels = RegExp('PASS:[a-z0-9-]+')
          .allMatches(result.stdout as String)
          .map((match) => match.group(0)!)
          .toSet();
      expect(labels, {
        'PASS:missing-host',
        'PASS:duplicate-portal-controller',
        'PASS:malformed-entry',
        'PASS:duplicate-menu-controller',
        'PASS:detached-menu-open',
        'PASS:negative-reserved-padding',
      });
    },
  );
}
