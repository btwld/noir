import 'package:noir/noir.dart';

import 'framework.dart';

/// Releases resources created by an effect.
typedef Dispose = void Function();

/// Runs a synchronous side effect and optionally returns its cleanup callback.
typedef Effect = Dispose? Function();

/// Reduces [state] and [action] into a new state value.
typedef Reducer<S, A> = S Function(S state, A action);

/// Holds one mutable value without requesting widget rebuilds.
final class ObjectRef<T> {
  /// Creates a reference initialized to [value].
  ObjectRef(this.value);

  /// The current referenced value.
  T value;
}

/// Read-only reducer state returned by [useReducer].
abstract interface class Store<S, A> {
  /// The current reducer state.
  S get value;

  /// Applies [action] to the current state.
  void dispatch(A action);
}

/// Creates a [ValueNotifier] that rebuilds its widget when its value changes.
///
/// [initialValue] is used only when the hook state is first created.
ValueNotifier<T> useState<T>(T initialValue) =>
    use(_StateHook<T>(initialValue));

/// Creates and retains a value until [keys] change.
T useMemoized<T>(
  T Function() valueBuilder, [
  List<Object?> keys = const <Object?>[],
]) => use(_MemoizedHook<T>(valueBuilder, keys));

/// Retains [callback] until [keys] change.
T useCallback<T extends Function>(
  T callback, [
  List<Object?> keys = const <Object?>[],
]) => useMemoized<T>(() => callback, keys);

/// Creates a mutable reference that does not rebuild its widget when changed.
ObjectRef<T> useRef<T>(T initialValue) =>
    useMemoized<ObjectRef<T>>(() => ObjectRef<T>(initialValue));

/// Runs [effect] synchronously during build and manages its cleanup.
///
/// With no [keys], the previous cleanup and the effect run on every build.
/// With keys, they run once and then whenever any key changes. Cleanup also
/// runs when the hook is removed or its widget is disposed.
void useEffect(Effect effect, [List<Object?>? keys]) =>
    use<Object?>(_EffectHook(effect, keys));

/// Creates and owns a [Disposable] value until [keys] change.
T useDisposable<T extends Disposable>(
  T Function() create, [
  List<Object?> keys = const <Object?>[],
]) => use(_DisposableHook<T>(create, keys));

/// Returns the value supplied on the previous build, or `null` initially.
T? usePrevious<T>(T value) => use(_PreviousHook<T>(value));

/// Invokes [valueChange] when [value] changes after the first build.
///
/// The most recent callback result is retained until the next change.
R? useValueChanged<T, R>(
  T value,
  R Function(T previous, T current) valueChange,
) => use(_ValueChangedHook<T, R>(value, valueChange));

/// Creates a reducer [Store] that rebuilds its widget after each state change.
///
/// [initialState] is used only when the hook state is created. The latest
/// [reducer] is used for later dispatches.
Store<S, A> useReducer<S, A>(
  Reducer<S, A> reducer,
  S initialState, [
  List<Object?> keys = const <Object?>[],
]) => use(_ReducerHook<S, A>(reducer, initialState, keys));

/// Registers [callback] to run once when this hook is disposed.
///
/// The latest callback supplied to the retained hook slot is used.
void useOnDispose(Dispose callback) => use<Object?>(_OnDisposeHook(callback));

/// Returns a stable callback that reports whether its hook is still mounted.
bool Function() useIsMounted() => use(const _IsMountedHook());

final class _StateHook<T> extends Hook<ValueNotifier<T>> {
  const _StateHook(this.initialValue);

  final T initialValue;

  @override
  _StateHookState<T> createState() => _StateHookState<T>();
}

final class _StateHookState<T>
    extends HookState<ValueNotifier<T>, _StateHook<T>> {
  late final ValueNotifier<T> _notifier;

  @override
  void initHook() {
    _notifier = ValueNotifier<T>(hook.initialValue)
      ..addListener(markMayNeedRebuild);
  }

  @override
  ValueNotifier<T> build(BuildContext context) => _notifier;

  @override
  void dispose() {
    try {
      _notifier
        ..removeListener(markMayNeedRebuild)
        ..dispose();
    } finally {
      super.dispose();
    }
  }
}

final class _MemoizedHook<T> extends Hook<T> {
  const _MemoizedHook(this.valueBuilder, List<Object?> keys)
    : super(keys: keys);

  final T Function() valueBuilder;

  @override
  _MemoizedHookState<T> createState() => _MemoizedHookState<T>();
}

final class _MemoizedHookState<T> extends HookState<T, _MemoizedHook<T>> {
  late final T _value;

  @override
  void initHook() => _value = hook.valueBuilder();

  @override
  T build(BuildContext context) => _value;
}

final class _EffectHook extends Hook<Object?> {
  _EffectHook(this.effect, List<Object?>? keys)
    : dependencyKeys = keys == null ? null : List<Object?>.unmodifiable(keys);

  final Effect effect;
  final List<Object?>? dependencyKeys;

  @override
  _EffectHookState createState() => _EffectHookState();
}

final class _EffectHookState extends HookState<Object?, _EffectHook> {
  Dispose? _cleanup;

