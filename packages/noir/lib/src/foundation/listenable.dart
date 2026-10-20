/// Callback with no arguments and no return value.
typedef VoidCallback = void Function();

/// Object that can notify listeners when its observable state changes.
abstract interface class Listenable {
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
