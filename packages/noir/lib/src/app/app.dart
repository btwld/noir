import 'dart:io' as io;

import 'package:meta/meta.dart';

import '../core/input.dart';
import '../foundation/disposable.dart';
import '../foundation/first_error.dart';
import '../foundation/listenable.dart';
import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../widgets/overlay.dart';
import 'driver.dart';
import 'hot_reload.dart';
import 'tui_binding.dart';

/// Mounts [app] and returns its owning application lifecycle facade.
///
/// This is the whole entry point — `void main() => runTuiApp(const MyApp());`.
/// Dart's event loop keeps the process alive after `main()` returns, because
/// the stdin subscription and signal watchers own the lifetime; quitting means
/// disposing the app, not awaiting a future. Call [TuiApp.exit] from anywhere
/// in the tree to do that.
///
/// A real terminal auto-detects its own size and tracks resizes, so there is
/// no size to pass here; a non-TTY or [headless] run gets 80x24. Hosting a
/// custom canvas without a terminal is advanced work — use `TuiBinding` from
/// `package:noir/noir_low_level.dart`, which keeps its size parameters.
///
/// Pass [enableMouse] to turn on mouse reporting as the app mounts; the
/// returned handle still exposes runtime toggles. Movement reporting is enabled
/// for hover pointers; `enableMouse(enableMovement: false)` opts out. Hot reload
/// is registered automatically, so an edited `build()` shows up without extra wiring.
///
/// With `NOIR_DRIVE=1` in the environment the app mounts in drive mode
/// instead: a headless binding painting into a non-terminal renderer, with the
/// `ext.noir.driver.*` service extensions published for an external driver.
/// Drive mode replaces the terminal session, so [headless] does not apply to
/// it; see `createDriveModeHost`. Without that variable the branch is inert
/// and this is the ordinary terminal path.
TuiApp runTuiApp(
  Widget app, {
  bool headless = false,
  bool enableMouse = false,
}) {
  final host = createDriveModeHost(io.Platform.environment);
  if (host != null) {
    try {
      return _mount(
        host.binding,
        app,
        enableMouse: enableMouse,
        exitCodeSink: host.handleAppExit,
        onMounted: host.start,
      );
    } on Object {
      try {
        // The binding borrows its renderer from this host, so mount rollback
        // must also release the host's renderer and any started keep-alive.
        host.dispose();
      } on Object {
        // The startup failure remains primary after every cleanup attempt.
      }
      rethrow;
    }
  }
  if (headless && enableMouse) {
    throw StateError('Mouse support requires a renderer');
  }
  return _mount(
    TuiBinding(headless: headless),
    app,
    enableMouse: enableMouse,
    onMounted: registerHotReloadExtension,
  );
}

/// Builds the handle, wraps [app] in the app scope, and applies mount-time
/// terminal modes and registration before transferring ownership to the caller.
TuiApp _mount(
  TuiBinding binding,
  Widget app, {
  required bool enableMouse,
  void Function(int exitCode)? exitCodeSink,
  void Function(TuiApp app)? onMounted,
}) {
  final handle = TuiApp._(binding, exitCodeSink ?? _defaultExitCodeSink);
  try {
    binding.runApp(
      _TuiAppScope(
        handle: handle,
        child: RootOverlay(child: app),
      ),
    );
    if (enableMouse) {
      handle.enableMouse();
    }
    onMounted?.call(handle);
    return handle;
  } on Object {
    try {
      handle.dispose();
    } on Object {
      // Preserve the mount or activation failure after attempting all cleanup.
    }
    rethrow;
  }
}

/// A soft exit sets the code the process will report once the event loop
/// drains; it never calls `io.exit`, which would cut short pending work.
void _defaultExitCodeSink(int code) {
  io.exitCode = code;
}

/// Creates a facade around an injected binding for package-owned tests.
@internal
@visibleForTesting
TuiApp createTuiAppForTesting(
  TuiBinding binding, {
  void Function(int exitCode)? exitCodeSink,
}) => TuiApp._(binding, exitCodeSink ?? _defaultExitCodeSink);

/// Mounts [app] under a scope wired to a test-owned exit sink.
@internal
@visibleForTesting
TuiApp mountTuiAppForTesting(
  TuiBinding binding,
  Widget app, {
  required void Function(int exitCode) exitCodeSink,
  bool enableMouse = false,
  void Function(TuiApp app)? onMounted,
}) => _mount(
  binding,
  app,
  enableMouse: enableMouse,
  exitCodeSink: exitCodeSink,
  onMounted: onMounted,
);

/// Publishes the owning [TuiApp] to its tree so any widget can end the app.
///
/// The handle never changes for a mounted tree, so lookups deliberately do not
/// register an inherited dependency: there is nothing that could later notify.
class _TuiAppScope extends InheritedWidget {
  const _TuiAppScope({required this.handle, required super.child});

  final TuiApp handle;

  @override
  bool updateShouldNotify(_TuiAppScope oldWidget) =>
      !identical(oldWidget.handle, handle);
}

/// Owns one mounted terminal application and its app-level input handlers.
final class TuiApp implements Disposable {
  TuiApp._(this._binding, this._exitCodeSink);

