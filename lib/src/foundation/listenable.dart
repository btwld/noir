/// Callback with no arguments and no return value.
typedef VoidCallback = void Function();

/// Object that can notify listeners when its observable state changes.
abstract interface class Listenable {
  /// Creates a listenable that forwards notifications from [listenables].
  ///
  /// Flutter-parity member; kept for API parity — see Flutter's
  /// `Listenable.merge`.
  factory Listenable.merge(Iterable<Listenable?> listenables) =
      _MergingListenable;

  /// Register [listener] for future notifications.
  void addListener(VoidCallback listener);

  /// Remove one registration of [listener].
  void removeListener(VoidCallback listener);
}

/// A [Listenable] that exposes a current value.
abstract interface class ValueListenable<T> implements Listenable {
  /// Current value.
  T get value;
}

class _MergingListenable implements Listenable {
  _MergingListenable(Iterable<Listenable?> listenables)
    : _listenables = listenables.whereType<Listenable>().toList(
        growable: false,
      );

  final List<Listenable> _listenables;

  @override
  void addListener(VoidCallback listener) {
    for (final listenable in _listenables) {
      listenable.addListener(listener);
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    for (final listenable in _listenables) {
      listenable.removeListener(listener);
    }
  }
}
