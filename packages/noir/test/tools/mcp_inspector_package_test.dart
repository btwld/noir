@TestOn('vm')
@Tags(['safe-process-spawning'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// The inspector and its fixtures own their own gates because the root
/// analysis options exclude `tools/**` and each package resolves its own
/// dependencies.
void main() {
  final packageRoot = path.join(
    Directory.current.absolute.path,
    'tool',
    'mcp_inspector',
  );
  final fixtureRoot = path.join(
    Directory.current.absolute.path,
    'tool',
    'mcp_fixtures',
  );

  setUpAll(() async {
    expect(Directory(packageRoot).existsSync(), isTrue, reason: packageRoot);
    expect(Directory(fixtureRoot).existsSync(), isTrue, reason: fixtureRoot);
    // The fixtures resolve first: the inspector depends on that package.
    await _run(fixtureRoot, const <String>['pub', 'get']);
    await _run(packageRoot, const <String>['pub', 'get']);
  });

  test('the fixture package is formatted', () async {
    await _run(fixtureRoot, const <String>[
      'format',
      '--output=none',
      '--set-exit-if-changed',
      '.',
    ]);
  });

  test('the fixture package analyzes without findings', () async {
    await _run(fixtureRoot, const <String>['analyze', '--fatal-infos']);
  });

  test('the fixture package depends only on mcp_dart', () {
    // A `noir` dependency would pull in its native-assets build hook, and
    // `dart run` writes hook progress to stdout — the MCP protocol channel.
    final pubspec = File(
      path.join(fixtureRoot, 'pubspec.yaml'),
    ).readAsStringSync();
    final block = pubspec
        .split('\ndependencies:\n')
        .last
        .split('\ndev_dependencies:')
        .first;
    final names = RegExp(
      '^  ([a-z_0-9]+):',
      multiLine: true,
    ).allMatches(block).map((match) => match.group(1)!).toList();
    expect(names, <String>['mcp_dart']);
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
