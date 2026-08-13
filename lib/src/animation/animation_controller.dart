import 'dart:async';

import 'animation.dart';
import 'ticker.dart';

/// Drives a value between [lowerBound] and [upperBound] on ticks from
/// [vsync].
class AnimationController extends Animation<double> {
  /// Validates bounds and initial value, with a 300 ms forward duration by default.
  AnimationController({
    required this.vsync,
    this.duration = const Duration(milliseconds: 300),
    this.reverseDuration,
    this.lowerBound = 0.0,
    this.upperBound = 1.0,
    double value = 0.0,
    this.debugLabel,
  }) : assert(upperBound >= lowerBound),
       assert(value >= lowerBound && value <= upperBound),
       _value = value,
       _status = (value <= lowerBound)
           ? AnimationStatus.dismissed
           : (value >= upperBound
                 ? AnimationStatus.completed
                 : AnimationStatus.forward);

  /// Provider used to create the frame-driven ticker for this controller.
  final TickerProvider vsync;

  /// Minimum value, reverse target, and dismissed endpoint.
  final double lowerBound;

  /// Maximum value, forward target, and completed endpoint.
  final double upperBound;

  /// Optional diagnostic label forwarded to the controller's ticker.
  final String? debugLabel;

  /// Full-range forward duration; partial-distance runs scale proportionally.
  Duration duration;

  /// Full-range reverse duration, or `null` to use [duration].
  Duration? reverseDuration;

  late final Ticker _ticker = vsync.createTicker(_tick, debugLabel: debugLabel);
  final List<AnimationStatusListener> _statusListeners =
      <AnimationStatusListener>[];

  double _value;
  AnimationStatus _status;
  bool _isAnimatingForward = true;
  double _beginValue = 0;
  double _endValue = 0;

  // The wall-clock length of the run currently in flight, frozen at
  // forward()/reverse() start. It is `duration`/`reverseDuration` scaled by
  // how much of [lowerBound, upperBound] this run actually travels, so a
  // partial-distance run (e.g. forward(from: 0.5)) takes proportionally
  // less time than a full-range run. See _scaledDuration.
  Duration _runDuration = Duration.zero;
  Completer<void>? _completer;

  static const double _completionTolerance = 1e-6;

  @override
  double get value => _value;

  set value(double newValue) {
    final clamped = newValue.clamp(lowerBound, upperBound);
    if ((clamped - _value).abs() < _completionTolerance) {
      return;
    }
    _value = clamped;

    if (_ticker.isTicking) {
      if ((_isAnimatingForward && _value >= _endValue - _completionTolerance) ||
          (!_isAnimatingForward &&
              _value <= _endValue + _completionTolerance)) {
        _finishAnimation();
      }
    } else {
      _updateStatusForValue();
    }

    notifyListeners();
  }

  @override
  AnimationStatus get status => _status;

  /// Whether this controller's ticker is currently active.
  bool get isAnimating => _ticker.isTicking;

  /// Starts the animation running towards [upperBound].
  ///
  /// Returns a [Future] that completes when *this* run ends: it reached
  /// [upperBound] naturally, was superseded by a later [forward] or
  /// [reverse] call, was stopped via [stop] or [reset], or the controller
  /// was [dispose]d. The Future reports only that the run ended; it carries
  /// no cancellation or outcome signal. After it completes, [status] is the
  /// controller's current state and may already describe a replacement run.
  ///
  /// The run's wall-clock length is [duration] scaled by the fraction of
  /// `[lowerBound, upperBound]` actually traveled, so `forward(from: 0.5)`
  /// over the default `[0.0, 1.0]` range takes half of [duration].
  Future<void> forward({double? from}) {
    if (isAnimating) {
      stop();
    }
    _isAnimatingForward = true;
    if (from != null) {
      value = from;
    }
    _beginValue = value;
    _endValue = upperBound;

    if ((_beginValue - _endValue).abs() <= _completionTolerance) {
      _setStatus(AnimationStatus.completed);
      return Future<void>.value();
    }

    if (duration == Duration.zero) {
      value = _endValue;
      _setStatus(AnimationStatus.completed);
      return Future<void>.value();
    }

    _runDuration = _scaledDuration(duration);
    _setStatus(AnimationStatus.forward);
    _ticker.start();
    return _ensureCompleter();
  }

