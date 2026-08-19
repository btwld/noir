import 'package:noir/noir.dart';

import 'framework.dart';
import 'primitives.dart';

/// Compares two selected listenable values for equality.
typedef ValueEquality<T> = bool Function(T previous, T current);

/// Subscribes to [listenable] and rebuilds when it notifies listeners.
///
/// Passing `null` is supported and removes any previous subscription.
T useListenable<T extends Listenable?>(T listenable) =>
    use(_ListenableHook<T>(listenable));

/// Subscribes to [valueListenable] and returns its current value.
T useValueListenable<T>(ValueListenable<T> valueListenable) {
  useListenable<ValueListenable<T>>(valueListenable);
  return valueListenable.value;
}

/// Creates and owns a [ValueNotifier] without subscribing to its changes.
///
/// [initialValue] is used only when the notifier is created. Observe the
/// returned notifier with [useValueListenable] when its changes should rebuild
/// the current widget.
ValueNotifier<T> useValueNotifier<T>(
  T initialValue, [
  List<Object?> keys = const <Object?>[],
]) => useDisposable<ValueNotifier<T>>(
  () => ValueNotifier<T>(initialValue),
  keys,
);

/// Creates, owns, and subscribes to a [ChangeNotifier].
T useChangeNotifier<T extends ChangeNotifier>(
  T Function() create, [
  List<Object?> keys = const <Object?>[],
]) {
  final notifier = useDisposable<T>(create, keys);
  return useListenable<T>(notifier);
}

/// Subscribes to [listenable] and rebuilds only when [selector] changes.
///
/// [equals] defaults to the selected value's `==` operator.
T useListenableSelector<L extends Listenable, T>(
  L listenable,
  T Function(L listenable) selector, {
  ValueEquality<T>? equals,
}) => use(_ListenableSelectorHook<L, T>(listenable, selector, equals));

/// Registers the latest [listener] with [listenable] for this hook's lifetime.
///
/// Updating only [listener] does not remove and re-add the subscription.
void useOnListenableChange(Listenable? listenable, VoidCallback listener) =>
    use<Object?>(_OnListenableChangeHook(listenable, listener));

final class _ListenableHook<T extends Listenable?> extends Hook<T> {
  const _ListenableHook(this.listenable);

  final T listenable;

  @override
  _ListenableHookState<T> createState() => _ListenableHookState<T>();
}

final class _ListenableHookState<T extends Listenable?>
    extends HookState<T, _ListenableHook<T>> {
  @override
  void initHook() => hook.listenable?.addListener(markMayNeedRebuild);

  @override
  void didUpdateHook(_ListenableHook<T> oldHook) {
    if (identical(oldHook.listenable, hook.listenable)) {
      return;
    }
    oldHook.listenable?.removeListener(markMayNeedRebuild);
    hook.listenable?.addListener(markMayNeedRebuild);
  }

  @override
  T build(BuildContext context) => hook.listenable;

  @override
  void dispose() {
    try {
      hook.listenable?.removeListener(markMayNeedRebuild);
    } finally {
      super.dispose();
    }
  }
}

final class _ListenableSelectorHook<L extends Listenable, T> extends Hook<T> {
  const _ListenableSelectorHook(this.listenable, this.selector, this.equals);

  final L listenable;
  final T Function(L listenable) selector;
  final ValueEquality<T>? equals;

  @override
  _ListenableSelectorHookState<L, T> createState() =>
      _ListenableSelectorHookState<L, T>();
}

final class _ListenableSelectorHookState<L extends Listenable, T>
    extends HookState<T, _ListenableSelectorHook<L, T>> {
  late T _selected;

  @override
  void initHook() {
    _selected = hook.selector(hook.listenable);
    hook.listenable.addListener(_handleChange);
  }

  @override
  void didUpdateHook(_ListenableSelectorHook<L, T> oldHook) {
    if (!identical(oldHook.listenable, hook.listenable)) {
      oldHook.listenable.removeListener(_handleChange);
      hook.listenable.addListener(_handleChange);
    }
    _selected = hook.selector(hook.listenable);
  }

  @override
  T build(BuildContext context) => _selected;

  @override
  void dispose() {
    try {
      hook.listenable.removeListener(_handleChange);
    } finally {
      super.dispose();
    }
  }

  void _handleChange() {
    final next = hook.selector(hook.listenable);
    final equals = hook.equals ?? _defaultEquals<T>;
    if (equals(_selected, next)) {
      return;
    }
    setState(() {
      _selected = next;
    });
  }

  static bool _defaultEquals<T>(T previous, T current) => previous == current;
}

final class _OnListenableChangeHook extends Hook<Object?> {
  const _OnListenableChangeHook(this.listenable, this.listener);

  final Listenable? listenable;
  final VoidCallback listener;

  @override
  _OnListenableChangeHookState createState() => _OnListenableChangeHookState();
}

final class _OnListenableChangeHookState
    extends HookState<Object?, _OnListenableChangeHook> {
  @override
  void initHook() => hook.listenable?.addListener(_handleChange);

  @override
  void didUpdateHook(_OnListenableChangeHook oldHook) {
    if (identical(oldHook.listenable, hook.listenable)) {
      return;
    }
    oldHook.listenable?.removeListener(_handleChange);
    hook.listenable?.addListener(_handleChange);
  }

  @override
  Object? build(BuildContext context) => null;

  @override
  void dispose() {
    try {
      hook.listenable?.removeListener(_handleChange);
    } finally {
      super.dispose();
    }
  }

  void _handleChange() => hook.listener();
}
