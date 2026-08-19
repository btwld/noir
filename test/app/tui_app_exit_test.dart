import 'dart:io' as io;

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
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

  test('enableMouse on a rendererless headless app fails loudly', () {
    expect(
      () =>
          runTuiApp(const SizedBox.shrink(), headless: true, enableMouse: true),
      throwsA(isA<StateError>()),
    );
  });
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
