@TestOn('vm')
@Tags(['safe-process-spawning'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

final _forbiddenControlCharacters = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

void main() {
  test(
    'health check succeeds from a downstream package working directory',
    () async {
      final packageRoot = Directory.current.resolveSymbolicLinksSync();
      final consumer = await Directory.systemTemp.createTemp(
        'noir_health_check_consumer_',
      );
      addTearDown(() async {
        if (consumer.existsSync()) {
          await consumer.delete(recursive: true);
        }
      });

      await File('${consumer.path}/pubspec.yaml').writeAsString('''
name: noir_health_check_consumer
publish_to: none

environment:
  sdk: '>=3.10.0 <4.0.0'

dependencies:
  noir:
    path: ${jsonEncode(packageRoot)}
''');

      final pubGet = await Process.run(Platform.resolvedExecutable, [
        'pub',
        'get',
        '--offline',
      ], workingDirectory: consumer.path);
      expect(
        pubGet.exitCode,
        0,
        reason: 'stdout:\n${pubGet.stdout}\n\nstderr:\n${pubGet.stderr}',
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'noir:health_check',
      ], workingDirectory: consumer.path);

      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\n\nstderr:\n${result.stderr}',
      );
      expect(
        '${result.stdout}${result.stderr}',
        isNot(matches(_forbiddenControlCharacters)),
        reason: 'The shipped health check must not emit terminal controls.',
      );
      expect(result.stdout, isNot(contains('native_manifest.json is missing')));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
