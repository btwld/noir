import 'package:noir/noir.dart';
import 'package:signals_core/signals_core.dart';

import 'effect_guard.dart';
import 'first_error.dart';
import 'framework.dart';

/// Creates, owns, and observes a [Signal] for the hosting widget.
///
/// The hook slot keeps one signal while [keys] stay equal, and rebuilds the
/// host after the value changes. [initialValue] and [options] are used only
/// when the signal is created; a changed key list creates a replacement.
///
/// The hook owns the signal's lifetime, so `options.autoDispose` must stay
/// false. Use [useSignalValue] to observe a source somebody else owns.
///
/// ```dart
/// final count = useSignal(0);
/// return Button(label: 'Add one', onPressed: () => count.value++);
/// ```
Signal<T> useSignal<T>(
  T initialValue, {
  List<Object?> keys = const <Object?>[],
  SignalOptions<T>? options,
}) => use(_SignalHook<T>(initialValue, keys, options));

/// Creates, owns, and observes a [Computed] for the hosting widget.
///
/// The host rebuilds when the computed result changes, so an unchanged result
/// requests no rebuild. Signals read inside [compute] are tracked by Signals
/// itself. Ordinary values the closure captures are not: list them in [keys],
/// which recreates the computed when they change.
///
/// The hook owns the computed's lifetime, so `options.autoDispose` must stay
/// false.
Computed<T> useComputed<T>(
  T Function() compute, {
  List<Object?> keys = const <Object?>[],
  ComputedOptions<T>? options,
}) => use(_ComputedHook<T>(compute, keys, options));

/// Observes a borrowed [source] and returns its current value.
///
/// The hook never disposes [source]: its owner does. Passing the same object
/// on a later build keeps the existing subscription. Passing a different one
/// invalidates the previous callback, cancels it, and observes the new source.
///
/// A source created with `autoDispose: true` keeps its upstream behavior, so
/// removing the last observer may dispose it.
T useSignalValue<T>(ReadonlySignal<T> source) =>
    use(_SignalValueHook<T>(source));

/// Runs [callback] as a reactive effect owned by this hook slot.
///
/// Signals read inside [callback] are tracked by Signals, which reruns the
/// effect with its own timing. Return a cleanup callback to release whatever
/// the run acquired. The hook cancels the effect when the host leaves the tree
/// and ignores callbacks after that.
///
/// [callback] and [options] are retained until [keys] change.
///
/// The install and the lifecycle cleanup run under the same guard as
/// `useEffect`, so neither may request a hook rebuild while it runs. That
/// guard covers every hook host in the isolate, not only this one: a cleanup
/// that writes a signal another `HookWidget` observes makes that widget's
/// rebuild request throw. Write to shared signals from an input callback, a
/// timer, or a future instead.
///
/// A failure raised by the install run propagates unchanged. Signals wraps a
/// failure raised by a later dependency-driven rerun in a
/// [SignalEffectException], whose `error` holds the original.
void useSignalEffect(
  EffectCallback callback, {
  List<Object?> keys = const <Object?>[],
  EffectOptions? options,
}) => use<Object?>(_SignalEffectHook(callback, keys, options));

/// Observes one signal and requests ordinary Noir rebuilds.
///
/// This never runs a builder, flushes a frame, or paints: it only asks the
/// host to rebuild, and Noir's scheduler coalesces repeated requests into one
/// frame. Each subscription carries a generation, so a replaced callback is
/// inert before its cancellation runs and stays inert if that cancellation
/// throws.
final class _SignalObservation<T> {
  _SignalObservation(this._requestRebuild);

  final VoidCallback _requestRebuild;
  ReadonlySignal<T>? _source;
  void Function()? _cancel;
  int _generation = 0;
  bool _retired = false;

  /// Observes [source], keeping a live subscription to the same object.
  void observe(ReadonlySignal<T> source) {
    if (_retired || (identical(_source, source) && _cancel != null)) {
      return;
    }
    final failures = FirstErrorRecorder()..attempt(_cancelCurrent);
    _source = source;
    final generation = ++_generation;
    var attaching = true;
    failures.attempt(() {
      try {
        _cancel = source.subscribe((_) {
          // Upstream notifies immediately when the subscription attaches. The
          // build that installed it already read the current value.
          if (attaching || _retired || generation != _generation) {
            return;
          }
          _requestRebuild();
        });
      } finally {
        attaching = false;
      }
    });
    // First error wins even when both the cancellation and the attach fail.
    failures.rethrowFirst();
  }

  /// Stops observing. Safe to call when nothing is subscribed.
  void cancel() => _cancelCurrent();

  /// Stops observing for good; later notifications are ignored.
  void retire() {
    _retired = true;
    _cancelCurrent();
  }

  void _cancelCurrent() {
    final cancel = _cancel;
    _cancel = null;
    _source = null;
    // Invalidate before cancelling, so a throwing cancellation cannot leave a
    // live callback behind. Defense in depth on this path: `retire()` already
    // makes the callback inert, and Noir drops a rebuild requested for an
    // inactive element. The order matters only if either of those changes.
    _generation++;
    if (cancel != null) {
      cancel();
    }
  }
}

