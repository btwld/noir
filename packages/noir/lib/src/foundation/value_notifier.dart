import 'change_notifier.dart';
import 'listenable.dart';

/// A [ChangeNotifier] that publishes one value.
class ValueNotifier<T> extends ChangeNotifier implements ValueListenable<T> {
  /// Creates a [ValueNotifier] with an initial [value].
  ValueNotifier(this._value);

  T _value;

  @override
  T get value => _value;

  /// Update [value] and notify listeners when equality says it changed.
  set value(T value) {
    if (_value == value) return;
    _value = value;
    notifyListeners();
  }
}
