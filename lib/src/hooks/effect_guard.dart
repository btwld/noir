import 'package:meta/meta.dart';

/// Tracks synchronous effect and cleanup execution within the current isolate.
@internal
final class EffectExecutionGuard {
  EffectExecutionGuard._();

  static bool _isActive = false;

  /// Whether a synchronous effect or cleanup callback is currently running.
  static bool get isActive => _isActive;

  /// Runs [callback] with the effect guard active and restores prior state.
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
