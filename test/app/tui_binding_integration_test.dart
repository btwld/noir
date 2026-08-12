// ignore_for_file: cascade_invocations
import 'dart:async';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/terminal_session.dart';
import 'package:noir/src/app/tui_binding.dart' show runTuiAppForTesting;
import 'package:noir/src/core/input.dart' show InputManagerKernelAccess;
import 'package:noir/src/core/stdin_input_driver.dart';
import 'package:test/test.dart';

import '../helpers/tui_test_app.dart';

void main() {
  test('runTuiApp integration harness drives parser to dispatcher handler', () {
    final key = GlobalKey<_CounterAppState>();
    final app = createTuiTestApp(_CounterApp(key: key), width: 10, height: 3);
    late final InputSubscription sub;

    try {
      app.pumpFrame();
      final state = key.currentState!;
      sub = app.binding.inputManager.onKey((event) {
        state.recordKey(event.character ?? event.logicalKey.keyLabel);
      });
      expect(state.buildCount, 1);

      app.mockInput.typeText('a');
      app.pumpFrame();

      expect(state.receivedKeys, ['a']);
      expect(state.buildCount, 2);
    } finally {
      sub.cancel();
      app.dispose();
    }
  });

  test('resize propagates to RenderView constraints and captured frame', () {
    final constraints = <BoxConstraints>[];
    final app = createTuiTestApp(
      _LayoutProbe(log: constraints),
      width: 8,
      height: 2,
    );

    try {
      app.pumpFrame();
      app
        ..resize(20, 5)
        ..pumpFrame();

      expect(constraints.last.maxWidth, 20);
      expect(constraints.last.maxHeight, 5);
      expect(app.captureFrame().width, 20);
      expect(app.captureFrame().height, 5);
    } finally {
      app.dispose();
    }
  });

  test(
    'scheduler idles without invalidation and reschedules active ticker',
    () {
      final idleApp = createTuiTestApp(const Text('idle'));

      try {
        expect(idleApp.binding.debugHasScheduledFrame, isTrue);
        idleApp.pumpFrame();
        expect(idleApp.binding.debugHasScheduledFrame, isFalse);
      } finally {
        idleApp.dispose();
      }

      final tickerKey = GlobalKey<_TickerProbeState>();
      final tickingApp = createTuiTestApp(_TickerProbe(key: tickerKey));

      try {
        tickingApp.pumpFrame();

        expect(tickerKey.currentState!.ticks, 1);
        expect(tickingApp.binding.debugHasScheduledFrame, isTrue);
      } finally {
        tickingApp.dispose();
      }
    },
  );

  test(
    'headless integration harness paints without stdout terminal ownership',
    () {
      final app = createTuiTestApp(
        const Text('headless'),
        width: 12,
        height: 2,
      );

      try {
        expect(app.binding.isHeadless, isTrue);
        app.pumpFrame();

        expect(app.captureFrame().containsText('headless'), isTrue);
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'runTuiApp shutdown unmounts root once and releases harness renderer',
    () {
      final disposals = <String>[];
      final app = createTuiTestApp(
        _DisposeProbe(onDispose: () => disposals.add('dispose')),
      );

      app
        ..dispose()
        ..dispose();

      expect(disposals, ['dispose']);
      expect(() => app.renderer.nextBuffer, throwsA(isA<StateError>()));
    },
  );

  test('parser-roundtrip mouse and paste reach dispatcher subscribers', () {
    final app = createTuiTestApp(const Text('events'));
    final mouse = <MouseEvent>[];
    final paste = <PasteEvent>[];
    final mouseSub = app.binding.inputManager.onMouse(mouse.add);
    final pasteSub = app.binding.inputManager.onPaste(paste.add);

    try {
      app.mockMouse.click(2, 1);
      app.mockInput.paste('line 1\nline 2');

      expect(mouse.map((event) => event.type), [
        MouseEventType.down,
        MouseEventType.up,
      ]);
      expect(
        mouse.singleWhere((event) => event.type == MouseEventType.down).x,
        2,
      );
      expect(paste.single.text, 'line 1\nline 2');
    } finally {
      mouseSub.cancel();
      pasteSub.cancel();
      app.dispose();
    }
  });

  test('complete capability batch never reaches application input', () {
    const response =
        '\x1b[?1016;2\$y'
        '\x1b[?2027;2\$y'
        '\x1b[?2031;2\$y'
        '\x1b[?1004;1\$y'
        '\x1b[?2004;2\$y'
        '\x1b[?2026;2\$y'
        '\x1b[1;2R'
        '\x1b[1;3R'
        '\x1bP>|kitty(0.40.1)\x1b\\'
        '\x1b[?0u'
        '\x1b_Gi=1;OK\x1b\\'
        '\x1b[?62;4c';
    final app = createTuiTestApp(
      const Text('capabilities'),
      headless: false,
      terminalPlatform: _RecordingTerminalPlatform(),
      inputDriverFactory: (_) => _NoopInputDriver(),
    );
    final dispatcher = app.binding.inputManager.dispatcher;
    final leakedCapabilities = <Object>[];
    final keys = <KeyEvent>[];
    final mouse = <MouseEvent>[];
    final paste = <PasteEvent>[];
    final subscriptions = <InputSubscription>[
      dispatcher.onCapabilityResponse(
        leakedCapabilities.add,
        priority: InputPriority.widget - 1,
      ),
      app.binding.inputManager.onKey(keys.add),
      app.binding.inputManager.onMouse(mouse.add),
      app.binding.inputManager.onPaste(paste.add),
    ];

    try {
      StdinInputDriver(dispatcher).debugFeedBytes(response.codeUnits);

      expect(leakedCapabilities, isEmpty);
      expect(keys, isEmpty);
      expect(mouse, isEmpty);
      expect(paste, isEmpty);
    } finally {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      app.dispose();
    }
  });

  test('signal cleanup disposes binding once through TerminalSession', () {
    final platform = _FakeTerminalPlatform();
    final exits = <int>[];
    final disposals = <String>[];
    final app = createTuiTestApp(
      _DisposeProbe(onDispose: () => disposals.add('dispose')),
      headless: false,
      terminalPlatform: platform,
      inputDriverFactory: (_) => _NoopInputDriver(),
      exitProcess: exits.add,
    );

    platform
      ..emit(TerminalSignal.interrupt)
      ..emit(TerminalSignal.interrupt);
    app.dispose();

    expect(disposals, ['dispose']);
    expect(exits, [130]);
  });

  test('parser-roundtrip key dispatch preserves priority ordering', () {
    final app = createTuiTestApp(const Text('priority'));
    final order = <String>[];
    final subs = <InputSubscription>[
      app.binding.inputManager.onKey((_) => order.add('widget')),
      app.binding.inputManager.onKey(
        (_) => order.add('app'),
        priority: InputPriority.app,
      ),
      app.binding.inputManager.onKey(
        (_) => order.add('focus'),
        priority: InputPriority.focus,
      ),
    ];

    try {
      app.mockInput.typeText('z');

      expect(order, ['app', 'focus', 'widget']);
    } finally {
      for (final sub in subs) {
        sub.cancel();
      }
      app.dispose();
    }
  });

  test('binding constructor failure rolls back input frame scheduling', () {
    final factoryError = StateError('renderer factory failed');
    final inputManager = InputManager();
    var timerCreates = 0;

    runZoned(
      () {
        expect(
          () => runTuiAppForTesting(
            const Text('never mounted'),
            inputManager: inputManager,
            terminalPlatform: _RecordingTerminalPlatform(
              stdoutHasTerminal: false,
            ),
            rendererFactory: (_, _) => throw factoryError,
            inputDriverFactory: (_) => _ProbeInputDriver(),
          ),
          throwsA(same(factoryError)),
        );

        inputManager.dispatchKey(
          KeyEvent(
            logicalKey: LogicalKeyboardKey.keyA,
            keyCode: 97,
            character: 'a',
          ),
        );
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          timerCreates++;
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );

    expect(timerCreates, 0);
  });

  test(
    'mount failure remains primary while rollback releases app resources',
    () {
      final mountError = StateError('root build failed');
      final stateDisposeError = StateError('state dispose failed');
      final platform = _RecordingTerminalPlatform();
      final driver = _ProbeInputDriver();
      Renderer? renderer;
      Object? caughtError;
      StackTrace? caughtStack;
      late StackTrace originalMountStack;
      var stateDisposals = 0;
      addTearDown(() => renderer?.dispose());

      try {
        runTuiAppForTesting(
          _ThrowingBuildProbe(
            onBuild: () {
              originalMountStack = StackTrace.current;
              Error.throwWithStackTrace(mountError, originalMountStack);
            },
            onDispose: () {
              stateDisposals++;
              throw stateDisposeError;
            },
          ),
          width: 8,
          height: 2,
          terminalPlatform: platform,
          rendererFactory: (width, height) {
            renderer = Renderer.create(width, height, testing: true);
            return renderer!;
          },
          inputDriverFactory: (_) => driver,
        );
      } on Object catch (error, stackTrace) {
        caughtError = error;
        caughtStack = stackTrace;
      }

      expect(caughtError, same(mountError));
      expect(caughtStack.toString(), originalMountStack.toString());
      expect(stateDisposals, 1);
      expect(driver.starts, 1);
      expect(driver.stops, 1);
      expect(platform.stdoutWriteAttempts, 3);
      expect(platform.stdoutFlushes, 1);
      expect(() => renderer!.nextBuffer, throwsStateError);
      expect(WidgetInspectorService.instance.rootElement, isNull);
    },
  );

  test(
    'binding dispose preserves unmount error and attempts every later release',
    () {
      final stateDisposeError = StateError('state dispose failed');
      final driverStopError = StateError('driver stop failed');
      final platform = _RecordingTerminalPlatform();
      final driver = _ProbeInputDriver(onStop: () => throw driverStopError);
      Renderer? renderer;
      var stateDisposals = 0;
      addTearDown(() => renderer?.dispose());

      final binding = runTuiAppForTesting(
        _DisposeProbe(
          onDispose: () {
            stateDisposals++;
            throw stateDisposeError;
          },
        ),
        width: 8,
        height: 2,
        terminalPlatform: platform,
        rendererFactory: (width, height) {
          renderer = Renderer.create(width, height, testing: true);
          return renderer!;
        },
        inputDriverFactory: (_) => driver,
      );

      expect(binding.dispose, throwsA(same(stateDisposeError)));

      expect(stateDisposals, 1);
      expect(driver.stops, 1);
      expect(platform.stdoutWriteAttempts, 3);
      expect(platform.stdoutFlushes, 1);
      expect(platform.stdinLineModeSets, 0);
      expect(platform.stdinEchoModeSets, 0);
      expect(binding.buildOwner.pipelineOwner.debugNeedsLayout, isFalse);
      expect(binding.buildOwner.pipelineOwner.debugNeedsPaint, isFalse);
      expect(() => renderer!.nextBuffer, throwsStateError);
      expect(WidgetInspectorService.instance.rootElement, isNull);

      expect(binding.dispose, returnsNormally);
      expect(stateDisposals, 1);
      expect(driver.stops, 1);
      expect(platform.stdoutWriteAttempts, 3);
    },
  );

  test('binding dispose is reentrancy-safe and at-most-once after failure', () {
    final stateDisposeError = StateError('state dispose failed');
    final platform = _RecordingTerminalPlatform();
    final driver = _ProbeInputDriver();
    Renderer? renderer;
    var stateDisposals = 0;
    late TuiBinding binding;
    addTearDown(() => renderer?.dispose());

    binding = runTuiAppForTesting(
      _DisposeProbe(
        onDispose: () {
          stateDisposals++;
          binding.dispose();
          throw stateDisposeError;
        },
      ),
      width: 8,
      height: 2,
      terminalPlatform: platform,
      rendererFactory: (width, height) {
        renderer = Renderer.create(width, height, testing: true);
        return renderer!;
      },
      inputDriverFactory: (_) => driver,
    );

    expect(binding.dispose, throwsA(same(stateDisposeError)));
    expect(binding.dispose, returnsNormally);

    expect(stateDisposals, 1);
    expect(driver.stops, 1);
    expect(platform.stdoutWriteAttempts, 3);
    expect(platform.stdoutFlushes, 1);
    expect(platform.stdinLineModeSets, 0);
    expect(platform.stdinEchoModeSets, 0);
    expect(() => renderer!.nextBuffer, throwsStateError);
  });
}

class _CounterApp extends StatefulWidget {
  const _CounterApp({super.key});

  @override
  State<StatefulWidget> createState() => _CounterAppState();
}

class _CounterAppState extends State<_CounterApp> {
  int buildCount = 0;
  final List<String> receivedKeys = [];

  void recordKey(String key) {
    setState(() {
      receivedKeys.add(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return const Text('counter');
  }
}

class _LayoutProbe extends RenderObjectWidget {
  const _LayoutProbe({required this.log});

  final List<BoxConstraints> log;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutProbe(log);
}

class _RenderLayoutProbe extends RenderBox {
  _RenderLayoutProbe(this.log);

  final List<BoxConstraints> log;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    log.add(constraints);
    size = Size(constraints.maxWidth ?? 0, constraints.maxHeight ?? 0);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.drawText('probe', offset, Color.white);
  }
}

class _DisposeProbe extends StatefulWidget {
  const _DisposeProbe({required this.onDispose});

  final void Function() onDispose;

  @override
  State<_DisposeProbe> createState() => _DisposeProbeState();
}

class _DisposeProbeState extends State<_DisposeProbe> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('dispose');
}

class _ThrowingBuildProbe extends StatefulWidget {
  const _ThrowingBuildProbe({required this.onBuild, required this.onDispose});

  final void Function() onBuild;
  final void Function() onDispose;

  @override
  State<_ThrowingBuildProbe> createState() => _ThrowingBuildProbeState();
}

class _ThrowingBuildProbeState extends State<_ThrowingBuildProbe> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return const Text('unreachable');
  }
}

class _TickerProbe extends StatefulWidget {
  const _TickerProbe({super.key});

  @override
  State<_TickerProbe> createState() => _TickerProbeState();
}

class _TickerProbeState extends State<_TickerProbe>
    with SingleTickerProviderStateMixin<_TickerProbe> {
  late final Ticker _ticker;
  int ticks = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      ticks++;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('ticker');
}

class _NoopInputDriver implements TerminalInputDriver {
  @override
  bool start() => true;

  @override
  void stop() {}
}

class _ProbeInputDriver implements TerminalInputDriver {
  _ProbeInputDriver({this.onStop});

  final void Function()? onStop;
  int starts = 0;
  int stops = 0;

  @override
  bool start() {
    starts++;
    return true;
  }

  @override
  void stop() {
    stops++;
    onStop?.call();
  }
}

class _RecordingTerminalPlatform implements TerminalPlatform {
  _RecordingTerminalPlatform({this.stdoutHasTerminal = true});

  @override
  bool stdoutHasTerminal;

  @override
  bool get isWindows => false;

  @override
  int get terminalColumns => 80;

  @override
  int get terminalLines => 24;

  bool _stdinLineMode = false;
  bool _stdinEchoMode = false;
  int stdoutWriteAttempts = 0;
  int stdoutFlushes = 0;
  int stdinLineModeSets = 0;
  int stdinEchoModeSets = 0;

  bool get stdinLineMode => _stdinLineMode;

  set stdinLineMode(bool value) {
    stdinLineModeSets++;
    _stdinLineMode = value;
  }

  bool get stdinEchoMode => _stdinEchoMode;

  set stdinEchoMode(bool value) {
    stdinEchoModeSets++;
    _stdinEchoMode = value;
  }

  final Map<TerminalSignal, StreamController<void>> _signals = {
    for (final signal in TerminalSignal.values)
      signal: StreamController<void>.broadcast(sync: true),
  };

  @override
  void stdoutWrite(String data) {
    stdoutWriteAttempts++;
  }

  @override
  void stdoutFlush() {
    stdoutFlushes++;
  }

  @override
  Stream<void> watchSignal(TerminalSignal signal) => _signals[signal]!.stream;
}

class _FakeTerminalPlatform implements TerminalPlatform {
  final Map<TerminalSignal, StreamController<void>> _signals = {
    for (final signal in TerminalSignal.values)
      signal: StreamController<void>.broadcast(sync: true),
  };

  void emit(TerminalSignal signal) {
    _signals[signal]!.add(null);
  }

  @override
  bool get stdoutHasTerminal => false;

  @override
  bool get isWindows => false;

  @override
  int get terminalColumns => 80;

  @override
  int get terminalLines => 24;

  @override
  void stdoutWrite(String data) {}

  @override
  void stdoutFlush() {}

  @override
  Stream<void> watchSignal(TerminalSignal signal) => _signals[signal]!.stream;
}
