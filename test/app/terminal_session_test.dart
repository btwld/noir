// ignore_for_file: cascade_invocations
import 'dart:async';

import 'package:noir/src/app/terminal_session.dart';
import 'package:noir/src/core/color.dart';
import 'package:noir/src/core/input.dart';
import 'package:noir/src/core/renderer.dart';
import 'package:test/test.dart';

KeyEvent _ctrlC() => KeyEvent(
  logicalKey: LogicalKeyboardKey.keyC,
  keyCode: 3,
  modifiers: KeyModifiers.ctrl,
);

void main() {
  test(
    'headless session does not create renderer, start stdin, install signals, '
    'or write terminal restore',
    () {
      final platform = _FakeTerminalPlatform(stdoutHasTerminal: true);
      var rendererCreates = 0;
      var scheduledFrames = 0;
      final driver = _FakeTerminalInputDriver();

      final session = TerminalSession(
        width: 12,
        height: 4,
        headless: true,
        inputDispatcher: _dispatcher(),
        scheduleFrame: () => scheduledFrames++,
        platform: platform,
        rendererFactory: (width, height) {
          rendererCreates++;
          return Renderer.create(width, height, testing: true);
        },
        inputDriverFactory: (_) => driver,
      );

      expect(session.renderer, isNull);
      expect(session.width, 12);
      expect(session.height, 4);
      expect(session.isHeadless, isTrue);
      expect(rendererCreates, 0);
      expect(driver.starts, 0);
      expect(platform.watchedSignals, isEmpty);

      session.close();

      expect(scheduledFrames, 0);
      expect(driver.stops, 0);
      expect(platform.writes, isEmpty);
    },
  );

  test('owned renderer is created through session and disposed on close', () {
    final platform = _FakeTerminalPlatform();
    Renderer? created;

    final session = TerminalSession(
      width: 7,
      height: 3,
      headless: false,
      inputDispatcher: _dispatcher(),
      scheduleFrame: () {},
      platform: platform,
      inputDriverFactory: (_) => _FakeTerminalInputDriver(),
      rendererFactory: (width, height) {
        created = Renderer.create(width, height, testing: true);
        return created!;
      },
    );

    expect(session.renderer, same(created));

    session.close();

    expect(() => created!.nextBuffer.clear(Color.black), throwsStateError);
  });

  test('injected renderer remains caller-owned but terminal restore still runs '
      'after setup', () {
    final renderer = Renderer.create(8, 2, testing: true);
    final platform = _FakeTerminalPlatform(stdoutHasTerminal: true);

    final session = TerminalSession(
      width: 8,
      height: 2,
      headless: false,
      inputDispatcher: _dispatcher(),
      renderer: renderer,
      scheduleFrame: () {},
      platform: platform,
      inputDriverFactory: (_) => _FakeTerminalInputDriver(),
    );

    session.close();

    expect(platform.writes.join(), contains('\x1b[?1049l\x1b[?25h\x1b[0m'));
    expect(session.renderer, isNull);
    expect(() => renderer.nextBuffer.clear(Color.black), returnsNormally);

    renderer.dispose();
  });

  test(
    'interactive session requests all modified keys and resets on close',
    () {
      final renderer = Renderer.create(8, 2, testing: true);
      final platform = _FakeTerminalPlatform(stdoutHasTerminal: true);
      addTearDown(renderer.dispose);

      final session = TerminalSession(
        width: 8,
        height: 2,
        headless: false,
        inputDispatcher: _dispatcher(),
        renderer: renderer,
        scheduleFrame: () {},
        platform: platform,
        inputDriverFactory: (_) => _FakeTerminalInputDriver(),
      );
      addTearDown(session.close);

      expect(platform.writes, ['\x1b[>4;2m']);
      expect(platform.stdoutFlushes, 1);

      session.close();

      expect(platform.writes, [
        '\x1b[>4;2m',
        '\x1b[<u',
        '\x1b[>4;0m',
        '\x1b[?1000l\x1b[?1006l',
        '\x1b[?1049l\x1b[?25h\x1b[0m',
      ]);
      expect(platform.stdoutFlushes, 2);
    },
  );

  test(
    'resize ignores non-positive sizes and resizes renderer for positives',
    () {
      final renderer = Renderer.create(5, 2, testing: true);
      final session = TerminalSession(
        width: 5,
        height: 2,
        headless: true,
        inputDispatcher: _dispatcher(),
        renderer: renderer,
        scheduleFrame: () {},
        platform: _FakeTerminalPlatform(),
      );

      expect(session.resize(0, 10), isFalse);
      expect(session.width, 5);
      expect(session.height, 2);

      expect(session.resize(9, 4), isTrue);
      expect(session.width, 9);
      expect(session.height, 4);
      expect(renderer.nextBuffer.width, 9);
      expect(renderer.nextBuffer.height, 4);

      session.close();
      renderer.dispose();
    },
  );

  test('resize failure preserves the last applied dimensions', () {
    final renderer = Renderer.create(5, 2, testing: true);
    final session = TerminalSession(
      width: 5,
      height: 2,
      headless: true,
      inputDispatcher: _dispatcher(),
      renderer: renderer,
      scheduleFrame: () {},
      platform: _FakeTerminalPlatform(),
    );
    renderer.dispose();

    addTearDown(session.close);

    expect(() => session.resize(9, 4), throwsStateError);
    expect(session.width, 5);
    expect(session.height, 2);
  });

  test('same-size resize preserves the current renderer buffer', () {
    final renderer = Renderer.create(5, 2, testing: true);
    final session = TerminalSession(
      width: 5,
      height: 2,
      headless: true,
      inputDispatcher: _dispatcher(),
      renderer: renderer,
      scheduleFrame: () {},
      platform: _FakeTerminalPlatform(),
    );
    final retainedBuffer = renderer.nextBuffer;

    addTearDown(() {
      session.close();
      renderer.dispose();
    });

    expect(session.resize(5, 2), isFalse);
    expect(session.width, 5);
    expect(session.height, 2);
    expect(renderer.nextBuffer, same(retainedBuffer));
    expect(() => retainedBuffer.clear(Color.black), returnsNormally);
  });

  test('resize signal updates dimensions, schedules a frame, and close cancels '
      'subscriptions', () {
    final platform = _FakeTerminalPlatform(
      stdoutHasTerminal: true,
      terminalColumns: 10,
      terminalLines: 4,
    );
    var scheduledFrames = 0;
    final session = TerminalSession(
      width: 5,
      height: 2,
      headless: false,
      inputDispatcher: _dispatcher(),
      scheduleFrame: () => scheduledFrames++,
      platform: platform,
      inputDriverFactory: (_) => _FakeTerminalInputDriver(),
      rendererFactory: (width, height) =>
          Renderer.create(width, height, testing: true),
    );

    platform
      ..terminalColumns = 18
      ..terminalLines = 6
      ..emit(TerminalSignal.resize);

    expect(session.width, 18);
    expect(session.height, 6);
    expect(scheduledFrames, 1);

    session.close();

    expect(platform.canceledSignals, contains(TerminalSignal.resize));
  });

  test('resize after close is a no-op and does not touch the renderer', () {
    final renderer = Renderer.create(5, 2, testing: true);
    final session = TerminalSession(
      width: 5,
      height: 2,
      headless: true,
      inputDispatcher: _dispatcher(),
      renderer: renderer,
      scheduleFrame: () {},
      platform: _FakeTerminalPlatform(),
    );

    session.close();

    expect(session.resize(9, 4), isFalse);
    expect(session.width, 5);
    expect(session.height, 2);
    expect(session.renderer, isNull);
    expect(renderer.nextBuffer.width, 5);
    expect(renderer.nextBuffer.height, 2);

    renderer.dispose();
  });

  test('late resize signal after close does not throw or schedule', () {
    final platform = _FakeTerminalPlatform(
      stdoutHasTerminal: true,
      terminalColumns: 10,
      terminalLines: 4,
    );
    var scheduledFrames = 0;
    final session = TerminalSession(
      width: 5,
      height: 2,
      headless: false,
      inputDispatcher: _dispatcher(),
      scheduleFrame: () => scheduledFrames++,
      platform: platform,
      inputDriverFactory: (_) => _FakeTerminalInputDriver(),
      rendererFactory: (width, height) =>
          Renderer.create(width, height, testing: true),
    );

    session.close();
    scheduledFrames = 0;
    final closedWidth = session.width;
    final closedHeight = session.height;
    platform
      ..terminalColumns = 18
      ..terminalLines = 6;
    expect(() => platform.emit(TerminalSignal.resize), returnsNormally);
    expect(() => session.resize(18, 6), returnsNormally);
    expect(session.width, closedWidth);
    expect(session.height, closedHeight);
    expect(scheduledFrames, 0);
  });

  test(
    'signal handler closes session, restores terminal, and records exit code',
    () {
      final platform = _FakeTerminalPlatform(stdoutHasTerminal: true);
      final driver = _FakeTerminalInputDriver();
      final exits = <int>[];

      final session = TerminalSession(
        width: 6,
        height: 2,
        headless: false,
        inputDispatcher: _dispatcher(),
        scheduleFrame: () {},
        platform: platform,
        inputDriverFactory: (_) => driver,
        rendererFactory: (width, height) =>
            Renderer.create(width, height, testing: true),
        exitProcess: exits.add,
      );

      platform.emit(TerminalSignal.interrupt);

      expect(driver.stops, 1);
      expect(platform.writes.join(), contains('\x1b[?1049l\x1b[?25h\x1b[0m'));
      expect(exits, [130]);

      session.close();

      expect(driver.stops, 1);
      expect(exits, [130]);
    },
  );

  test(
    'unhandled Ctrl+C key event closes and restores the terminal session',
    () {
      final dispatcher = _dispatcher();
      final platform = _FakeTerminalPlatform(stdoutHasTerminal: true);
      final driver = _FakeTerminalInputDriver();
      final exits = <int>[];
      final session = TerminalSession(
        width: 6,
        height: 2,
        headless: false,
        inputDispatcher: dispatcher,
        scheduleFrame: () {},
        platform: platform,
        inputDriverFactory: (_) => driver,
        rendererFactory: (width, height) =>
            Renderer.create(width, height, testing: true),
        exitProcess: exits.add,
      );
      final event = _ctrlC();

      dispatcher.dispatchKeyEvent(event);

      expect(event.isConsumed, isTrue);
      expect(driver.stops, 1);
      expect(platform.writes.join(), contains('\x1b[?1049l\x1b[?25h\x1b[0m'));
      expect(exits, [130]);

      session.close();
      expect(driver.stops, 1);
      expect(exits, [130]);
    },
  );

  test('a higher-priority Ctrl+C handler overrides the session fallback', () {
    final dispatcher = _dispatcher();
    final platform = _FakeTerminalPlatform(stdoutHasTerminal: true);
    final driver = _FakeTerminalInputDriver();
    final exits = <int>[];
    var handled = 0;
    final override = dispatcher.onKey((event) {
      if (event.logicalKey == LogicalKeyboardKey.keyC &&
          event.isControlPressed) {
        handled++;
        event.consume();
      }
    }, priority: InputPriority.app);
    final session = TerminalSession(
      width: 6,
      height: 2,
      headless: false,
      inputDispatcher: dispatcher,
      scheduleFrame: () {},
      platform: platform,
      inputDriverFactory: (_) => driver,
      rendererFactory: (width, height) =>
          Renderer.create(width, height, testing: true),
      exitProcess: exits.add,
    );

    try {
      final event = _ctrlC();
      dispatcher.dispatchKeyEvent(event);

      expect(handled, 1);
      expect(event.isConsumed, isTrue);
      expect(driver.stops, 0);
      expect(exits, isEmpty);
    } finally {
      override.cancel();
      session.close();
    }
  });

  test(
    'renderer factory failure escapes before input or signal acquisition',
    () {
      final factoryError = StateError('renderer factory failed');
      final platform = _FakeTerminalPlatform();
      var driverCreates = 0;

      expect(
        () => TerminalSession(
          width: 6,
          height: 2,
          headless: false,
          inputDispatcher: _dispatcher(),
          scheduleFrame: () {},
          platform: platform,
          rendererFactory: (_, _) => throw factoryError,
          inputDriverFactory: (_) {
            driverCreates++;
            return _FakeTerminalInputDriver();
          },
        ),
        throwsA(same(factoryError)),
      );

      expect(driverCreates, 0);
      expect(platform.watchedSignals, isEmpty);
    },
  );

  test('terminal setup failure stops input acquired before setup', () {
    final renderer = Renderer.create(6, 2, testing: true)..dispose();
    final platform = _FakeTerminalPlatform(stdoutHasTerminal: true);
    final driver = _FakeTerminalInputDriver();

    expect(
      () => TerminalSession(
        width: 6,
        height: 2,
        headless: false,
        inputDispatcher: _dispatcher(),
        renderer: renderer,
        scheduleFrame: () {},
        platform: platform,
        inputDriverFactory: (_) => driver,
      ),
      throwsStateError,
    );

    expect(driver.starts, 1);
    expect(driver.stops, 1);
    expect(platform.writes.join(), contains('\x1b[?1049l\x1b[?25h\x1b[0m'));
    expect(platform.stdoutFlushes, 1);
  });

  test('capability route is installed before input starts', () {
    final renderer = Renderer.create(6, 2, testing: true);
    final dispatcher = _dispatcher();
    final lowerPriorityEvents = <TerminalCapabilityEvent>[];
    final lowerPrioritySubscription = dispatcher.onCapabilityResponse(
      lowerPriorityEvents.add,
      priority: InputPriority.widget - 1,
    );
    final driver = _FakeTerminalInputDriver(
      onStart: () {
        dispatcher.dispatchCapabilityResponse(
          TerminalCapabilityEvent(
            kind: TerminalCapabilityKind.primaryDeviceAttributes,
            payload: '?62;4',
            raw: '\x1b[?62;4c',
          ),
        );
      },
    );
    addTearDown(() {
      lowerPrioritySubscription.cancel();
      renderer.dispose();
    });

    final session = TerminalSession(
      width: 6,
      height: 2,
      headless: false,
      inputDispatcher: dispatcher,
      renderer: renderer,
      scheduleFrame: () {},
      platform: _FakeTerminalPlatform(stdoutHasTerminal: true),
      inputDriverFactory: (_) => driver,
    );
    addTearDown(session.close);

    expect(lowerPriorityEvents, isEmpty);

    session.close();
    renderer.dispose();
    dispatcher.dispatchCapabilityResponse(
      TerminalCapabilityEvent(
        kind: TerminalCapabilityKind.primaryDeviceAttributes,
        payload: '?1',
        raw: '\x1b[?1c',
      ),
    );

    expect(lowerPriorityEvents.map((event) => event.raw), ['\x1b[?1c']);
  });

  test(
    'pixel resolution reports update session state and repaint on change',
    () {
      final renderer = Renderer.create(6, 2, testing: true);
      final dispatcher = _dispatcher();
      var scheduledFrames = 0;
      final session = TerminalSession(
        width: 6,
        height: 2,
        headless: false,
        inputDispatcher: dispatcher,
        renderer: renderer,
        scheduleFrame: () => scheduledFrames++,
        platform: _FakeTerminalPlatform(stdoutHasTerminal: true),
        inputDriverFactory: (_) => _FakeTerminalInputDriver(),
      );
      addTearDown(() {
        session.close();
        renderer.dispose();
      });

      void report(String payload) {
        dispatcher.dispatchCapabilityResponse(
          TerminalCapabilityEvent(
            kind: TerminalCapabilityKind.pixelResolutionReport,
            payload: payload,
            raw: '\x1b[${payload}t',
          ),
        );
      }

      report('4;720;1280');
      expect(session.pixelResolution, const TerminalPixelResolution(1280, 720));
      expect(scheduledFrames, 1);

      report('4;720;1280');
      report('4;0;1280');
      report('4;bad;1280');
      expect(session.pixelResolution, const TerminalPixelResolution(1280, 720));
      expect(scheduledFrames, 1);

      report('4;1080;1920');
      expect(
        session.pixelResolution,
        const TerminalPixelResolution(1920, 1080),
      );
      expect(scheduledFrames, 2);
    },
  );

  test('interactive stdout rejects inactive stdin before setup', () {
    final platform = _FakeTerminalPlatform(stdoutHasTerminal: true);
    final driver = _FakeTerminalInputDriver(acquired: false);
    Renderer? renderer;
    addTearDown(() => renderer?.dispose());

    expect(
      () => TerminalSession(
        width: 6,
        height: 2,
        headless: false,
        inputDispatcher: _dispatcher(),
        scheduleFrame: () {},
        platform: platform,
        rendererFactory: (width, height) {
          renderer = Renderer.create(width, height, testing: true);
          return renderer!;
        },
        inputDriverFactory: (_) => driver,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('terminal stdin'),
        ),
      ),
    );

    expect(driver.starts, 1);
    expect(driver.stops, 1);
    expect(platform.writes, isEmpty);
    expect(() => renderer!.nextBuffer, throwsStateError);
  });

  test('input start failure remains primary when rollback stop also fails', () {
    final startError = StateError('input start failed');
    final stopError = StateError('input stop failed');
    late StackTrace originalStartStack;
    final platform = _FakeTerminalPlatform(stdoutHasTerminal: true);
    final driver = _FakeTerminalInputDriver(
      onStart: () {
        originalStartStack = StackTrace.current;
        Error.throwWithStackTrace(startError, originalStartStack);
      },
      onStop: () => throw stopError,
    );
    Renderer? renderer;
    Object? caughtError;
    StackTrace? caughtStack;
    addTearDown(() => renderer?.dispose());

    try {
      TerminalSession(
        width: 6,
        height: 2,
        headless: false,
        inputDispatcher: _dispatcher(),
        scheduleFrame: () {},
        platform: platform,
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

    expect(caughtError, same(startError));
    expect(caughtStack.toString(), originalStartStack.toString());
    expect(driver.starts, 1);
    expect(driver.stops, 1);
    expect(platform.writes, isEmpty);
    expect(platform.stdoutFlushes, 0);
    expect(() => renderer!.nextBuffer, throwsStateError);
  });

  test('session does not overwrite modes restored by its input driver', () {
    final platform = _FakeTerminalPlatform(stdoutHasTerminal: true);
    final driver = _FakeTerminalInputDriver(
      onStop: () {
        platform
          ..stdinLineMode = false
          ..stdinEchoMode = false;
      },
    );
    final renderer = Renderer.create(6, 2, testing: true);
    addTearDown(renderer.dispose);
    final session = TerminalSession(
      width: 6,
      height: 2,
      headless: false,
      inputDispatcher: _dispatcher(),
      renderer: renderer,
      scheduleFrame: () {},
      platform: platform,
      inputDriverFactory: (_) => driver,
    );

    session.close();

    expect(platform.stdinLineMode, isFalse);
    expect(platform.stdinEchoMode, isFalse);
  });

  test('stop failure does not skip cleanup and close remains at-most-once', () {
    final stopError = StateError('input stop failed');
    final platform = _FakeTerminalPlatform(stdoutHasTerminal: true);
    late TerminalSession session;
    final driver = _FakeTerminalInputDriver(
      onStop: () {
        session.close();
        throw stopError;
      },
    );
    Renderer? renderer;
    addTearDown(() => renderer?.dispose());

    session = TerminalSession(
      width: 6,
      height: 2,
      headless: false,
      inputDispatcher: _dispatcher(),
      scheduleFrame: () {},
      platform: platform,
      rendererFactory: (width, height) {
        renderer = Renderer.create(width, height, testing: true);
        return renderer!;
      },
      inputDriverFactory: (_) => driver,
    );

    expect(session.close, throwsA(same(stopError)));
    expect(driver.stops, 1);
    expect(platform.writes, hasLength(5));
    expect(platform.stdoutFlushes, 2);
    expect(platform.stdinLineModeSets, 0);
    expect(platform.stdinEchoModeSets, 0);
    expect(() => renderer!.nextBuffer, throwsStateError);

    final canceledSignals = List<TerminalSignal>.from(platform.canceledSignals);
    expect(session.close, returnsNormally);
    expect(driver.stops, 1);
    expect(platform.writes, hasLength(5));
    expect(platform.stdoutFlushes, 2);
    expect(platform.stdinLineModeSets, 0);
    expect(platform.stdinEchoModeSets, 0);
    expect(platform.canceledSignals, canceledSignals);
  });

  test(
    'terminal restore actions continue after independent platform failures',
    () {
      final writeError = StateError('stdout write failed');
      final platform = _FakeTerminalPlatform(
        stdoutHasTerminal: true,
        stdoutWriteError: writeError,
        stdoutWriteErrorAttempt: 2,
      );
      final renderer = Renderer.create(6, 2, testing: true);
      addTearDown(renderer.dispose);
      final session = TerminalSession(
        width: 6,
        height: 2,
        headless: false,
        inputDispatcher: _dispatcher(),
        renderer: renderer,
        scheduleFrame: () {},
        platform: platform,
        inputDriverFactory: (_) => _FakeTerminalInputDriver(),
      );

      expect(session.close, returnsNormally);

      expect(platform.stdoutWriteAttempts, 5);
      expect(platform.writes, hasLength(4));
      expect(platform.writes, isNot(contains('\x1b[<u')));
      expect(platform.writes, contains('\x1b[>4;0m'));
      expect(platform.writes, contains('\x1b[?1049l\x1b[?25h\x1b[0m'));
      expect(platform.stdoutFlushes, 2);
      expect(platform.stdinLineModeSets, 0);
      expect(platform.stdinEchoModeSets, 0);
      expect(() => renderer.nextBuffer, returnsNormally);
    },
  );

  test(
    'asynchronous cancellation failures are consumed before leaving close',
    () async {
      final uncaughtErrors = <Object>[];
      final platform = _AsyncCancelErrorPlatform();
      final driver = _FakeTerminalInputDriver();
      Renderer? renderer;
      addTearDown(() => renderer?.dispose());

      await runZonedGuarded(() async {
        final session = TerminalSession(
          width: 6,
          height: 2,
          headless: false,
          inputDispatcher: _dispatcher(),
          scheduleFrame: () {},
          platform: platform,
          rendererFactory: (width, height) {
            renderer = Renderer.create(width, height, testing: true);
            return renderer!;
          },
          inputDriverFactory: (_) => driver,
        );

        session.close();
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => uncaughtErrors.add(error));

      expect(uncaughtErrors, isEmpty);
      expect(platform.cancelAttempts, 4);
      expect(driver.stops, 1);
      expect(platform.writes, hasLength(5));
      expect(() => renderer!.nextBuffer, throwsStateError);
    },
  );
}

InputDispatcher _dispatcher() => InputManager().dispatcher;

class _FakeTerminalInputDriver implements TerminalInputDriver {
  _FakeTerminalInputDriver({this.acquired = true, this.onStart, this.onStop});

  final bool acquired;
  final void Function()? onStart;
  final void Function()? onStop;
  int starts = 0;
  int stops = 0;

  @override
  bool start() {
    starts++;
    onStart?.call();
    return acquired;
  }

  @override
  void stop() {
    stops++;
    onStop?.call();
  }
}

class _FakeTerminalPlatform implements TerminalPlatform {
  _FakeTerminalPlatform({
    bool stdoutHasTerminal = false,
    this.terminalColumns = 80,
    this.terminalLines = 24,
    this.stdoutWriteError,
    this.stdoutWriteErrorAttempt,
  }) : _stdoutHasTerminal = stdoutHasTerminal;

  bool _stdoutHasTerminal;
  bool _stdinLineMode = false;
  bool _stdinEchoMode = false;

  final Error? stdoutWriteError;
  final int? stdoutWriteErrorAttempt;

  int stdoutWriteAttempts = 0;
  int stdoutFlushes = 0;
  int stdinLineModeSets = 0;
  int stdinEchoModeSets = 0;

  @override
  bool get stdoutHasTerminal => _stdoutHasTerminal;

  set stdoutHasTerminal(bool value) => _stdoutHasTerminal = value;

  @override
  bool isWindows = false;

  @override
  int terminalColumns;

  @override
  int terminalLines;

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

  final List<String> writes = [];
  final List<TerminalSignal> watchedSignals = [];
  final List<TerminalSignal> canceledSignals = [];
  final Map<TerminalSignal, StreamController<void>> _controllers = {};

  @override
  void stdoutWrite(String data) {
    stdoutWriteAttempts++;
    final error = stdoutWriteError;
    if (error != null && stdoutWriteAttempts == stdoutWriteErrorAttempt) {
      throw error;
    }
    writes.add(data);
  }

  @override
  void stdoutFlush() {
    stdoutFlushes++;
  }

  @override
  Stream<void> watchSignal(TerminalSignal signal) {
    watchedSignals.add(signal);
    // ignore: close_sinks
    final controller = StreamController<void>.broadcast(
      sync: true,
      onCancel: () => canceledSignals.add(signal),
    );
    _controllers[signal] = controller;
    return controller.stream;
  }

  void emit(TerminalSignal signal) {
    _controllers[signal]!.add(null);
  }
}

class _AsyncCancelErrorPlatform extends _FakeTerminalPlatform {
  _AsyncCancelErrorPlatform() : super(stdoutHasTerminal: true);

  int cancelAttempts = 0;

  @override
  Stream<void> watchSignal(TerminalSignal signal) {
    watchedSignals.add(signal);
    // ignore: close_sinks
    return StreamController<void>(
      sync: true,
      onCancel: () async {
        cancelAttempts++;
        throw StateError('cancel $signal');
      },
    ).stream;
  }
}
