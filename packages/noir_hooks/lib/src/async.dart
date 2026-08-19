// The stream hook retains subscriptions and cancels them in lifecycle cleanup.
// ignore_for_file: cancel_subscriptions

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:noir/noir.dart';

import 'framework.dart';

/// The connection phase represented by an [AsyncSnapshot].
enum ConnectionState {
  /// No asynchronous computation is connected.
  none,

  /// A future or stream is connected but has not produced a value.
  waiting,

  /// A stream has produced at least one event and remains connected.
  active,

  /// The connected future or stream has completed.
  done,
}

/// Immutable state from a future or stream observed by a hook.
@immutable
final class AsyncSnapshot<T> {
  const AsyncSnapshot._(
    this.connectionState,
    this.data,
    this.error,
    this.stackTrace,
  );

  /// Creates a disconnected snapshot with no data or error.
  const AsyncSnapshot.nothing()
    : this._(ConnectionState.none, null, null, null);

  /// Creates a snapshot in [connectionState] containing [data].
  const AsyncSnapshot.withData(ConnectionState connectionState, T data)
    : this._(connectionState, data, null, null);

  /// Creates a snapshot in [connectionState] containing an error.
  const AsyncSnapshot.withError(
    ConnectionState connectionState,
    Object error, [
    StackTrace? stackTrace,
  ]) : this._(connectionState, null, error, stackTrace);

  /// Current asynchronous connection phase.
  final ConnectionState connectionState;

  /// Most recent data value, when present.
  final T? data;

  /// Most recent asynchronous error, when present.
  final Object? error;

  /// Stack trace associated with [error], when available.
  final StackTrace? stackTrace;

  /// Whether [data] is non-null.
  bool get hasData => data != null;

  /// Whether this snapshot contains an [error].
  bool get hasError => error != null;

  /// Returns [data], or rethrows [error], or throws when no data exists.
  T get requireData {
    final currentError = error;
    if (currentError != null) {
      Error.throwWithStackTrace(currentError, stackTrace ?? StackTrace.current);
    }
    final currentData = data;
    if (currentData == null) {
      throw StateError('AsyncSnapshot has neither data nor an error.');
    }
    return currentData;
  }

  /// Returns a snapshot with [state] and the same data or error payload.
  AsyncSnapshot<T> inState(ConnectionState state) =>
      AsyncSnapshot<T>._(state, data, error, stackTrace);

  @override
  bool operator ==(Object other) =>
      other is AsyncSnapshot<T> &&
      other.connectionState == connectionState &&
      other.data == data &&
      other.error == error &&
      other.stackTrace == stackTrace;

  @override
  int get hashCode => Object.hash(connectionState, data, error, stackTrace);

  @override
  String toString() =>
      'AsyncSnapshot($connectionState, data: $data, error: $error)';
}

/// Observes [future] and rebuilds as it completes.
///
/// A replacement future ignores stale completion callbacks. When
/// [preserveState] is true, the previous data or error remains visible while
/// the replacement future is waiting. [initialData] is used only when this
/// hook state is first created or when state preservation is disabled.
AsyncSnapshot<T> useFuture<T>(
  Future<T>? future, {
  T? initialData,
  bool preserveState = true,
}) => use(
  _FutureHook<T>(
    future: future,
    initialData: initialData,
    preserveState: preserveState,
  ),
);

/// Observes [stream] and rebuilds for data, error, and completion events.
///
/// Replacing the stream cancels the old subscription. When [preserveState] is
/// true, its last payload remains visible while the replacement stream waits.
AsyncSnapshot<T> useStream<T>(
  Stream<T>? stream, {
  T? initialData,
  bool preserveState = true,
}) => use(
  _StreamHook<T>(
    stream: stream,
    initialData: initialData,
    preserveState: preserveState,
  ),
);

final class _FutureHook<T> extends Hook<AsyncSnapshot<T>> {
  const _FutureHook({
    required this.future,
    required this.initialData,
    required this.preserveState,
  });

  final Future<T>? future;
  final T? initialData;
  final bool preserveState;

  @override
  _FutureHookState<T> createState() => _FutureHookState<T>();
}

