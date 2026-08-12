// ignore_for_file: use_setters_to_change_properties
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
    _requestFrame();
  }

  void _stopTicker(Ticker ticker) {
    _activeTickers.remove(ticker);
  }

  void _removeTicker(Ticker ticker) {
    _managedTickers.remove(ticker);
  }

  /// Ticks an active snapshot and requests another frame while work remains.
  void handleFrame(Duration timeStamp) {
    if (_activeTickers.isEmpty) {
      return;
    }

    final tickers = List<Ticker>.from(_activeTickers);
    for (final ticker in tickers) {
      ticker._tick(timeStamp);
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
mixin TickerProviderStateMixin<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  final Set<Ticker> _tickers = <Ticker>{};

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
    for (final ticker in List<Ticker>.of(_tickers)) {
      assert(
        !ticker.isTicking,
        'TickerProviderStateMixin.dispose called with an active ticker. '
        'Dispose your AnimationController before calling super.dispose().',
      );
      ticker.dispose();
    }
    assert(_tickers.isEmpty);
    super.dispose();
  }
}

/// Lets a [State] vend exactly one ticker, disposed with the state.
mixin SingleTickerProviderStateMixin<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  Ticker? _ticker;

  @override
  Ticker createTicker(TickerCallback onTick, {String? debugLabel}) {
    assert(
      _ticker == null,
      'SingleTickerProviderStateMixin can only be used to create a single ticker.',
    );
    final ticker = context.owner.tickerScheduler.createTicker(
      onTick,
      debugLabel: debugLabel ?? _debugTickerLabel(this),
    );
    _ticker = ticker;
    return ticker;
  }

  @override
  void dispose() {
    assert(
      _ticker == null || !_ticker!.isTicking,
      'SingleTickerProviderStateMixin.dispose called with an active ticker. '
      'Dispose your AnimationController before calling super.dispose().',
    );
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

String _debugTickerLabel(State<dynamic> state) {
  final type = state.runtimeType;
  final hash = identityHashCode(state).toRadixString(16);
  return '$type#$hash';
}
