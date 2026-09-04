@TestOn('vm')
@Tags(['safe-process-spawning'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:noir_mcp_inspector/noir_mcp_inspector.dart';
import 'package:test/test.dart';

const _fixture = 'fixtures/calculate_server.dart';

void main() {
  test(
    'a stdio session calls a tool, shows stderr, and ends its child',
    () async {
      final session = LiveMcpSession.stdio(
        command: Platform.resolvedExecutable,
        // `--verbosity=error` keeps `dart run` build-hook progress lines off the
        // child's stdout, which is the MCP protocol channel.
        args: const <String>['run', '--verbosity=error', _fixture],
      );
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
        await _childCount(),
        greaterThan(0),
        reason: 'child must be running',
      );

      await session.close();

      await _until(() async => await _childCount() == 0);
      expect(await _childCount(), 0, reason: 'close() must end the child');
    },
    skip: _skipReason,
  );
}

/// Why this test cannot run here, or null when it can.
final String? _skipReason = Platform.isWindows
    ? 'Child-process inventory uses pgrep, which Windows does not provide.'
    : null;

/// Counts running processes whose command line names the fixture.
Future<int> _childCount() async {
  final result = await Process.run('pgrep', <String>['-f', _fixture]);
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
