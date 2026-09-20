import 'package:muse/muse.dart';
import 'package:noir/noir.dart';

/// Adapts a borrowed Noir [ValueListenable] to Muse.
final class MuseValueListenable<T> implements MuseListenable<T> {
  /// Adapts [source] without taking ownership of it.
  MuseValueListenable(ValueListenable<T> source) : _source = source;

  ValueListenable<T>? _source;
  final Set<VoidCallback> _listeners = <VoidCallback>{};

  ValueListenable<T> get _live =>
      _source ??
      (throw StateError('A disposed MuseValueListenable has no source.'));

  @override
  T get value => _live.value;

  @override
  void addListener(VoidCallback listener) {
    if (_listeners.add(listener)) _live.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_listeners.remove(listener)) _source?.removeListener(listener);
  }

  /// Detaches forwarded listeners without disposing the borrowed source.
  void dispose() {
    final source = _source;
    if (source != null) {
      for (final listener in _listeners) {
        source.removeListener(listener);
      }
    }
    _listeners.clear();
    _source = null;
  }
}

/// Adapts a borrowed Noir [Listenable], deriving its current value with
/// [select].
final class MuseNotifierListenable<N extends Listenable, T>
    implements MuseListenable<T> {
  /// Adapts [notifier] and derives a current value with [select].
  MuseNotifierListenable(N notifier, T Function(N notifier) select)
    : _notifier = notifier,
      _select = select;

  N? _notifier;
  final T Function(N notifier) _select;
  final Set<VoidCallback> _listeners = <VoidCallback>{};

  N get _live =>
      _notifier ??
      (throw StateError('A disposed MuseNotifierListenable has no notifier.'));

  @override
  T get value => _select(_live);

  @override
  void addListener(VoidCallback listener) {
    if (_listeners.add(listener)) _live.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_listeners.remove(listener)) _notifier?.removeListener(listener);
  }

  /// Detaches forwarded listeners without disposing the borrowed notifier.
  void dispose() {
    final notifier = _notifier;
    if (notifier != null) {
      for (final listener in _listeners) {
        notifier.removeListener(listener);
      }
    }
    _listeners.clear();
    _notifier = null;
  }
}
