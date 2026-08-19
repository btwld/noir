// ignore_for_file: use_setters_to_change_properties
import 'dart:async';

import 'package:meta/meta.dart';

import '../foundation/first_error.dart';
import '../framework/widget.dart';

/// Signature of a per-frame tick given the time elapsed since the ticker
/// started.
typedef TickerCallback = void Function(Duration elapsed);

/// Interface for objects that vend [Ticker]s driven by the frame scheduler.
abstract class TickerProvider {
  /// Returns a ticker driven by this provider's frame scheduler.
  Ticker createTicker(TickerCallback onTick, {String? debugLabel});
}

/// Owns ticker registration and ticks every active ticker once per frame.
class TickerScheduler {
  /// Initializes an empty ticker registry with no frame-request callback.
  TickerScheduler();

  final Set<Ticker> _managedTickers = <Ticker>{};
  final Set<Ticker> _activeTickers = <Ticker>{};
  void Function()? _frameCallback;
  bool _isHandlingFrame = false;

  /// Replaces the callback used to request a frame; `null` disables requests.
  void setFrameCallback(void Function()? callback) {
    _frameCallback = callback;
  }

  /// Registers and returns an inactive ticker that unregisters on disposal.
  ///
  /// [onDispose] also runs when the ticker is disposed; framework ticker
  /// providers use it to drop their own tracking references.
  Ticker createTicker(
    TickerCallback onTick, {
    String? debugLabel,
    void Function(Ticker)? onDispose,
  }) {
    final ticker = Ticker._(
      onTick,
      this,
      debugLabel: debugLabel,
      onDispose: onDispose,
    );
    _managedTickers.add(ticker);
    return ticker;
  }

  void _startTicker(Ticker ticker) {
    _activeTickers.add(ticker);
    if (!_isHandlingFrame) {
      _requestFrame();
    }
  }

  void _stopTicker(Ticker ticker) {
    _activeTickers.remove(ticker);
  }

  void _removeTicker(Ticker ticker) {
    _managedTickers.remove(ticker);
  }

  /// Ticks an active snapshot and requests another frame while work remains.
  ///
  /// Callback failures are reported with their original stack traces to the
  /// zone in which this frame dispatch began. One ticker cannot starve a
  /// sibling or suppress the next frame while active work remains.
  void handleFrame(Duration timeStamp) {
    if (_activeTickers.isEmpty) {
      return;
    }

    _isHandlingFrame = true;
    try {
      final reportingZone = Zone.current;
      final tickers = List<Ticker>.from(_activeTickers);
      for (final ticker in tickers) {
        try {
          ticker._tick(timeStamp);
        } on Object catch (error, stackTrace) {
          reportingZone.handleUncaughtError(error, stackTrace);
        }
      }
    } finally {
      _isHandlingFrame = false;
    }

    if (_activeTickers.isNotEmpty) {
      _requestFrame();
    }
  }

  void _requestFrame() {
    _frameCallback?.call();
  }
}

/// Invokes its callback each frame while active with the elapsed time since
/// [start].
class Ticker {
  Ticker._(
    this._callback,
    this._scheduler, {
    this.debugLabel,
    void Function(Ticker)? onDispose,
  }) : _onDispose = onDispose;

  final TickerCallback _callback;
  final TickerScheduler _scheduler;
  void Function(Ticker)? _onDispose;

  /// Optional diagnostic label with no effect on timing.
  final String? debugLabel;

  bool _isActive = false;
  bool _isDisposed = false;
  Duration? _startTime;

  /// Whether this ticker is active in its scheduler.
  bool get isTicking => _isActive;

  /// Whether this ticker has reached its terminal disposed state.
  bool get isDisposed => _isDisposed;

  /// Activates and schedules this ticker; no-ops if active and throws if disposed.
  void start() {
    if (_isDisposed) {
      throw StateError('Ticker $debugLabel has been disposed');
    }
    if (_isActive) {
      return;
    }
    _isActive = true;
    _startTime = null;
    _scheduler._startTicker(this);
  }

