import 'package:meta/meta.dart';

/// Prevents hook-owned rebuilds during synchronous effect execution.
///
/// Noir resolves `useEffect` while its `HookWidget` is building. Its
/// `BuildOwner` also drains rebuilds scheduled during a build before returning.
/// Without this guard, a keyless effect that updates hook state can schedule
/// itself repeatedly and keep that drain from completing.
///
/// The guard stays inside the unexported hooks implementation so the optional
/// `package:noir/hooks.dart` surface does not add an effect dependency to core
/// `State` or `BuildOwner`. `HookState.setState` is the hook-owned scheduling
/// boundary that consults it. Ordinary `State.setState` remains a core
/// framework concern and is not intercepted here.
@internal
final class EffectExecutionGuard {
  EffectExecutionGuard._();

  // Static state is isolate-local in Dart. Because effects and cleanup are
  // synchronous, callbacks scheduled for later run after run() restores this.
  static bool _isActive = false;

  /// Whether a synchronous effect or cleanup callback is currently running.
  static bool get isActive => _isActive;

  /// Runs [callback] with the effect guard active and restores prior state.
  ///
  /// Saving the previous value keeps nested guarded calls correct. The
  /// `finally` block also prevents a throwing effect or cleanup from leaving
  /// unrelated later callbacks guarded.
  static T run<T>(T Function() callback) {
    final wasActive = _isActive;
    _isActive = true;
    try {
      return callback();
    } finally {
      _isActive = wasActive;
    }
  }
}
