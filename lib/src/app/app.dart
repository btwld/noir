import 'dart:io' as io;

import 'package:meta/meta.dart';

import '../core/input.dart';
import '../foundation/disposable.dart';
import '../foundation/first_error.dart';
import '../foundation/listenable.dart';
import '../framework/widget.dart';
import 'driver.dart';
import 'tui_binding.dart';

/// Mounts [app] and returns its owning application lifecycle facade.
///
/// With `NOIR_DRIVE=1` in the environment the app mounts in drive mode
/// instead: a headless binding painting into a non-terminal renderer, with the
/// `ext.noir.driver.*` service extensions published for an external driver.
/// Drive mode replaces the terminal session, so [width], [height], and
/// [headless] do not apply to it; see `createDriveModeHost`. Without that
/// variable the branch is inert and this is the ordinary terminal path.
TuiApp runTuiApp(
  Widget app, {
  int width = 80,
  int height = 24,
  bool headless = false,
}) {
  final host = createDriveModeHost(io.Platform.environment);
  if (host != null) {
    host.binding.runApp(app);
    final driven = TuiApp._(host.binding);
    host.start(driven);
    return driven;
  }
  final binding = TuiBinding(width: width, height: height, headless: headless)
    ..runApp(app);
  return TuiApp._(binding);
}

/// Creates a facade around an injected binding for package-owned tests.
@internal
@visibleForTesting
TuiApp createTuiAppForTesting(TuiBinding binding) => TuiApp._(binding);

/// Owns one mounted terminal application and its app-level input handlers.
final class TuiApp implements Disposable {
  TuiApp._(this._binding);

  final TuiBinding _binding;
  final Set<InputSubscription> _subscriptions = <InputSubscription>{};
  bool _disposed = false;

  /// Whether this app runs without an owned terminal renderer.
  bool get isHeadless => _binding.isHeadless;

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

  /// Enables terminal mouse reporting.
  void enableMouse({bool enableMovement = false}) {
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