  /// Deactivates and resets elapsed time; does nothing when already inactive.
  void stop() {
    if (!_isActive) {
      return;
    }
    _isActive = false;
    _startTime = null;
    _scheduler._stopTicker(this);
  }

  /// Idempotently stops, unregisters, and invokes the owner hook once.
  void dispose() {
    if (_isDisposed) {
      return;
    }
    stop();
    _scheduler._removeTicker(this);
    _isDisposed = true;
    final onDispose = _onDispose;
    _onDispose = null;
    onDispose?.call(this);
  }

  void _tick(Duration timeStamp) {
    if (!_isActive) {
      return;
    }
    _startTime ??= timeStamp;
    final elapsed = timeStamp - _startTime!;
    _callback(elapsed);
  }
}

/// Lets a [State] vend any number of tickers, disposing the survivors with
/// the state.
///
/// A ticker still running at [dispose] is misuse and is reported in every
/// build mode, not just debug — an [AnimationController] that outlives its
/// [State] keeps requesting frames forever. Teardown still completes first:
/// every ticker is disposed and the full `super.dispose()` chain runs before
/// the first failure is thrown.
mixin TickerProviderStateMixin<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  final Set<Ticker> _tickers = <Ticker>{};

  /// Number of live tickers this provider is still tracking.
  @visibleForTesting
  int get debugTrackedTickerCount => _tickers.length;

  @override
  Ticker createTicker(TickerCallback onTick, {String? debugLabel}) {
    final ticker = context.owner.tickerScheduler.createTicker(
      onTick,
      debugLabel: debugLabel ?? _debugTickerLabel(this),
      onDispose: _removeTicker,
    );
    _tickers.add(ticker);
    return ticker;
  }

  void _removeTicker(Ticker ticker) {
    assert(
      _tickers.contains(ticker),
      'TickerProviderStateMixin received an untracked ticker disposal.',
    );
    _tickers.remove(ticker);
  }

  @override
  void dispose() {
    final failures = FirstErrorRecorder();
    for (final ticker in List<Ticker>.of(_tickers)) {
      failures
        ..attempt(() => _rejectActiveTicker(ticker, 'TickerProviderStateMixin'))
        ..attempt(ticker.dispose);
    }
    failures
      ..attempt(super.dispose)
      ..rethrowFirst();
  }
}

/// Lets a [State] vend exactly one ticker, disposed with the state.
///
/// Both the one-ticker cardinality and the ticker-still-running-at-teardown
/// check are enforced in every build mode, not just debug: a second ticker
/// would be dropped on the floor, and a surviving one requests frames forever.
mixin SingleTickerProviderStateMixin<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  Ticker? _ticker;

  @override
  Ticker createTicker(TickerCallback onTick, {String? debugLabel}) {
    // Rejected before the scheduler mints anything, so a rejected second
    // request leaves no untracked ticker behind.
    if (_ticker != null) {
      throw StateError(
        'SingleTickerProviderStateMixin can only be used to create a single '
        'ticker. Use TickerProviderStateMixin to vend more than one.',
      );
    }
    final ticker = context.owner.tickerScheduler.createTicker(
      onTick,
      debugLabel: debugLabel ?? _debugTickerLabel(this),
    );
    _ticker = ticker;
    return ticker;
  }

  @override
  void dispose() {
    final failures = FirstErrorRecorder();
    final ticker = _ticker;
    if (ticker != null) {
      failures
        ..attempt(
          () => _rejectActiveTicker(ticker, 'SingleTickerProviderStateMixin'),
        )
        ..attempt(ticker.dispose);
    }
    _ticker = null;
    failures
      ..attempt(super.dispose)
      ..rethrowFirst();
  }
}

/// Rejects a ticker that is still running when its owning [State] tears down.
void _rejectActiveTicker(Ticker ticker, String mixinName) {
  if (!ticker.isTicking) {
    return;
  }
  throw StateError(
    '$mixinName.dispose called with an active ticker. Dispose your '
    'AnimationController before calling super.dispose().',
  );
}

String _debugTickerLabel(State<dynamic> state) {
  final type = state.runtimeType;
  final hash = identityHashCode(state).toRadixString(16);
  return '$type#$hash';
}
