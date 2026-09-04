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
  final constrainedFixture = path.join(
    packageRoot,
    'fixtures',
    'constrained_server.dart',
  );
  final greetingFixture = path.join(
    packageRoot,
    'fixtures',
    'greeting_server.dart',
  );
  final legacyFixture = path.join(
    packageRoot,
    'fixtures',
    'legacy_elicit_server.dart',
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

  test('Ctrl+O swaps the schema in and out without losing focus', () async {
    final driver = await NoirDriver.launch(
      entryPoint,
      width: 100,
      height: 30,
      arguments: <String>['--', ..._fixtureCommand(calculateFixture)],
    );
    addTearDown(driver.quit);

    await driver.waitFor(
      const DriverLocator.byKey('primitive:calculate'),
      timeout: const Duration(seconds: 30),
    );
    // Put focus inside the form, which is the state that used to break: the
    // toggle unmounts the focused field, and `Shortcuts` are looked up from
    // the focused element.
    await driver.clickLocator(const DriverLocator.byKey('primitive:calculate'));

    await driver.sendKey('ctrl-o');
    await driver.waitForText('Schema', timeout: const Duration(seconds: 10));

    // Enter used to focus a field the schema view had already unmounted,
    // which threw. The app must still be answering after it.
    await driver.sendKey('enter');
    final afterEnter = await driver.capture();
    expect(afterEnter.contains('Schema'), isTrue);

    // Back to the form, which is what the README promises.
    await driver.sendKey('ctrl-o');
    await driver.waitForText('operation', timeout: const Duration(seconds: 10));

    // The form is bounded, so Run survives both documented floors. Without
    // that bound the per-field hint rows push it off the pane.
    for (final size in const <({int width, int height})>[
      (width: 80, height: 24),
      (width: 60, height: 18),
    ]) {
      await driver.resize(size.width, size.height);
      final frame = await driver.capture();
      expect(
        frame.contains('Run'),
        isTrue,
        reason:
            'Run lost at ${size.width}x${size.height}:\n'
            '${frame.lines.join('\n')}',
      );
    }
    await driver.resize(100, 30);

    // Ctrl+N still steps the tab strip, so no binding was lost on the way.
    await driver.sendKey('ctrl-n');
    final afterTab = await driver.waitForText(
      'file:///logs',
      timeout: const Duration(seconds: 10),
    );
    expect(afterTab.contains('file:///logs'), isTrue);
  }, skip: _skipReason);

  test('the schema view reaches the keywords the form cannot show', () async {
    final driver = await NoirDriver.launch(
      entryPoint,
      width: 100,
      height: 40,
      arguments: <String>['--', ..._fixtureCommand(constrainedFixture)],
    );
    addTearDown(driver.quit);

    await driver.waitFor(
      const DriverLocator.byKey('primitive:schedule'),
      timeout: const Duration(seconds: 30),
    );
    await driver.clickLocator(const DriverLocator.byKey('primitive:schedule'));

    // The form shows the value constraints it can express.
    final form = await driver.waitForText(
      'Retry budget',
      timeout: const Duration(seconds: 10),
    );
    expect(form.contains('1..10'), isTrue);

    await driver.sendKey('ctrl-o');
    await driver.waitForText('Schema', timeout: const Duration(seconds: 10));

    // `if` and `dependentRequired` generate no control, so the schema view is
    // the only place the reader can see them. FINDINGS entry 24 says so; this
    // proves they are reachable rather than clipped away.
    // The schema view autofocuses as it mounts, so it scrolls straight away.
    var found = false;
    for (var step = 0; step < 60 && !found; step++) {
      final frame = await driver.capture();
      found = frame.contains('"if"');
      if (!found) await driver.sendKey('down');
    }
    expect(found, isTrue, reason: 'the schema view never reached "if"');
  }, skip: _skipReason);

  test('the modal answers a 2026 input_required call', () async {
    final driver = await NoirDriver.launch(
      entryPoint,
      width: 100,
      height: 30,
      arguments: <String>[
        '--protocol',
        '2026',
        '--',
        ..._fixtureCommand(greetingFixture),
      ],
    );
    addTearDown(driver.quit);

    await _answerElicitation(
      driver,
      tool: 'personalized_greeting',
      name: 'Leo',
    );

    final frame = await driver.waitForText(
      'Hello, Leo!',
      timeout: const Duration(seconds: 30),
    );
    expect(frame.contains('Result ('), isTrue);
  });

  test('the same modal answers a 2025-11-25 elicitation/create', () async {
    final driver = await NoirDriver.launch(
      entryPoint,
      width: 100,
      height: 30,
      arguments: <String>[
        '--protocol',
        'legacy',
        '--',
        ..._fixtureCommand(legacyFixture),
      ],
    );
    addTearDown(driver.quit);

    await _answerElicitation(driver, tool: 'register_user', name: 'Leo');

    final frame = await driver.waitForText(
      'Registered Leo.',
      timeout: const Duration(seconds: 30),
    );
    expect(frame.contains('Result ('), isTrue);
  });
}

/// Runs [tool], then answers its server-initiated form with [name].
Future<void> _answerElicitation(
  NoirDriver driver, {
  required String tool,
  required String name,
}) async {
  await driver.waitFor(
    DriverLocator.byKey('primitive:$tool'),
    timeout: const Duration(seconds: 30),
  );
  // The tool takes no arguments, so Enter on the row sends the request.
  await driver.sendKey('enter');
  await driver.waitFor(
    const DriverLocator.byKey('elicit:field:name'),
    timeout: const Duration(seconds: 30),
  );
  await driver.typeText(name);
  await driver.clickLocator(const DriverLocator.byKey('elicit:accept'));
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
