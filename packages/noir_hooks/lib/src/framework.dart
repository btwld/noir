import 'package:meta/meta.dart';
import 'package:noir/noir.dart';

/// Builds a widget from a [BuildContext] while hooks are active.
typedef HookWidgetBuilder = Widget Function(BuildContext context);

/// Immutable configuration for one reusable lifecycle hook.
///
/// A hook is identified by its call position, runtime type, and optional
/// [keys]. Applications normally expose hooks through top-level functions
/// whose names start with `use` instead of constructing hook objects directly.
@immutable
abstract class Hook<R> {
  /// Creates a hook whose state is retained while [keys] remain equal.
  const Hook({this.keys});

  /// Values that control whether this hook's state is retained.
  ///
  /// The hosting widget snapshots these values on every build. Mutating a list
  /// after passing it here therefore cannot retroactively change stored hook
  /// identity.
  final List<Object?>? keys;

  /// Creates the mutable state owned by this hook slot.
  @protected
  HookState<R, Hook<R>> createState();
}

/// Mutable lifecycle state for a [Hook].
///
/// This API intentionally mirrors the useful parts of Noir's [State] API while
/// remaining independent from Noir's private element implementations.
abstract class HookState<R, H extends Hook<R>> {
  H? _hook;
  _HookWidgetState? _owner;
  bool _mounted = false;
  bool _disposing = false;
  List<Object?>? _keySnapshot;

  /// The latest immutable hook configuration for this slot.
  @protected
  H get hook {
    _checkReadable();
    return _hook!;
  }

  /// The build context of the hosting [HookWidget].
  ///
  /// The context remains readable during [dispose], matching Noir's [State]
  /// lifecycle, and becomes unavailable after disposal completes.
  @protected
  BuildContext get context {
    _checkReadable();
    return _owner!.context;
  }

  /// Whether this hook state is attached to a live [HookWidget].
  bool get mounted => _mounted;

  /// A ticker provider shared by all hooks in the hosting widget.
  @protected
  TickerProvider get tickerProvider {
    _checkReadable();
    return _owner!;
  }

  /// Called once after this hook state is attached.
  @protected
  void initHook() {}

  /// Called when a retained hook slot receives a new configuration.
  @protected
  void didUpdateHook(covariant H oldHook) {}

  /// Returns the current value exposed by this hook.
  @protected
  R build(BuildContext context);

  /// Called when the hosting widget is removed from the active tree.
  @protected
  void deactivate() {}

  /// Releases resources owned by this hook state.
  ///
  /// Overrides should release their resources and then call `super.dispose()`.
  @mustCallSuper
  @protected
  void dispose() {}

  /// Applies [fn] and schedules the hosting widget to rebuild.
  ///
  /// This throws after disposal starts. The callback is not invoked in that
  /// case.
  @protected
  void setState(VoidCallback fn) {
    if (!_mounted || _disposing) {
      throw StateError(
        'HookState.setState() called after dispose(): $runtimeType is no '
        'longer active. Cancel timers, subscriptions, and callbacks in '
        'dispose().',
      );
    }
    _owner!.setState(fn);
  }

  /// Schedules a rebuild without changing local state.
  @protected
  void markMayNeedRebuild() => setState(() {});

  Type get _hookType => _hook!.runtimeType;

  List<Object?>? get _storedKeys => _keySnapshot;

  dynamic _buildValue(BuildContext context) => build(context);

  void _attach(
    _HookWidgetState owner,
    Hook<dynamic> hook,
    List<Object?>? keySnapshot,
  ) {
    _owner = owner;
    _hook = hook as H;
    _keySnapshot = keySnapshot;
    _mounted = true;
  }

  void _initialize() => initHook();

  void _updateHook(Hook<dynamic> nextHook, List<Object?>? keySnapshot) {
    final oldHook = _hook!;
    _hook = nextHook as H;
    _keySnapshot = keySnapshot;
    didUpdateHook(oldHook);
  }

  void _deactivateEntry() {
    if (_mounted && !_disposing) {
      deactivate();
    }
  }

  void _unmount() {
    if (!_mounted || _disposing) {
      return;
    }
    _disposing = true;
    try {
      dispose();
    } finally {
      _mounted = false;
      _disposing = false;
      _owner = null;
      _hook = null;
      _keySnapshot = null;
    }
  }

  void _checkReadable() {
    if (!_mounted) {
      throw StateError('$runtimeType is no longer mounted.');
    }
  }
}

/// A Noir widget whose [build] method can call hooks.
///
/// Hook calls must be unconditional and must occur in the same order on every
/// build. Custom hook functions should start with `use`.
abstract class HookWidget extends StatefulWidget {
  /// Creates a hook-enabled widget with an optional [key].
  const HookWidget({super.key});

  /// Describes this widget and may call [use] and built-in hooks.
  Widget build(BuildContext context);

  @override
  @nonVirtual
  State<HookWidget> createState() => _HookWidgetState();
}

/// A hook-enabled widget defined by a callback.
final class HookBuilder extends HookWidget {
  /// Creates a hook widget that invokes [builder] for each build.
  const HookBuilder({required this.builder, super.key});

