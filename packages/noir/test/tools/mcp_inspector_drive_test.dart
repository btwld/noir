@TestOn('vm')
@Tags(['safe-process-spawning'])
@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../tool/driver/noir_driver.dart';

/// Drives the MCP inspector against its own fixture servers.
///
/// Drive mode starts `bin/mcp_inspector.dart` as an ordinary Dart process, so
/// the inspector also starts the fixture server as a real child. The test
/// checks the whole chain: the handshake, one tool call, the protocol log, two
/// resize floors, and that the fixture child is gone after the app quits.
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
  final entryPoint = path.join(packageRoot, 'bin', 'mcp_inspector.dart');
  const calculateFixture = 'bin/calculate_server.dart';
  const constrainedFixture = 'bin/constrained_server.dart';
  const greetingFixture = 'bin/greeting_server.dart';
  const legacyFixture = 'bin/legacy_elicit_server.dart';
  const slowFixture = 'bin/slow_server.dart';
  const manyToolsFixture = 'bin/many_tools_server.dart';

  setUpAll(() async {
    // The fixtures resolve first: the inspector depends on that package.
    for (final root in <String>[fixtureRoot, packageRoot]) {
      final resolution = await Process.run(
        Platform.resolvedExecutable,
        const <String>['pub', 'get'],
        workingDirectory: root,
      );
      expect(
        resolution.exitCode,
        0,
        reason:
            'pub get failed in $root\n'
            'stdout:\n${resolution.stdout}\nstderr:\n${resolution.stderr}',
      );
    }
    _compiledFixtures = _CompiledFixtures(fixtureRoot);
  });
  tearDownAll(() => _compiledFixtures.dispose());

  test(
    'the inspector calls a tool, logs the exchange, and ends its child',
    () async {
      final marker =
          'noir-mcp-drive-$pid-${DateTime.now().microsecondsSinceEpoch}';
      final driver = await NoirDriver.launch(
        entryPoint,
        width: 100,
        height: 30,
        arguments: <String>[
          '--',
          ...await _fixtureCommand(calculateFixture),
          marker,
        ],
      );
      var quit = false;
      addTearDown(() async {
        if (!quit) await driver.quit();
      });

      await driver.waitFor(
        const DriverLocator.byKey('primitive:calculate'),
        timeout: const Duration(seconds: 30),
      );
      expect(await _childCount(marker), greaterThan(0));

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
      expect(result, _paints('example_server 1.0.0'));

      // Ctrl+N steps the tab strip from anywhere; the driver cannot encode
      // Ctrl with a digit.
      for (var step = 0; step < 3; step++) {
        await driver.sendKey('ctrl-n');
      }
      final protocol = await driver.waitForText(
        '-> tools/call',
        timeout: const Duration(seconds: 10),
      );
      expect(protocol, _paints('<- result'));

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

      await driver.sendKey('ctrl-x');
      expect(
        await driver.waitForExit().timeout(const Duration(seconds: 10)),
        0,
      );
      quit = true;
      await _until(() async => await _childCount(marker) == 0);
      expect(
        await _childCount(marker),
        0,
        reason: 'the inspector must end the fixture child when it exits',
      );
    },
    skip: _skipReason,
  );

  test('activating a different tool focuses its new field', () async {
    final driver = await NoirDriver.launch(
      entryPoint,
      width: 100,
      height: 30,
      arguments: <String>[
        '--protocol',
        'legacy',
        '--',
        ...await _fixtureCommand('bin/selection_server.dart'),
      ],
    );
    addTearDown(driver.quit);
    await driver.waitFor(const DriverLocator.byKey('field:firstValue'));

    for (final name in ['second', 'first']) {
      await driver.clickLocator(DriverLocator.byKey('primitive:$name'));
      await _waitForFocusIn(driver, DriverLocator.byKey('field:${name}Value'));
      await driver.typeText('entered');
      await driver.sendKey('ctrl-r');
      await driver.waitForText('$name: entered');
    }

    // A completed mount-time focus request must not fire again when the
    // form returns from the schema view, which deliberately focuses Run.
    await driver.sendKey('ctrl-g');
    await driver.waitForText('Schema');
    await driver.sendKey('ctrl-g');
    expect(
      (await driver.find(
        const DriverLocator.byKey('run'),
      )).hasFocusedDescendant,
      isTrue,
    );
  });

  test('Ctrl+G swaps the schema in and out without losing focus', () async {
    final driver = await NoirDriver.launch(
      entryPoint,
      width: 100,
      height: 30,
      arguments: <String>['--', ...await _fixtureCommand(calculateFixture)],
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

    await driver.sendKey('ctrl-g');
    await driver.waitForText('Schema', timeout: const Duration(seconds: 10));

    // Enter used to focus a field the schema view had already unmounted,
    // which threw. The app must still be answering after it.
    await driver.sendKey('enter');
    final afterEnter = await driver.capture();
    expect(afterEnter, _paints('Schema'));

    // Back to the form, which is what the README promises.
    await driver.sendKey('ctrl-g');
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
        frame,
        _paints('Run'),
        reason: 'Run lost at ${size.width}x${size.height}',
      );
      expect(
        frame.lines.last,
        contains('Ctrl+X quit'),
        reason: 'the quit shortcut must remain readable at the size floor',
      );
    }
    await driver.resize(100, 30);

    // Ctrl+N still steps the tab strip, so no binding was lost on the way.
    await driver.sendKey('ctrl-n');
    final afterTab = await driver.waitForText(
      'file:///logs',
      timeout: const Duration(seconds: 10),
    );
    expect(afterTab, _paints('file:///logs'));
  });

  test('the schema view reaches the keywords the form cannot show', () async {
    final driver = await NoirDriver.launch(
      entryPoint,
      width: 100,
      height: 40,
      arguments: <String>['--', ...await _fixtureCommand(constrainedFixture)],
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
    expect(form, _paints('1..10'));

    await driver.sendKey('ctrl-g');
    await driver.waitForText('Schema', timeout: const Duration(seconds: 10));

    // `if` and `dependentRequired` generate no control. The per-tool schema
    // view must make them reachable without searching the Protocol tab.
    // The schema view autofocuses as it mounts, so it scrolls straight away.
    var found = false;
    for (var step = 0; step < 60 && !found; step++) {
      final frame = await driver.capture();
      found = frame.contains('"if"');
      if (!found) await driver.sendKey('down');
    }
    expect(found, isTrue, reason: 'the schema view never reached "if"');
  });

  test('Ctrl+G leaves every non-tool tab and its focus alone', () async {
    final driver = await NoirDriver.launch(
      entryPoint,
      width: 100,
      height: 30,
      arguments: <String>['--', ...await _fixtureCommand(calculateFixture)],
    );
    addTearDown(driver.quit);
    await driver.waitFor(const DriverLocator.byKey('primitive:calculate'));

    for (var tab = 1; tab < 5; tab++) {
      await driver.sendKey('ctrl-n');
      final before = await driver.find(const DriverLocator.focused());
      await driver.sendKey('ctrl-g');
      final after = await driver.find(const DriverLocator.focused());
      expect(after.type, before.type);
      expect(after.key, before.key);
    }
    await driver.sendKey('ctrl-p');
    expect(await driver.capture(), _paints('Protocol'));
  });

  test('Tab reveals every constrained field at each supported grid', () async {
    final driver = await NoirDriver.launch(
      entryPoint,
      width: 100,
      height: 30,
      arguments: <String>['--', ...await _fixtureCommand(constrainedFixture)],
    );
    addTearDown(driver.quit);
    await driver.waitFor(const DriverLocator.byKey('primitive:schedule'));

    for (final size in const [(100, 30), (80, 24), (60, 18)]) {
      await driver.resize(size.$1, size.$2);
      await driver.clickLocator(
        const DriverLocator.byKey('primitive:schedule'),
      );
      for (final name in [
        'attempts',
        'timeoutSeconds',
        'slug',
        'webhook',
        'intervalMinutes',
      ]) {
        final field = await driver.find(DriverLocator.byKey('field:$name'));
        expect(
          field.hitPoint,
          isNotNull,
          reason: '$name must be visible at $size',
        );
        await driver.sendKey('tab');
      }
      expect(
        (await driver.find(const DriverLocator.byKey('run'))).hitPoint,
        isNotNull,
      );
      await driver.sendKey('shift-tab');
      expect(
        (await driver.find(
          const DriverLocator.byKey('field:intervalMinutes'),
        )).hitPoint,
        isNotNull,
      );
    }
  });

  test('the modal answers a 2026 input_required call', () async {
    final driver = await NoirDriver.launch(
      entryPoint,
      width: 100,
      height: 30,
      arguments: <String>[
        '--protocol',
        '2026',
        '--',
        ...await _fixtureCommand(greetingFixture),
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
    expect(frame, _paints('Result ('));
  });

  test('Ctrl+R sends from a field and editing keys stay local', () async {
    final driver = await NoirDriver.launch(
      entryPoint,
      arguments: ['--', ...await _fixtureCommand(calculateFixture)],
    );
    addTearDown(driver.quit);
    await driver.waitFor(const DriverLocator.byKey('primitive:calculate'));
    await driver.clickLocator(const DriverLocator.byKey('primitive:calculate'));
    // The generated field takes focus as it mounts, a frame after the click
    // that created it. Typing before that loses the characters.
    await _waitForFocusIn(driver, const DriverLocator.byKey('field:a'));
    await driver.typeText('5');
    await driver.sendKey('tab');
    await driver.typeText('13');
    await driver.sendKey('home');
    await driver.sendKey('delete');
    await driver.sendKey('ctrl-r');
    await driver.waitForText('Result: 8');
  });

  test('the primitives list fills the rows each grid offers', () async {
    final driver = await NoirDriver.launch(
      entryPoint,
      width: 100,
      height: 30,
      arguments: ['--', ...await _fixtureCommand(manyToolsFixture)],
    );
    addTearDown(driver.quit);
    await driver.waitFor(const DriverLocator.byKey('primitive:tool01'));

    final tall = await _visibleRowCount(driver);
    expect(tall, greaterThan(12), reason: 'a tall pane beats the old budget');

    await driver.resize(60, 18);
    await driver.waitStable();
    final short = await _visibleRowCount(driver);
    expect(short, lessThan(tall));
    expect(short, greaterThan(0));

    // The selected row must survive both directions of the resize. The detail
    // pane title is the selection, so it proves more than the row's presence.
    await driver.clickLocator(const DriverLocator.byKey('primitive:tool03'));
    await driver.waitForText('Echo a note from tool03');
    await driver.resize(100, 30);
    await driver.waitStable();
    expect(await _visibleRowCount(driver), tall);
    await driver.waitFor(const DriverLocator.byKey('primitive:tool03'));
    await driver.waitForText('Echo a note from tool03');
  });

  test('shortcuts keep working while a request is in flight', () async {
    final driver = await NoirDriver.launch(
      entryPoint,
      arguments: ['--', ...await _fixtureCommand(slowFixture)],
    );
    addTearDown(driver.quit);
    await driver.waitFor(const DriverLocator.byKey('primitive:slow'));
    await driver.clickLocator(const DriverLocator.byKey('primitive:slow'));
    await _waitForFocusIn(driver, const DriverLocator.byKey('field:note'));
    await driver.typeText('waiting');

    // Run must own focus when it is disabled: that is the case that used to
    // leave the tree with no primary focus and silence every binding.
    await driver.sendKey('tab');
    expect(
      (await driver.find(
        const DriverLocator.byKey('run'),
      )).hasFocusedDescendant,
      isTrue,
    );
    await driver.sendKey('enter');

    expect(await driver.findAll(const DriverLocator.focused()), isNotEmpty);
    await driver.sendKey('ctrl-n');
    await driver.waitForText('No resources');
    await driver.sendKey('ctrl-p');

    await driver.waitForText(
      'slow: waiting',
      timeout: const Duration(seconds: 30),
    );
  });

  test(
    'a long modal scrolls every field into view and preserves actions',
    () async {
      final driver = await NoirDriver.launch(
        entryPoint,
        width: 60,
        height: 18,
        arguments: [
          '--protocol',
          'legacy',
          '--',
          ...await _fixtureCommand('bin/long_form_server.dart'),
        ],
      );
      addTearDown(driver.quit);
      await driver.waitFor(const DriverLocator.byKey('primitive:long_form'));
      await driver.sendKey('enter');
      await driver.waitFor(const DriverLocator.byKey('elicit:field:f0'));
      await driver.sendKey('ctrl-g');
      for (var index = 0; index < 8; index++) {
        final field = await driver.find(
          DriverLocator.byKey('elicit:field:f$index'),
        );
        expect(
          field.hitPoint,
          isNotNull,
          reason: 'modal field f$index must be visible',
        );
        await driver.typeText('v$index');
        await driver.sendKey('tab');
      }
      for (final key in ['elicit:accept', 'elicit:decline', 'elicit:cancel']) {
        expect(
          (await driver.find(DriverLocator.byKey(key))).hitPoint,
          isNotNull,
        );
      }
      await driver.sendKey('enter');
      await driver.waitForText('Accepted');
      // The narrow result viewport clips long lines horizontally. Widen it
      // to assert every submitted value without weakening the modal checks.
      await driver.resize(80, 24);
      await driver.waitForText('Accepted v0,v1,v2,v3,v4,v5,v6,v7');
    },
  );

  test('the same modal answers a 2025-11-25 elicitation/create', () async {
    final driver = await NoirDriver.launch(
      entryPoint,
      width: 100,
      height: 30,
      arguments: <String>[
        '--protocol',
        'legacy',
        '--',
        ...await _fixtureCommand(legacyFixture),
      ],
    );
    addTearDown(driver.quit);

    await _answerElicitation(driver, tool: 'register_user', name: 'Leo');

    final frame = await driver.waitForText(
      'Registered Leo.',
      timeout: const Duration(seconds: 30),
    );
    expect(frame, _paints('Result ('));
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

/// Counts the primitives rows the list currently builds.
///
/// `ListView` inflates only its visible window, so this is the number of rows
/// the pane shows at the current grid.
Future<int> _visibleRowCount(NoirDriver driver) async {
  final root = (await driver.tree()).root;
  if (root == null) return 0;
  var count = 0;
  void visit(DriverNode node) {
    if (node.key?.startsWith('primitive:') ?? false) count++;
    node.children.forEach(visit);
  }

  visit(root);
  return count;
}

/// The command the inspector runs for [fixture], compiled on first use.
///
/// [fixture] is relative to `tools/mcp_fixtures`, which depends only on
/// `package:mcp_dart` and so has no native-assets build hook. That matters
/// twice. `dart run` on a hook-bearing package writes hook progress to
/// **stdout** — the MCP protocol channel — and `--verbosity=error` suppresses
/// it only from Dart 3.11 on. The same SDKs also refuse `dart compile exe` for
/// a hook-bearing package. A hook-free fixture compiles everywhere, and its
/// stdout carries only what the server writes.
Future<List<String>> _fixtureCommand(String fixture) async => <String>[
  await _compiledFixtures.executableFor(fixture),
];

late final _CompiledFixtures _compiledFixtures;

/// Compiles fixture servers into one temporary directory for this process.
class _CompiledFixtures {
  _CompiledFixtures(this.workingDirectory);

  /// Package root whose dependencies the fixtures resolve against.
  final String workingDirectory;

  final Map<String, Future<String>> _executables = <String, Future<String>>{};
  Directory? _output;

  /// The executable for [fixture], compiling it on the first request.
  Future<String> executableFor(String fixture) =>
      _executables.putIfAbsent(fixture, () => _compile(fixture));

  Future<String> _compile(String fixture) async {
    final output = _output ??= Directory.systemTemp.createTempSync(
      'noir-mcp-fixtures-',
    );
    final base = path.basenameWithoutExtension(fixture);
    final target = path.join(
      output.path,
      Platform.isWindows ? '$base.exe' : base,
    );
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'compile',
      'exe',
      fixture,
      '-o',
      target,
    ], workingDirectory: workingDirectory);
    if (result.exitCode != 0) {
      throw StateError(
        'dart compile exe $fixture failed\n'
        'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
    }
    return target;
  }

  /// Removes every executable this instance compiled.
  void dispose() {
    final output = _output;
    _output = null;
    _executables.clear();
    if (output != null && output.existsSync()) {
      output.deleteSync(recursive: true);
    }
  }
}

/// Polls until [locator] resolves to one node that owns focus or contains it.
///
/// The inspector focuses a generated field as the field mounts, a frame after
/// the row activation that created it. A test that types straight after a
/// click therefore races that focus, and loses its first characters whenever
/// the machine is slower than the developer's.
Future<void> _waitForFocusIn(
  NoirDriver driver,
  DriverLocator locator, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  DriverNode? last;
  while (DateTime.now().isBefore(deadline)) {
    final matches = (await driver.tree()).findAll(locator);
    if (matches.length == 1) {
      last = matches.single;
      if (last.focused || last.hasFocusedDescendant) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Timed out waiting for focus in $locator. Last: $last');
}

/// Counts only the app and fixture processes carrying this test's marker.
/// Short local alias; a failed drive assertion should print the frame.
Matcher _paints(String text) => DriverFrameMatchers.containsText(text);

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
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
