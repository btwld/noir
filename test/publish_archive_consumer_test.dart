@TestOn('vm')
@Tags(['safe-process-spawning'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'helpers/published_package.dart';

void main() {
  test(
    'exact Pub archive renders native cells and relocates a CLI bundle',
    () async {
      final sourceRoot = Directory.current.absolute;
      final temporary = Directory.systemTemp.createTempSync(
        'noir_pub_archive.',
      );
      addTearDown(() => temporary.deleteSync(recursive: true));

      final extracted = await extractPublishedPackage(sourceRoot, temporary);
      final consumer = Directory(path.join(temporary.path, 'consumer'))
        ..createSync();
      File(path.join(consumer.path, 'pubspec.yaml')).writeAsStringSync('''
name: noir_archive_consumer
publish_to: none
environment:
  sdk: '>=3.10.0 <4.0.0'
dependencies:
  noir:
    path: ../package
''');
      final entrypoint = File(path.join(consumer.path, 'bin', 'render.dart'));
      entrypoint.parent.createSync();
      File(
        path.join(
          sourceRoot.path,
          'test',
          'fixtures',
          'source_package_consumer',
          'bin',
          'render.dart',
        ),
      ).copySync(entrypoint.path);
      await _run(consumer, ['pub', 'get', '--offline']);
      final configurationFile = File(
        path.join(consumer.path, '.dart_tool', 'package_config.json'),
      );
      final configuration =
          jsonDecode(configurationFile.readAsStringSync())
              as Map<String, Object?>;
      final packages = (configuration['packages']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final noir = packages.singleWhere((entry) => entry['name'] == 'noir');
      expect(
        Directory.fromUri(
          configurationFile.uri.resolve(noir['rootUri']! as String),
        ).resolveSymbolicLinksSync(),
        extracted.resolveSymbolicLinksSync(),
      );
      expect(
        packages.map((entry) => entry['name']),
        isNot(
          anyElement(isIn(['noir_signals', 'signals_core', 'preact_signals'])),
        ),
      );
      await _run(consumer, ['analyze', '--fatal-infos']);
      await _run(consumer, ['run', 'bin/render.dart']);
      await _run(consumer, ['run', 'noir:health_check']);
      final output = path.join(temporary.path, 'build');
      await _run(consumer, [
        'build',
        'cli',
        '-t',
        'bin/render.dart',
        '--output',
        output,
      ]);
      final relocated = Directory(
        path.join(output, 'bundle'),
      ).renameSync(path.join(temporary.path, 'relocated'));
      // A successful relocation cannot depend on the extracted package or
      // on native assets left in the consumer's build cache.
      await consumer.delete(recursive: true);
      await extracted.delete(recursive: true);
      final executable = path.join(
        relocated.path,
        'bin',
        Platform.isWindows ? 'render.exe' : 'render',
      );
      final result = await Process.run(
        executable,
        const <String>[],
        workingDirectory: relocated.path,
        environment: const {'OPENTUI_LIBRARY_PATH': ''},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<ProcessResult> _run(Directory directory, List<String> arguments) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: directory.path,
    environment: const {'OPENTUI_LIBRARY_PATH': ''},
  );
  expect(
    result.exitCode,
    0,
    reason: 'dart ${arguments.join(' ')}\n${result.stdout}\n${result.stderr}',
  );
  return result;
}
