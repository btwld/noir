@TestOn('vm')
@Tags(['safe-process-spawning'])
@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../scripts/driver/noir_driver.dart';

/// Drives the MCP inspector against its own fixture servers.
///
/// Drive mode starts `bin/mcp_inspector.dart` as an ordinary Dart process, so
/// the inspector also starts the fixture server as a real child. The test
/// checks the whole chain: the handshake, one tool call, the protocol log, two
/// resize floors, and that the fixture child is gone after the app quits.
void main() {
  final packageRoot = path.join(
    Directory.current.absolute.path,
    'tools',
    'mcp_inspector',
  );
  final entryPoint = path.join(packageRoot, 'bin', 'mcp_inspector.dart');
  final calculateFixture = path.join(
    packageRoot,
    'fixtures',
    'calculate_server.dart',
  );

  setUpAll(() async {
    final resolution = await Process.run(
      Platform.resolvedExecutable,
      const <String>['pub', 'get'],
      workingDirectory: packageRoot,
    );
    expect(
      resolution.exitCode,
      0,
      reason: 'stdout:\n${resolution.stdout}\nstderr:\n${resolution.stderr}',
    );
  });

  test(
    'the inspector calls a tool, logs the exchange, and ends its child',
    () async {
      final driver = await NoirDriver.launch(
        entryPoint,
        width: 100,
        height: 30,
        arguments: <String>['--', ..._fixtureCommand(calculateFixture)],
      );
      var quit = false;
      addTearDown(() async {
        if (!quit) await driver.quit();
      });

      await driver.waitFor(
        const DriverLocator.byKey('primitive:calculate'),
        timeout: const Duration(seconds: 30),
      );
      expect(await _childCount(calculateFixture), greaterThan(0));

      await driver.clickLocator(
        const DriverLocator.byKey('primitive:calculate'),
      );
      await driver.typeText('5');
      await driver.sendKey('tab');
      await driver.typeText('3');
      await driver.clickLocator(const DriverLocator.byKey('run'));
      final result = await driver.waitForText(
        'Result: 8',
        timeout: const Duration(seconds: 30),
      );
      expect(result.contains('example_server 1.0.0'), isTrue);

      // Ctrl+N steps the tab strip from anywhere; the driver cannot encode
      // Ctrl with a digit.
      for (var step = 0; step < 3; step++) {
        await driver.sendKey('ctrl-n');
      }
      final protocol = await driver.waitForText(
        '-> tools/call',
        timeout: const Duration(seconds: 10),
      );
      expect(
        protocol.lines.any((line) => line.contains('<- result')),
        isTrue,
        reason: protocol.lines.join('\n'),
      );

      for (final size in const <({int width, int height})>[
        (width: 80, height: 24),
        (width: 60, height: 18),
      ]) {
        await driver.resize(size.width, size.height);
        final frame = await driver.capture();
        expect(
          frame.lines.first,
          contains('example_server'),
          reason:
              'header lost at ${size.width}x${size.height}:\n'
              '${frame.lines.join('\n')}',
        );
      }

      quit = true;
      expect(await driver.quit(), 0);
      await _until(() async => await _childCount(calculateFixture) == 0);
      expect(
        await _childCount(calculateFixture),
        0,
        reason: 'the inspector must end the fixture child when it exits',
      );
    },
    skip: _skipReason,
  );
}

/// Why this test cannot run here, or null when it can.
final String? _skipReason = Platform.isWindows
    ? 'Child-process inventory uses pgrep, which Windows does not provide.'
    : null;

/// The command the inspector runs for [fixture].
///
/// `--verbosity=error` keeps `dart run` build-hook progress lines off the
/// child's stdout, which is the MCP protocol channel.
List<String> _fixtureCommand(String fixture) => <String>[
  Platform.resolvedExecutable,
  'run',
  '--verbosity=error',
  fixture,
];

/// Counts running processes whose command line names [fixture].
Future<int> _childCount(String fixture) async {
  final result = await Process.run('pgrep', <String>['-f', fixture]);
  if (result.exitCode == 1) return 0;
  expect(result.exitCode, 0, reason: 'pgrep failed: ${result.stderr}');
  return const LineSplitter()
      .convert(result.stdout.toString())
      .where((line) => line.trim().isNotEmpty)
      .length;
}

/// Polls [condition] until it holds or the deadline passes.
Future<void> _until(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