  final TuiBinding _binding;
  final void Function(int exitCode) _exitCodeSink;
  final Set<InputSubscription> _subscriptions = <InputSubscription>{};
  bool _disposed = false;

  /// Whether this app runs without an owned terminal renderer.
  bool get isHeadless => _binding.isHeadless;

  /// The app enclosing [context], or null when there is none.
  ///
  /// Only a tree mounted by [runTuiApp] has one; a widget under a bare
  /// `TuiBinding` or a widget-test harness does not.
  static TuiApp? maybeOf(BuildContext context) {
    final scope = context
        .getElementForInheritedWidgetOfExactType<_TuiAppScope>()
        ?.widget;
    return scope is _TuiAppScope ? scope.handle : null;
  }

  /// The app enclosing [context], or a [StateError] when there is none.
  static TuiApp of(BuildContext context) {
    final app = maybeOf(context);
    if (app == null) {
      throw StateError(
        'TuiApp.of() called with a context that has no runTuiApp ancestor.',
      );
    }
    return app;
  }

  /// Ends the app enclosing [context] with [code].
  ///
  /// Disposes the app — restoring the terminal and cancelling stdin, signal,
  /// and timer subscriptions — and records the exit code. The event loop then
  /// drains and the process exits on its own.
  ///
  /// Safe to call from an event handler. A second call is a no-op. Throws
  /// [StateError] if called while the tree is building.
  ///
  /// A cleanup step that throws does not stop the exit: the remaining cleanup
  /// still runs, [code] is still recorded unchanged, and the first failure is
  /// rethrown afterwards.
  static void exit(BuildContext context, {int code = 0}) {
    of(context).requestExit(code);
  }

  /// Ends this app with [code]. See [exit] for the tree-facing form.
  void requestExit([int code = 0]) {
    if (_disposed) return;
    if (_binding.buildOwner.isBuilding) {
      // Dispose mid-build strips registrations the in-flight rebuild still
      // needs.
      throw StateError(
        'TuiApp.exit() cannot be called while the tree is building. '
        'Call it from an event handler instead.',
      );
    }
    // A failing cleanup must not leave the host uninformed: this app is
    // already marked disposed, so no later request could deliver the code.
    FirstErrorRecorder()
      ..attempt(dispose)
      ..attempt(() => _exitCodeSink(code))
      ..rethrowFirst();
  }

  /// Registers an app-priority key handler and returns an idempotent canceler.
  VoidCallback onKey(KeyEventHandler handler) {
    _checkNotDisposed();
    return _own(
      _binding.inputManager.onKey(handler, priority: InputPriority.app),
    );
  }

  /// Registers an app-priority mouse handler and returns an idempotent canceler.
  VoidCallback onMouse(MouseEventHandler handler) {
    _checkNotDisposed();
    return _own(
      _binding.inputManager.onMouse(handler, priority: InputPriority.app),
    );
  }

  /// Registers an app-priority paste handler and returns an idempotent canceler.
  VoidCallback onPaste(PasteEventHandler handler) {
    _checkNotDisposed();
    return _own(
      _binding.inputManager.onPaste(handler, priority: InputPriority.app),
    );
  }

  /// Enables terminal mouse reporting, including movement for hover pointers.
  /// Pass `enableMovement: false` for click and drag reporting only.
  void enableMouse({bool enableMovement = true}) {
    _checkNotDisposed();
    _binding.enableMouse(enableMovement: enableMovement);
  }

  /// Disables terminal mouse reporting.
  void disableMouse() {
    _checkNotDisposed();
    _binding.disableMouse();
  }

  /// Enables Kitty keyboard reporting.
  void enableKittyKeyboard({int flags = KittyFlags.disambiguateEscapeCodes}) {
    _checkNotDisposed();
    _binding.enableKittyKeyboard(flags: flags);
  }

  /// Disables Kitty keyboard reporting.
  void disableKittyKeyboard() {
    _checkNotDisposed();
    _binding.disableKittyKeyboard();
  }

  /// Rebuilds the whole widget tree and forces a full repaint.
  ///
  /// Call this after a hot-reload source swap succeeds. Every retained
  /// [State.reassemble] runs, then every `build()` body re-executes once;
  /// owned `State`, focus, scroll, and animation state survive, and no
  /// terminal or native resource is recreated. `main()` and [State.initState]
  /// are not re-run; override [State.reassemble] to re-derive whatever
  /// [State.initState] computed from code the reload may have just changed.
  void reassemble() {
    _checkNotDisposed();
    _binding.reassemble();
  }

  VoidCallback _own(InputSubscription subscription) {
    _subscriptions.add(subscription);
    var cancelled = false;
    return () {
      if (cancelled) return;
      cancelled = true;
      _subscriptions.remove(subscription);
      subscription.cancel();
    };
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('TuiApp is disposed.');
    }
  }

  /// Disposes every owned input registration and the mounted app.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    final failures = FirstErrorRecorder();
    final subscriptions = _subscriptions.toList(growable: false);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      failures.attempt(subscription.cancel);
    }
    failures
      ..attempt(_binding.dispose)
      ..rethrowFirst();
  }
}
