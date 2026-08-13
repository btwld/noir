// ignore_for_file: use_setters_to_change_properties
import 'dart:async';

import 'package:meta/meta.dart';

/// Callback invoked when a scheduled frame begins.
typedef SchedulerFrameCallback = void Function(Duration timeStamp);

/// Clock used by [SchedulerBinding].
@visibleForTesting
typedef SchedulerClock = DateTime Function();

/// Timer factory used by [SchedulerBinding].
@visibleForTesting
typedef SchedulerTimerFactory =
    SchedulerTimer Function(Duration delay, void Function() callback);

/// Cancellable timer handle used by [SchedulerBinding].
@visibleForTesting
abstract interface class SchedulerTimer {
  /// Cancels the timer.
  void cancel();
}

/// Internal owner for app frame timing and animation pacing.
class SchedulerBinding {
  /// Validates frame rate and prepares coalesced frame timers.
  SchedulerBinding({
    int targetFramesPerSecond = 60,
    @visibleForTesting SchedulerClock? clock,
    @visibleForTesting SchedulerTimerFactory? timerFactory,
  }) : assert(targetFramesPerSecond > 0),
       _frameInterval = Duration(
         microseconds: Duration.microsecondsPerSecond ~/ targetFramesPerSecond,
       ),
       _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? _DartSchedulerTimer.new;

  final Duration _frameInterval;
  final SchedulerClock _clock;
  final SchedulerTimerFactory _timerFactory;

  SchedulerFrameCallback? _frameCallback;
  SchedulerTimer? _pendingTimer;
  DateTime? _firstFrameTime;
  DateTime? _lastFrameTime;
  bool _disposed = false;

  /// Whether a frame timer is currently pending.
  @visibleForTesting
  bool get hasScheduledFrame => _pendingTimer != null;

  /// Flush the pending frame synchronously in integration tests.
  @visibleForTesting
  void debugFlushFrame([Duration timestamp = Duration.zero]) {
    if (_disposed) {
      return;
    }
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _frameCallback?.call(timestamp);
  }

  /// Sets the callback invoked when a scheduled frame begins.
  void setFrameCallback(SchedulerFrameCallback? callback) {
    _frameCallback = callback;
  }

  /// Requests a frame, coalescing with any pending request.
  void scheduleFrame() {
    if (_disposed || _frameCallback == null || _pendingTimer != null) {
      return;
    }

    final delay = _delayUntilNextFrame();
    _pendingTimer = _timerFactory(delay, _handleTimer);
  }

  /// Cancels pending work and blocks future frame delivery.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _frameCallback = null;
  }

  void _handleTimer() {
    final timer = _pendingTimer;
    if (timer == null) {
      return;
    }
    _pendingTimer = null;

    if (_disposed) {
      return;
    }
    final callback = _frameCallback;
    if (callback == null) {
      return;
    }

    final now = _clock();
    _firstFrameTime ??= now;
    _lastFrameTime = now;
    final timeStamp = now.difference(_firstFrameTime!);

    callback(timeStamp);
  }

  Duration _delayUntilNextFrame() {
    final lastFrameTime = _lastFrameTime;
    if (lastFrameTime == null) {
      return Duration.zero;
    }

    final elapsed = _clock().difference(lastFrameTime);
    if (elapsed >= _frameInterval) {
      return Duration.zero;
    }
    return _frameInterval - elapsed;
  }
}

class _DartSchedulerTimer implements SchedulerTimer {
  _DartSchedulerTimer(Duration delay, void Function() callback)
    : _timer = Timer(delay, callback);

  final Timer _timer;

  @override
  void cancel() {
    _timer.cancel();
  }
}
