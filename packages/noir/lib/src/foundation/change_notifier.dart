import 'dart:async';

import 'package:meta/meta.dart';

import 'disposable.dart';
import 'listenable.dart';

/// Default [Listenable] implementation backed by a listener list.
class ChangeNotifier implements Listenable, Disposable {
  final List<VoidCallback> _listeners = <VoidCallback>[];
  bool _disposed = false;

  /// Whether at least one listener is registered.
  bool get hasListeners => _listeners.isNotEmpty;

  @override
  void addListener(VoidCallback listener) {
    if (_disposed) {
      throw StateError('Cannot add a listener after dispose().');
    }
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Notifies all registered listeners using a stable snapshot.
  ///
  /// Listener failures are reported with their original stack traces to the
  /// [Zone] in which this notification invocation began. A failure does not
  /// prevent later listeners that remain eligible in the snapshot from
  /// running.
  void notifyListeners() {
    if (_listeners.isEmpty) return;
    final reportingZone = Zone.current;
    final localListeners = List<VoidCallback>.from(_listeners);
    for (final listener in localListeners) {
      if (_listeners.contains(listener)) {
        try {
          listener();
        } on Object catch (error, stackTrace) {
          reportingZone.handleUncaughtError(error, stackTrace);
        }
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _listeners.clear();
  }
}

/// Rejects an already-disposed notifier before a caller mutates related
/// ownership state.
@internal
void validateChangeNotifierNotDisposed(
  ChangeNotifier notifier, {
  String name = 'ChangeNotifier',
}) {
  if (notifier._disposed) {
    throw StateError('$name has already been disposed.');
  }
}
