import 'dart:async';

import 'package:meta/meta.dart';

/// One elapsed-time budget shared by every response and every pause of a
/// client-side wait.
///
/// Expiry ends the waiting, not the request: [Future.timeout] stops listening
/// without cancelling anything, so an abandoned response is ignored rather
/// than revoked. The budget is also asynchronous, and cannot preempt code
/// that blocks the client's event loop. Internal to the driver client.
final class PollDeadline {
  /// Starts spending [budget] now. [elapsed] replaces the stopwatch in tests.
  PollDeadline(this.budget, {@visibleForTesting Duration Function()? elapsed})
    : _elapsed = elapsed ?? _startStopwatch();

  /// The whole budget this wait started with.
  final Duration budget;

  final Duration Function() _elapsed;

  static Duration Function() _startStopwatch() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  /// What is left of [budget], never negative.
  Duration get remaining {
    final left = budget - _elapsed();
    return left.isNegative ? Duration.zero : left;
  }

  /// Whether [budget] is spent.
  bool get isExpired => remaining == Duration.zero;

  /// Awaits [response] for at most [remaining].
  ///
  /// [onExpired] supplies the outcome, or throws it, when the budget runs out
  /// first; a response that lands afterwards is dropped. An error from
  /// [response] propagates unchanged.
  Future<T> bound<T>(
    Future<T> response, {
    required FutureOr<T> Function() onExpired,
  }) =>
      // `timeout` checks `onTimeout` against the response's runtime type, and
      // an `async` closure that only throws is a `Future<Never>`.
      Future<T>.value(response).timeout(remaining, onTimeout: onExpired);

  /// Pauses for [interval], or for [remaining] when that is shorter.
  Future<void> pause(
    Duration interval, {
    required Future<void> Function(Duration duration) delay,
  }) {
    final left = remaining;
    return delay(left < interval ? left : interval);
  }
}

/// The default pause between two probes of a client-side wait.
Future<void> pollDelay(Duration duration) => Future<void>.delayed(duration);

/// Polls [fetch] until [resolve] accepts a snapshot, and returns its result.
///
/// [timeout] is one budget across every response and every pause. The first
/// probe always goes out, so a zero [timeout] still accepts a response that
/// is already available; after that a probe starts only while budget is left.
/// A response still pending when the budget runs out is abandoned, never
/// accepted late. [onTimeout] builds the failure from the last snapshot that
/// did arrive, or null when none did. Errors from [fetch] and [resolve]
/// propagate unchanged. Internal to the driver client.
Future<R> pollSnapshots<S extends Object, R extends Object>({
  required Future<S> Function() fetch,
  required R? Function(S snapshot) resolve,
  required StateError Function(S? lastSnapshot) onTimeout,
  required Duration timeout,
  required Duration pollInterval,
}) async {
  final deadline = PollDeadline(timeout);
  S? last;
  while (true) {
    final snapshot = await deadline.bound(
      fetch(),
      onExpired: () => throw onTimeout(last),
    );
    final result = resolve(snapshot);
    if (result != null) {
      return result;
    }
    last = snapshot;
    if (!deadline.isExpired) {
      await deadline.pause(pollInterval, delay: pollDelay);
    }
    if (deadline.isExpired) {
      throw onTimeout(last);
    }
  }
}