  /// Callback that describes the widget subtree.
  final HookWidgetBuilder builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

/// Uses [hook] in the current [HookWidget] build and returns its value.
///
/// This throws when called outside a hook-enabled build or from a lifecycle
/// callback other than [HookState.build]. Class-based hook builds may compose
/// later hooks under the same unconditional call-order rule.
R use<R>(Hook<R> hook) {
  final owner = _currentHookState;
  if (owner == null || !owner.isBuilding) {
    throw StateError(
      'Hooks can only be used while a HookWidget or HookBuilder is building.',
    );
  }
  return owner.useHook(hook);
}

/// Returns the [BuildContext] of the current [HookWidget] build.
///
/// Unlike stateful hooks, this lookup does not consume a hook slot. It is
/// valid only in the widget build body or [HookState.build].
BuildContext useContext() {
  final owner = _currentHookState;
  if (owner == null || !owner.isBuilding) {
    throw StateError(
      'useContext() can only be called while a HookWidget or HookBuilder is '
      'building.',
    );
  }
  if (owner.isResolvingHook) {
    throw StateError(
      'useContext() cannot be called from hook lifecycle or effect '
      'callbacks. Use HookState.context there instead.',
    );
  }
  return owner.context;
}

_HookWidgetState? _currentHookState;

final class _HookWidgetState extends State<HookWidget>
    with TickerProviderStateMixin<HookWidget> {
  final List<HookState<dynamic, dynamic>> _hooks =
      <HookState<dynamic, dynamic>>[];
  int _hookIndex = 0;
  bool _isBuilding = false;
  bool _isResolvingHook = false;

  bool get isBuilding => _isBuilding;

  bool get isResolvingHook => _isResolvingHook;

  R useHook<R>(Hook<R> nextHook) {
    if (_isResolvingHook) {
      throw StateError(
        'A hook cannot call another hook from initHook, didUpdateHook, '
        'deactivate, dispose, or an effect callback. Compose hooks in a '
        'top-level use... function or from HookState.build instead.',
      );
    }

    final index = _hookIndex;
    _hookIndex++;

    try {
      final nextKeys = _snapshotKeys(nextHook.keys);
      late final HookState<dynamic, dynamic> state;
      _isResolvingHook = true;
      try {
        if (index >= _hooks.length) {
          state = _createHookState(nextHook, nextKeys);
          _hooks.add(state);
        } else {
          final current = _hooks[index];
          if (current._hookType != nextHook.runtimeType) {
            _disposeFrom(index);
            state = _createHookState(nextHook, nextKeys);
            _hooks.add(state);
          } else if (!_keysEqual(current._storedKeys, nextKeys)) {
            _hooks.removeAt(index);
            current._unmount();
            state = _createHookState(nextHook, nextKeys);
            _hooks.insert(index, state);
          } else {
            current._updateHook(nextHook, nextKeys);
            state = current;
          }
        }
      } finally {
        _isResolvingHook = false;
      }
      return state._buildValue(context) as R;
    } on Object {
      _hookIndex = index;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isBuilding) {
      throw StateError('HookWidget build cannot be re-entered.');
    }

    final previous = _currentHookState;
    _currentHookState = this;
    _hookIndex = 0;
    _isBuilding = true;

    Widget? result;
    final failures = _FirstErrorRecorder();
    try {
      failures.attempt(() {
        result = widget.build(context);
      });
      failures.attempt(() {
        _disposeFrom(_hookIndex);
      });
    } finally {
      _currentHookState = previous;
      _isBuilding = false;
      _isResolvingHook = false;
    }

    failures.rethrowFirst();
    return result!;
  }

  @override
  void deactivate() {
    final failures = _FirstErrorRecorder();
    for (final hook in _hooks.reversed) {
      failures.attempt(hook._deactivateEntry);
    }
    failures.attempt(() {
      super.deactivate();
    });
    failures.rethrowFirst();
  }

  @override
  void dispose() {
    final failures = _FirstErrorRecorder();
    final hooks = List<HookState<dynamic, dynamic>>.of(_hooks);
    _hooks.clear();
    for (final hook in hooks.reversed) {
      failures.attempt(hook._unmount);
    }
    failures.attempt(() {
      super.dispose();
    });
    failures.rethrowFirst();
  }

  HookState<dynamic, dynamic> _createHookState<R>(
    Hook<R> hook,
    List<Object?>? keySnapshot,
  ) {
    final state = hook.createState();
    state._attach(this, hook, keySnapshot);
    try {
      state._initialize();
      return state;
    } on Object catch (error, stackTrace) {
      try {
        state._unmount();
      } on Object {
        // Preserve the initialization error. Cleanup was still attempted.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _disposeFrom(int index) {
    if (index >= _hooks.length) {
      return;
    }
    final removed = _hooks.sublist(index);
    _hooks.removeRange(index, _hooks.length);
    final failures = _FirstErrorRecorder();
    final wasResolvingHook = _isResolvingHook;
    _isResolvingHook = true;
    try {
      for (final hook in removed.reversed) {
        failures.attempt(hook._unmount);
      }
    } finally {
      _isResolvingHook = wasResolvingHook;
    }
    failures.rethrowFirst();
  }
}

List<Object?>? _snapshotKeys(List<Object?>? keys) =>
    keys == null ? null : List<Object?>.unmodifiable(keys);

bool _keysEqual(List<Object?>? left, List<Object?>? right) {
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

final class _FirstErrorRecorder {
  Object? _error;
  StackTrace? _stackTrace;

  void attempt(void Function() action) {
    try {
      action();
    } on Object catch (error, stackTrace) {
      _error ??= error;
      _stackTrace ??= stackTrace;
    }
  }

  void rethrowFirst() {
    final error = _error;
    if (error != null) {
      Error.throwWithStackTrace(error, _stackTrace!);
    }
  }
}
