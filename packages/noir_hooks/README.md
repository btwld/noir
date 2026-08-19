# noir_hooks

`noir_hooks` adds reusable widget lifecycle hooks to Noir. It is a companion
package for `package:noir/noir.dart`; production code uses no private Element,
low-level renderer, or FFI API.

## Install

```yaml
dependencies:
  noir: ^0.0.1-alpha.1
  noir_hooks: ^0.0.1-alpha.0
```

## Quick start

```dart
import 'dart:async';

import 'package:noir/noir.dart';
import 'package:noir_hooks/noir_hooks.dart';

void main() => runTuiApp(const CounterApp());

class CounterApp extends HookWidget {
  const CounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useState(0);

    useEffect(() {
      final timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => count.value++,
      );
      return timer.cancel;
    }, const <Object?>[]);

    return Text('Ticks: ${count.value}');
  }
}
```

Use `HookBuilder` when an inline builder needs hooks:

```dart
final widget = HookBuilder(
  builder: (context) {
    final enabled = useState(false);
    return Text(enabled.value ? 'enabled' : 'disabled');
  },
);
```

## Noir model

`HookWidget` is a normal Noir `StatefulWidget`. Rebuilds use Noir's `State` and
`BuildOwner`, animations use Noir's ticker scheduler, and effects run
synchronously during the hook widget build.

A normal `StatefulWidget` can keep a `HookBuilder` at a stable position in its
`build` method. The package does not provide `StatefulHookWidget` because that
would require framework-owned Element behavior that Noir does not expose as an
application API.

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
build. With keys, they run when a key changes. Cleanup also runs when the hook
is removed or its widget is disposed.

Owned hooks dispose in reverse call order. Cleanup continues after a failure,
then the first error is rethrown.

## Custom hooks

Prefer functions that compose built-in hooks:

```dart
ValueNotifier<int> useCounter([int initialValue = 0]) {
  final counter = useState(initialValue);
  useEffect(() {
    return null;
  }, <Object?>[counter.value]);
  return counter;
}
```

For lifecycle behavior that composition cannot express, extend `Hook` and
`HookState`. A class hook can initialize, update, reassemble, rebuild, access
the host context and ticker provider, and dispose resources.
