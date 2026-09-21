import 'dart:io' as io;

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/app.dart' show mountTuiAppForTesting;
import 'package:noir/src/app/tui_binding.dart' show createTuiBindingForTesting;
import 'package:test/test.dart';

import '../helpers/tui_test_app.dart';

/// Contract for tree-scoped [TuiApp.exit].
void main() {
  test('exit disposes the app and reports the code through the sink', () async {
    final app = createTuiTestApp(const _ExitOnKey());
    try {
      await _settle(app);
      expect(app.exitRequests, isEmpty);

      app.mockInput.typeText('q');
      await _settle(app);

      expect(app.exitRequests, [0]);
    } finally {
      app.dispose();
    }
  });

  test('exit carries a non-zero code', () async {
    final app = createTuiTestApp(const _ExitOnKey(code: 3));
    try {
      await _settle(app);
      app.mockInput.typeText('q');
      await _settle(app);
      expect(app.exitRequests, [3]);
    } finally {
      app.dispose();
    }
  });

  test('a second exit is a no-op, so a double press cannot throw', () async {
    final app = createTuiTestApp(const _ExitOnKey());
    try {
      await _settle(app);
      app.mockInput.typeText('q');
      await _settle(app);
      // A double-press race is normal: the second press arrives after the
      // first already tore the app down.
      expect(() => app.mockInput.typeText('q'), returnsNormally);
      await _settle(app);
      expect(app.exitRequests, [0]);
    } finally {
      app.dispose();
    }
  });

  test(
    'exiting inside a key dispatch unwinds without touching disposed state',
    () async {
      final app = createTuiTestApp(const _ExitOnKey());
      try {
        await _settle(app);
        // The handler runs mid-dispatch; the stack has to unwind back through
        // FocusManager and InputManager after the binding is already disposed.
        expect(() => app.mockInput.typeText('q'), returnsNormally);
        await _settle(app);
        expect(app.exitRequests, [0]);
        expect(() => app.mockInput.typeText('x'), returnsNormally);
      } finally {
        app.dispose();
      }
    },
  );

  test('exit never mutates the host process exit code', () async {
    final before = io.exitCode;
    final app = createTuiTestApp(const _ExitOnKey(code: 42));
    try {
      await _settle(app);
      app.mockInput.typeText('q');
      await _settle(app);
      expect(app.exitRequests, [42]);
      expect(io.exitCode, before, reason: 'the sink is the only exit path');
    } finally {
      app.dispose();
      io.exitCode = before;
    }
  });

  test('maybeOf returns null with no enclosing app scope', () {
    final owner = BuildOwner();
    TuiApp? seen;
    var probed = false;
    final element = _ScopeProbe(
      onBuild: (app) {
        seen = app;
        probed = true;
      },
    ).createElement();

    element.mount(null, owner);
    owner.buildScope();

    expect(probed, isTrue);
    expect(seen, isNull);
    element.unmount();
  });

  test('of throws a StateError with no enclosing app scope', () {
    final owner = BuildOwner();
    Object? thrown;
    final element = _StrictScopeProbe(
      onError: (error) => thrown = error,
    ).createElement();

    element.mount(null, owner);
    owner.buildScope();

    expect(thrown, isA<StateError>());
    element.unmount();
  });

  test('runTuiApp wraps the tree so of() finds the handle', () {
    TuiApp? seen;
    final app = runTuiApp(
      _ScopeProbe(onBuild: (found) => seen = found),
      headless: true,
    );
    try {
      expect(seen, same(app));
    } finally {
      app.dispose();
    }
  });

  test('exit during build is rejected instead of corrupting the tree', () {
    // Dispose during build leaves the in-flight rebuild without a parent.
    expect(
      () => runTuiApp(const _ExitInBuild(), headless: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('event handler'),
        ),
      ),
    );
  });

  group('exit after a cleanup failure', () {
    test('still notifies the sink once and rethrows the cleanup error', () {
      final disposeError = StateError('state dispose failed');
      final disposeStack = StackTrace.fromString('original dispose stack');
      final exits = <int>[];
      var disposals = 0;
      final app = _mountForExit(
        _DisposeProbe(
          onDispose: () {
            disposals++;
            Error.throwWithStackTrace(disposeError, disposeStack);
          },
        ),
        exitCodeSink: exits.add,
      );

      Object? caught;
      StackTrace? caughtStack;
      try {
        app.requestExit(7);
      } on Object catch (error, stackTrace) {
        caught = error;
        caughtStack = stackTrace;
      }

      expect(caught, same(disposeError));
      expect(caughtStack.toString(), disposeStack.toString());
      expect(exits, [7], reason: 'the host still learns the requested code');
      expect(disposals, 1);

      expect(() => app.requestExit(9), returnsNormally);
      expect(exits, [7], reason: 'a second request notifies nobody');
      expect(disposals, 1);
    });

    test('keeps the cleanup error primary when the sink also throws', () {
      final disposeError = StateError('state dispose failed');
      var notifications = 0;
      final app = _mountForExit(
        _DisposeProbe(onDispose: () => throw disposeError),
        exitCodeSink: (_) {
          notifications++;
          throw StateError('sink failed');
        },
      );

      expect(app.requestExit, throwsA(same(disposeError)));
      expect(notifications, 1);
    });

    test('propagates a sink failure after a clean disposal', () {
      final sinkError = StateError('sink failed');
      var disposals = 0;
      final app = _mountForExit(
        _DisposeProbe(onDispose: () => disposals++),
        exitCodeSink: (_) => throw sinkError,
      );

      expect(app.requestExit, throwsA(same(sinkError)));
      expect(disposals, 1);
      expect(app.requestExit, returnsNormally);
    });
  });

  test('enableMouse on a rendererless headless app fails loudly', () {
    expect(
      () =>
          runTuiApp(const SizedBox.shrink(), headless: true, enableMouse: true),
      throwsA(isA<StateError>()),
    );
  });
}

/// Mounts [widget] under a caller-owned exit sink and returns the app handle.
TuiApp _mountForExit(
  Widget widget, {
  required void Function(int exitCode) exitCodeSink,
}) {
  final renderer = Renderer.create(8, 2, testing: true)..setAutoFlush(false);
  addTearDown(renderer.dispose);
  final binding = createTuiBindingForTesting(
    width: 8,
    height: 2,
    headless: true,
    renderer: renderer,
  );
  return mountTuiAppForTesting(binding, widget, exitCodeSink: exitCodeSink);
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}

/// Requests exit from a key handler.
class _ExitOnKey extends StatelessWidget {
  const _ExitOnKey({this.code = 0});

  final int code;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event.isPress && event.character == 'q') {
        TuiApp.exit(context, code: code);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: const Text('press q'),
  );
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
    try {
      widget.onDispose();
    } finally {
      super.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Calls [TuiApp.exit] from `build()`, which must fail.
class _ExitInBuild extends StatelessWidget {
  const _ExitInBuild();

  @override
  Widget build(BuildContext context) {
    TuiApp.exit(context);
    return const SizedBox.shrink();
  }
}

class _ScopeProbe extends StatelessWidget {
  const _ScopeProbe({required this.onBuild});

  final void Function(TuiApp? app) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(TuiApp.maybeOf(context));
    return const SizedBox.shrink();
  }
}

class _StrictScopeProbe extends StatelessWidget {
  const _StrictScopeProbe({required this.onError});

  final void Function(Object error) onError;

  @override
  Widget build(BuildContext context) {
    try {
      TuiApp.of(context);
    } on Object catch (error) {
      onError(error);
    }
    return const SizedBox.shrink();
  }
}