  /// Starts the animation running towards [lowerBound].
  ///
  /// Returns a [Future] that completes when *this* run ends: it reached
  /// [lowerBound] naturally, was superseded by a later [forward] or
  /// [reverse] call, was stopped via [stop] or [reset], or the controller
  /// was [dispose]d. The Future reports only that the run ended; it carries
  /// no cancellation or outcome signal. After it completes, [status] is the
  /// controller's current state and may already describe a replacement run.
  ///
  /// The run's wall-clock length is `reverseDuration ?? duration` scaled by
  /// the fraction of `[lowerBound, upperBound]` actually traveled, so
  /// `reverse(from: 0.5)` over the default `[0.0, 1.0]` range takes half of
  /// that duration.
  Future<void> reverse({double? from}) {
    if (isAnimating) {
      stop();
    }
    _isAnimatingForward = false;
    if (from != null) {
      value = from;
    }
    _beginValue = value;
    _endValue = lowerBound;

    if ((_beginValue - _endValue).abs() <= _completionTolerance) {
      _setStatus(AnimationStatus.dismissed);
      return Future<void>.value();
    }

    final totalDuration = reverseDuration ?? duration;
    if (totalDuration == Duration.zero) {
      value = _endValue;
      _setStatus(AnimationStatus.dismissed);
      return Future<void>.value();
    }

    _runDuration = _scaledDuration(totalDuration);
    _setStatus(AnimationStatus.reverse);
    _ticker.start();
    return _ensureCompleter();
  }

  /// Stops the running animation in place, without changing [value].
  ///
  /// If a run is in progress, completes that run's pending [Future] (the
  /// one returned by the [forward] or [reverse] call that started it) and
  /// updates [status] to reflect the current [value] (`dismissed`,
  /// `completed`, `forward`, or `reverse`).
  ///
  /// The completed Future reports only that the run ended; it carries no
  /// cancellation or outcome signal. When that Future is observed
  /// asynchronously, [status] is the controller's current state and may
  /// already describe a replacement run. Register an [addStatusListener]
  /// before starting a run when its status transitions matter.
  void stop() {
    if (!isAnimating) {
      return;
    }
    _ticker.stop();
    final old = _takeCompleter();
    _updateStatusForValue();
    old?.complete();
  }

  /// Stops the current run, restores [lowerBound], and publishes dismissed status.
  void reset() {
    stop();
    value = lowerBound;
    _setStatus(AnimationStatus.dismissed);
  }

  @override
  void addStatusListener(AnimationStatusListener listener) {
    _statusListeners.add(listener);
  }

  @override
  void removeStatusListener(AnimationStatusListener listener) {
    _statusListeners.remove(listener);
  }

  @override
  void dispose() {
    _ticker.dispose();
    final old = _takeCompleter();
    old?.complete();
    _statusListeners.clear();
    super.dispose();
  }

  Future<void> _ensureCompleter() {
    _completer ??= Completer<void>();
    return _completer!.future;
  }

  Completer<void>? _takeCompleter() {
    final old = _completer;
    _completer = null;
    return old;
  }

  void _tick(Duration elapsed) {
    final runIdentity = _completer;
    if (_runDuration <= Duration.zero) {
      value = _endValue;
      if (identical(_completer, runIdentity)) {
        _finishAnimation();
      }
      return;
    }
    final fraction = (elapsed.inMicroseconds / _runDuration.inMicroseconds)
        .clamp(0.0, 1.0);
    final isComplete = (1.0 - fraction) <= _completionTolerance;
    final delta = _endValue - _beginValue;
    value = isComplete ? _endValue : _beginValue + delta * fraction;
    if (!identical(_completer, runIdentity)) {
      return;
    }
    if (isComplete) {
      _finishAnimation();
    }
  }

  // Scales `full` (duration or reverseDuration) by the fraction of
  // [lowerBound, upperBound] that this run's [_beginValue] -> [_endValue]
  // travel actually covers, so a partial-distance run takes proportionally
  // less wall-clock time than a full-range run. This matches Flutter's
  // AnimationController._animateToInternal remainingFraction scaling.
  Duration _scaledDuration(Duration full) {
    final range = upperBound - lowerBound;
    if (range <= 0) {
      return full;
    }
    final fraction = (_endValue - _beginValue).abs() / range;
    return full * fraction;
  }

  void _finishAnimation() {
    _ticker.stop();
    final old = _takeCompleter();
    _setStatus(
      _isAnimatingForward
          ? AnimationStatus.completed
          : AnimationStatus.dismissed,
    );
    old?.complete();
  }

  void _setStatus(AnimationStatus newStatus) {
    if (_status == newStatus) {
      return;
    }
    _status = newStatus;
    final listeners = List<AnimationStatusListener>.from(_statusListeners);
    for (final listener in listeners) {
      listener(newStatus);
    }
  }

  void _updateStatusForValue() {
    if (_value <= lowerBound + _completionTolerance) {
      _setStatus(AnimationStatus.dismissed);
    } else if (_value >= upperBound - _completionTolerance) {
      _setStatus(AnimationStatus.completed);
    } else {
      _setStatus(
        _isAnimatingForward ? AnimationStatus.forward : AnimationStatus.reverse,
      );
    }
  }
}