  @override
  void initHook() => _runEffect();

  @override
  void didUpdateHook(_EffectHook oldHook) {
    final keys = hook.dependencyKeys;
    if (keys == null || !_effectKeysEqual(oldHook.dependencyKeys, keys)) {
      _runEffect();
    }
  }

  @override
  Object? build(BuildContext context) => null;

  @override
  void dispose() {
    try {
      final cleanup = _cleanup;
      _cleanup = null;
      cleanup?.call();
    } finally {
      super.dispose();
    }
  }

  void _runEffect() {
    Object? firstError;
    StackTrace? firstStackTrace;

    final cleanup = _cleanup;
    _cleanup = null;
    try {
      cleanup?.call();
    } on Object catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }

    try {
      _cleanup = hook.effect();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}

final class _DisposableHook<T extends Disposable> extends Hook<T> {
  const _DisposableHook(this.create, List<Object?> keys) : super(keys: keys);

  final T Function() create;

  @override
  _DisposableHookState<T> createState() => _DisposableHookState<T>();
}

final class _DisposableHookState<T extends Disposable>
    extends HookState<T, _DisposableHook<T>> {
  late final T _value;

  @override
  void initHook() => _value = hook.create();

  @override
  T build(BuildContext context) => _value;

  @override
  void dispose() {
    try {
      _value.dispose();
    } finally {
      super.dispose();
    }
  }
}

final class _PreviousHook<T> extends Hook<T?> {
  const _PreviousHook(this.value);

  final T value;

  @override
  _PreviousHookState<T> createState() => _PreviousHookState<T>();
}

final class _PreviousHookState<T> extends HookState<T?, _PreviousHook<T>> {
  T? _previous;
  bool _hasPrevious = false;

  @override
  T? build(BuildContext context) {
    final result = _hasPrevious ? _previous : null;
    _previous = hook.value;
    _hasPrevious = true;
    return result;
  }
}

final class _ValueChangedHook<T, R> extends Hook<R?> {
  const _ValueChangedHook(this.value, this.valueChange);

  final T value;
  final R Function(T previous, T current) valueChange;

  @override
  _ValueChangedHookState<T, R> createState() => _ValueChangedHookState<T, R>();
}

final class _ValueChangedHookState<T, R>
    extends HookState<R?, _ValueChangedHook<T, R>> {
  late T _previous;
  bool _initialized = false;
  R? _result;

  @override
  R? build(BuildContext context) {
    final current = hook.value;
    if (!_initialized) {
      _previous = current;
      _initialized = true;
      return _result;
    }
    if (_previous != current) {
      final previous = _previous;
      final result = hook.valueChange(previous, current);
      _previous = current;
      _result = result;
    }
    return _result;
  }
}

final class _ReducerHook<S, A> extends Hook<Store<S, A>> {
  const _ReducerHook(this.reducer, this.initialState, List<Object?> keys)
    : super(keys: keys);

  final Reducer<S, A> reducer;
  final S initialState;

  @override
  _ReducerHookState<S, A> createState() => _ReducerHookState<S, A>();
}

final class _ReducerHookState<S, A>
    extends HookState<Store<S, A>, _ReducerHook<S, A>>
    implements Store<S, A> {
  late S _value;

  @override
  void initHook() => _value = hook.initialState;

  @override
  S get value => _value;

  @override
  void dispatch(A action) {
    final next = hook.reducer(_value, action);
    if (_value == next) {
      return;
    }
    setState(() {
      _value = next;
    });
  }

  @override
  Store<S, A> build(BuildContext context) => this;
}

final class _OnDisposeHook extends Hook<Object?> {
  const _OnDisposeHook(this.callback);

  final Dispose callback;

  @override
  _OnDisposeHookState createState() => _OnDisposeHookState();
}

final class _OnDisposeHookState extends HookState<Object?, _OnDisposeHook> {
  Dispose? _callback;

  @override
  void initHook() => _callback = hook.callback;

  @override
  void didUpdateHook(_OnDisposeHook _) => _callback = hook.callback;

  @override
  Object? build(BuildContext context) => null;

  @override
  void dispose() {
    try {
      final callback = _callback;
      _callback = null;
      callback?.call();
    } finally {
      super.dispose();
    }
  }
}

final class _IsMountedHook extends Hook<bool Function()> {
  const _IsMountedHook();

  @override
  _IsMountedHookState createState() => _IsMountedHookState();
}

final class _IsMountedHookState
    extends HookState<bool Function(), _IsMountedHook> {
  late final bool Function() _callback;

  @override
  void initHook() => _callback = () => mounted;

  @override
  bool Function() build(BuildContext context) => _callback;
}

bool _effectKeysEqual(List<Object?>? left, List<Object?>? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    final leftValue = left[index];
    final rightValue = right[index];
    if (leftValue is num && rightValue is num) {
      if (leftValue.isNaN && rightValue.isNaN) {
        continue;
      }
      if (leftValue == 0 && rightValue == 0) {
        if (leftValue.isNegative != rightValue.isNegative) {
          return false;
        }
        continue;
      }
    }
    if (leftValue != rightValue) {
      return false;
    }
  }
  return true;
}
