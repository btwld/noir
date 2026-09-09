# Hooks reference

`package:noir_signals/noir_signals.dart` provides reusable widget lifecycle
hooks for Noir. They live in the optional companion package `noir_signals`,
not in `noir`. The companion's production code uses no private Element,
low-level renderer, or FFI API.

This document is the reference. To learn hooks by building an app, start with
[Build a task list](getting-started.md).

## Install and import

Both packages are unpublished candidates. Resolve them from a Noir repository
checkout; the [package overview](../README.md) has the setup. After
publication, an application will declare:

```yaml
dependencies:
  noir: ^0.0.1-alpha.5
  noir_signals: ^0.0.1-alpha.0
```

```dart
import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
```

## Host hooks

Extend `SignalWidget` and call hooks at the top of `build`. Handle input in
callbacks such as `onPressed`; effects own external work and its cleanup. The
runnable [counter](../example/counter.dart) shows `useState` on its own.

Use `SignalBuilder` when an inline builder needs hooks:

```dart
final widget = SignalBuilder(
  builder: (context) {
    final enabled = useState(false);
    return Text(enabled.value ? 'enabled' : 'disabled');
  },
);
```

## Noir model

`SignalWidget` is a normal Noir `StatefulWidget`. Rebuilds use Noir's `State` and
`BuildOwner`, animations use Noir's ticker scheduler, and effects run
synchronously during the hook widget build.

A normal `StatefulWidget` can keep a `SignalBuilder` at a stable position in its
`build` method. That child owns the hook slots and their resources independently
of the parent’s `State` object.

Noir hot reload is forwarded to retained class hooks through
`HookState.reassemble`. The immediately following build may replace a
structurally changed hook slot and its tail. An ordinary build reports a hook
runtime-type mismatch instead of silently accepting reordered or conditional
hook calls.

## Rules

Stateful hooks use call order as identity. `useContext` and
`useTickerProvider` are build-only lookups and do not consume a hook slot.

- Call stateful hooks unconditionally and in the same order on every build.
- Do not call hooks from event, effect, cleanup, or non-build lifecycle
  callbacks.
- Compose custom hooks in top-level functions whose names start with `use`.
- A key change recreates only that hook slot.

Key lists are snapshotted. Later mutation of a caller-owned list cannot change
stored hook identity. During keyed replacement, later slots update before the
old state is disposed so listeners can detach safely.

## Included hooks

Core lifecycle:

- `useState`, `useEffect`, `useMemoized`, `useCallback`, `useRef`
- `usePrevious`, `useValueChanged`, `useReducer`
- `useDisposable`, `useOnDispose`, `useIsMounted`, `useContext`

Observable values:

- `useListenable`, `useValueListenable`, `useListenableSelector`
- `useValueNotifier`, `useChangeNotifier`, `useOnListenableChange`

`useState` owns and observes a `ValueNotifier`. `useValueNotifier` only owns
the notifier; pair it with `useValueListenable` when the widget should rebuild.

Asynchronous values:

- `useFuture` and `useStream`, returning `AsyncSnapshot`
- stale callbacks are ignored after replacement or disposal
- replaced and disposed stream subscriptions are canceled

Create futures and streams outside the build or retain them with
`useMemoized`. A new asynchronous object on every build restarts observation.

Noir integrations:

- `useTickerProvider`, `useAnimationController`, `useAnimation`,
  `useAnimationStatus`
- `useTextEditingController`, `useFocusNode`, `useScrollController`,
  `useViewportController`

## Effects and cleanup

`useEffect` is synchronous. Without keys, cleanup and the effect run on every
build, with cleanup first. With keys, a changed effect is installed during the
replacement build and the old cleanup runs after later hook slots have updated,
so those slots can detach from an effect-owned resource safely. Cleanup also
runs when the hook is removed or its widget is disposed.

Effect callbacks and cleanup must not synchronously request a hook rebuild.
That includes updating `useState` or another observed value from inside the
callback. Noir reports a targeted `StateError` immediately instead of allowing
the build queue to drain repeated effect-driven rebuilds. Assigning an
`ObjectRef` remains valid because it does not rebuild. State changes made later
from timers, futures, streams, or input callbacks are also valid because the
effect has returned by then.

The runtime guard is deliberately owned by this package. It covers
rebuilds requested through `HookState`, but does not modify core `State.setState`
or `BuildOwner`. An effect must therefore also avoid synchronously invoking an
ordinary state callback; that path does not receive the hook-specific error and
can still schedule work during the current build drain.

The guard is isolate-wide, not per host. While any synchronous effect callback
or cleanup runs, a rebuild requested through `HookState` is rejected for every
hook widget, including one that is unrelated to the effect. That is deliberate:
a cleanup that writes state a *different* host observes can drive the same
build-drain loop the guard exists to stop. Route cross-widget writes through an
input callback, a timer, or a future, after the effect has returned.

`useState` and other `ValueNotifier`-based sources update their notifier value
before notifying listeners. When an observed notifier changes during an effect,
the notifier keeps that value and `ChangeNotifier` reports the rejected hook
rebuild to the current `Zone`; the guard prevents scheduling but does not roll
back the notifier mutation.

`useValueChanged` follows the established hooks contract: its callback receives
the previous input value and the callback's previous result. The first build
returns `null` without invoking the callback.

Owned hooks dispose in reverse call order. Cleanup continues after a failure,
then the first error is rethrown.

## Custom hooks

Prefer top-level functions that compose built-in hooks. Return values and
callbacks that keep the owning notifier private when callers do not need it:

```dart
typedef CounterState = ({int value, VoidCallback increment});

CounterState useCounter([int initialValue = 0]) {
  final counter = useState(initialValue);
  return (value: counter.value, increment: () => counter.value++);
}
```

For lifecycle behavior that composition cannot express, extend `Hook` and
`HookState`. A class hook can initialize, update, reassemble, rebuild, access
the host context and ticker provider, and dispose resources.

`HookState.deferDispose` releases a resource this slot retires after the host
successfully updates its descendants and the removed descendants finish
unmounting. Use it when the widgets built by the previous configuration may
still read the retired resource. Detach this hook's own observation at once and
defer only the disposal.

## Signals

The same package adds `useSignal`, `useComputed`, `useSignalValue`,
`useSignalEffect`, and `SignalValueBuilder`. They follow the hook rules above
and connect the `signals_core` engine to Noir rebuilds. Read
[`signals.md`](signals.md) for their ownership and observation contract.