final class _FutureHookState<T>
    extends HookState<AsyncSnapshot<T>, _FutureHook<T>> {
  late AsyncSnapshot<T> _snapshot;
  _AsyncIdentity? _activeIdentity;

  @override
  void initHook() {
    _snapshot = _initialSnapshot(hook.initialData);
    _subscribe(hook.future);
  }

  @override
  void didUpdateHook(_FutureHook<T> oldHook) {
    if (oldHook.future == hook.future) {
      return;
    }
    _activeIdentity = _AsyncIdentity();
    _snapshot = hook.preserveState
        ? _snapshot.inState(ConnectionState.none)
        : _initialSnapshot(hook.initialData);
    _subscribe(hook.future);
  }

  @override
  AsyncSnapshot<T> build(BuildContext context) => _snapshot;

  @override
  void dispose() {
    _activeIdentity = _AsyncIdentity();
    super.dispose();
  }

  void _subscribe(Future<T>? future) {
    if (future == null) {
      _activeIdentity = null;
      return;
    }
    final identity = _AsyncIdentity();
    _activeIdentity = identity;
    _snapshot = _snapshot.inState(ConnectionState.waiting);
    void handleValue(T value) {
      if (!mounted || !identical(_activeIdentity, identity)) {
        return;
      }
      setState(() {
        _snapshot = AsyncSnapshot<T>.withData(ConnectionState.done, value);
      });
    }

    void handleError(Object error, StackTrace stackTrace) {
      if (!mounted || !identical(_activeIdentity, identity)) {
        return;
      }
      setState(() {
        _snapshot = AsyncSnapshot<T>.withError(
          ConnectionState.done,
          error,
          stackTrace,
        );
      });
    }

    unawaited(future.then<void>(handleValue, onError: handleError));
  }
}

final class _StreamHook<T> extends Hook<AsyncSnapshot<T>> {
  const _StreamHook({
    required this.stream,
    required this.initialData,
    required this.preserveState,
  });

  final Stream<T>? stream;
  final T? initialData;
  final bool preserveState;

  @override
  _StreamHookState<T> createState() => _StreamHookState<T>();
}

final class _StreamHookState<T>
    extends HookState<AsyncSnapshot<T>, _StreamHook<T>> {
  late AsyncSnapshot<T> _snapshot;
  StreamSubscription<T>? _subscription;
  _AsyncIdentity? _activeIdentity;

  @override
  void initHook() {
    _snapshot = _initialSnapshot(hook.initialData);
    _subscribe(hook.stream);
  }

  @override
  void didUpdateHook(_StreamHook<T> oldHook) {
    if (oldHook.stream == hook.stream) {
      return;
    }
    _disconnect();
    _snapshot = hook.preserveState
        ? _snapshot.inState(ConnectionState.none)
        : _initialSnapshot(hook.initialData);
    _subscribe(hook.stream);
  }

  @override
  AsyncSnapshot<T> build(BuildContext context) => _snapshot;

  @override
  void dispose() {
    try {
      _disconnect();
    } finally {
      super.dispose();
    }
  }

  void _subscribe(Stream<T>? stream) {
    if (stream == null) {
      _activeIdentity = null;
      return;
    }
    final identity = _AsyncIdentity();
    _activeIdentity = identity;
    _snapshot = _snapshot.inState(ConnectionState.waiting);
    void handleData(T value) {
      if (!mounted || !identical(_activeIdentity, identity)) {
        return;
      }
      setState(() {
        _snapshot = AsyncSnapshot<T>.withData(ConnectionState.active, value);
      });
    }

    void handleError(Object error, StackTrace stackTrace) {
      if (!mounted || !identical(_activeIdentity, identity)) {
        return;
      }
      setState(() {
        _snapshot = AsyncSnapshot<T>.withError(
          ConnectionState.active,
          error,
          stackTrace,
        );
      });
    }

    void handleDone() {
      if (!mounted || !identical(_activeIdentity, identity)) {
        return;
      }
      setState(() {
        _snapshot = _snapshot.inState(ConnectionState.done);
      });
    }

    // The retained subscription is cancelled by _disconnect and dispose.
    _subscription = stream.listen(
      handleData,
      onError: handleError,
      onDone: handleDone,
    );
  }

  void _disconnect() {
    _activeIdentity = _AsyncIdentity();
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
  }
}

AsyncSnapshot<T> _initialSnapshot<T>(T? initialData) => initialData == null
    ? AsyncSnapshot<T>.nothing()
    : AsyncSnapshot<T>.withData(ConnectionState.none, initialData);

final class _AsyncIdentity {}
