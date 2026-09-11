@TestOn('vm')
@Tags(['safe-process-spawning'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:noir_mcp_inspector/noir_mcp_inspector.dart';
import 'package:test/test.dart';

import 'compiled_fixture.dart';

const _fixturePackage = '../mcp_fixtures';
const _fixture = 'bin/calculate_server.dart';

void main() {
  final fixtures = CompiledFixtures(workingDirectory: _fixturePackage);
  late String executable;

  setUpAll(() async {
    executable = await fixtures.executableFor(_fixture);
  });
  tearDownAll(fixtures.dispose);

  test(
    'a stdio session calls a tool, shows stderr, and ends its child',
    () async {
      // Another inspector must not contaminate this test's lifetime check.
      final neighbor = LiveMcpSession.stdio(command: executable);
      addTearDown(neighbor.close);
      await neighbor.connect();
      final marker =
          'noir-mcp-fixture-$pid-${DateTime.now().microsecondsSinceEpoch}';
      final session = LiveMcpSession.stdio(
        command: executable,
        // The fixture ignores this extra argument. It identifies only this
        // session in the process table, even beside another copy of the app.
        args: <String>[marker],
      );
      addTearDown(session.close);
      final consoleLines = <String>[];
      final recording = session.console.listen(consoleLines.add);
      addTearDown(recording.cancel);

      await session.connect();

      expect(session.serverInfo?.name, 'example_server');
      final outcome = await session.callTool('calculate', <String, Object?>{
        'operation': 'add',
        'a': 5,
        'b': 3,
      });
      expect(outcome.text, 'Result: 8');

      await _until(() => consoleLines.any((line) => line.contains('ready')));
      expect(consoleLines, contains('calculate_server ready'));
      expect(
        await _childCount(marker),
        greaterThan(0),
        reason: 'child must be running',
      );

      await session.close();

      await _until(() async => await _childCount(marker) == 0);
      expect(
        await _childCount(marker),
        0,
        reason: 'close() must end the child',
      );
      final neighborOutcome = await neighbor.callTool('calculate', {
        'operation': 'add',
        'a': 2,
        'b': 3,
      });
      expect(neighborOutcome.text, 'Result: 5');
    },
    skip: _skipReason,
  );
}

/// Why this test cannot run here, or null when it can.
final String? _skipReason = Platform.isWindows
    ? 'Child-process inventory uses pgrep, which Windows does not provide.'
    : null;

/// Counts only the fixture processes carrying this test's unique marker.
Future<int> _childCount(String marker) async {
  final result = await Process.run('pgrep', <String>['-f', marker]);
  if (result.exitCode == 1) return 0;
  expect(result.exitCode, 0, reason: 'pgrep failed: ${result.stderr}');
  return const LineSplitter()
      .convert(result.stdout.toString())
      .where((line) => line.trim().isNotEmpty)
      .length;
}

/// Polls [condition] until it holds or the deadline passes.
Future<void> _until(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
