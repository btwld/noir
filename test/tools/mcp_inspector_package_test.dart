@TestOn('vm')
@Tags(['safe-process-spawning'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// The inspector owns its own gates because the root analysis options exclude
/// `tools/**` and the package resolves its own dependencies.
void main() {
  final packageRoot = path.join(
    Directory.current.absolute.path,
    'tools',
    'mcp_inspector',
  );

  setUpAll(() async {
    expect(Directory(packageRoot).existsSync(), isTrue, reason: packageRoot);
    await _run(packageRoot, const <String>['pub', 'get']);
  });

  test('the inspector package is formatted', () async {
    await _run(packageRoot, const <String>[
      'format',
      '--output=none',
      '--set-exit-if-changed',
      '.',
    ]);
  });

  test('the inspector package analyzes without findings', () async {
    await _run(packageRoot, const <String>['analyze', '--fatal-infos']);
  });

  test('the inspector package suite passes', () async {
    await _run(packageRoot, const <String>['test', '--concurrency=1']);
  });
}

Future<void> _run(String workingDirectory, List<String> arguments) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: workingDirectory,
  );
  expect(
    result.exitCode,
    0,
    reason:
        'dart ${arguments.join(' ')} failed in $workingDirectory\n'
        'stdout:\n${result.stdout}\n'
        'stderr:\n${result.stderr}',
  );
}