Never _rejectAutoDispose(String hookName, String borrowedHookName) =>
    throw ArgumentError.value(
      true,
      'options.autoDispose',
      '$hookName owns the lifetime of the value it creates, so upstream '
          'auto-disposal would race that ownership. Remove autoDispose, or '
          'observe a source somebody else owns with $borrowedHookName',
    );

final class _SignalHook<T> extends Hook<Signal<T>> {
  const _SignalHook(this.initialValue, List<Object?> keys, this.options)
    : super(keys: keys);

  final T initialValue;
  final SignalOptions<T>? options;

  @override
  _SignalHookState<T> createState() => _SignalHookState<T>();
}

final class _SignalHookState<T> extends HookState<Signal<T>, _SignalHook<T>>
    with _OwnsObservedSignal<Signal<T>, _SignalHook<T>, T> {
  @override
  void initHook() {
    final options = hook.options;
    if (options != null && options.autoDispose) {
      _rejectAutoDispose('useSignal', 'useSignalValue');
    }
    own(signal<T>(hook.initialValue, options: options));
  }

  @override
  Signal<T> build(BuildContext context) => owned! as Signal<T>;
}

final class _ComputedHook<T> extends Hook<Computed<T>> {
  const _ComputedHook(this.compute, List<Object?> keys, this.options)
    : super(keys: keys);

  final T Function() compute;
  final ComputedOptions<T>? options;

  @override
  _ComputedHookState<T> createState() => _ComputedHookState<T>();
}

final class _ComputedHookState<T>
    extends HookState<Computed<T>, _ComputedHook<T>>
    with _OwnsObservedSignal<Computed<T>, _ComputedHook<T>, T> {
  @override
  void initHook() {
    final options = hook.options;
    if (options != null && options.autoDispose) {
      _rejectAutoDispose('useComputed', 'useSignalValue');
    }
    own(computed<T>(hook.compute, options: options));
  }

  @override
  Computed<T> build(BuildContext context) => owned! as Computed<T>;
}

/// Shared ownership for the hooks that create the signal they observe.
///
/// Observation detaches as soon as the slot is replaced or the host leaves the
/// tree. Disposal of the signal itself is deferred, because descendants built
/// by the previous configuration may still read it until they reconcile.
mixin _OwnsObservedSignal<R, H extends Hook<R>, T> on HookState<R, H> {
  _SignalObservation<T>? _observation;

  /// The signal this slot created, or null before [own] runs.
  ReadonlySignal<T>? owned;

  /// Takes ownership of [source] and observes it for the host.
  void own(ReadonlySignal<T> source) {
    owned = source;
    _observation = _SignalObservation<T>(markMayNeedRebuild)..observe(source);
  }

  @override
  void deactivate() => _observation?.cancel();

  @override
  void dispose() {
    final observation = _observation;
    final source = owned;
    _observation = null;
    owned = null;
    final failures = FirstErrorRecorder()..attempt(() => observation?.retire());
    if (source != null) {
      failures.attempt(() => deferDispose(source.dispose));
    }
    failures.attempt(super.dispose);
    failures.rethrowFirst();
  }
}

final class _SignalValueHook<T> extends Hook<T> {
  const _SignalValueHook(this.source);

  final ReadonlySignal<T> source;

  @override
  _SignalValueHookState<T> createState() => _SignalValueHookState<T>();
}

final class _SignalValueHookState<T> extends HookState<T, _SignalValueHook<T>> {
  late final _SignalObservation<T> _observation = _SignalObservation<T>(
    markMayNeedRebuild,
  );

  @override
  void initHook() => _observation.observe(hook.source);

  @override
  void didUpdateHook(_SignalValueHook<T> oldHook) =>
      _observation.observe(hook.source);

  @override
  T build(BuildContext context) => hook.source.value;

  @override
  void deactivate() => _observation.cancel();

  @override
  void dispose() {
    try {
      _observation.retire();
    } finally {
      super.dispose();
    }
  }
}

final class _SignalEffectHook extends Hook<Object?> {
  const _SignalEffectHook(this.callback, List<Object?> keys, this.options)
    : super(keys: keys);

  final EffectCallback callback;
  final EffectOptions? options;

  @override
  _SignalEffectHookState createState() => _SignalEffectHookState();
}

final class _SignalEffectHookState
    extends HookState<Object?, _SignalEffectHook> {
  EffectCleanup? _cancel;
  bool _retired = false;

  @override
  void initHook() {
    final callback = hook.callback;
    final options = hook.options;
    // The install runs the body once, synchronously, inside the host's build.
    // Guard it like `useEffect`, so it cannot request a hook rebuild from
    // there. Later dependency-driven reruns keep upstream timing.
    _cancel = EffectExecutionGuard.run(
      () => effect(() {
        // Defense in depth. Upstream already skips a disposed effect, and it
        // disposes one whose cleanup throws, so this only matters if that
        // ever stops holding.
        if (_retired) {
          return null;
        }
        return callback();
      }, options: options),
    );
  }

  @override
  Object? build(BuildContext context) => null;

  @override
  void deactivate() => _cancelEffect();

  @override
  void dispose() {
    // Retire first: a throwing cancellation must still leave the body inert.
    _retired = true;
    try {
      _cancelEffect();
    } finally {
      super.dispose();
    }
  }

  void _cancelEffect() {
    final cancel = _cancel;
    _cancel = null;
    if (cancel == null) {
      return;
    }
    EffectExecutionGuard.run(cancel);
  }
}
