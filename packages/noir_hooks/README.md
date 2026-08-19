# noir_hooks

`noir_hooks` adds reusable lifecycle hooks to Noir widgets. It is a companion
package for `package:noir/noir.dart`. It does not use Flutter, Noir's concrete
Element classes, Noir's low-level renderer API, or FFI.

This package is unrelated to Dart's native build and link hooks. Noir uses
Dart build hooks to bundle OpenTUI. `noir_hooks` provides UI lifecycle hooks.

## Install

Add both packages:

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

`HookBuilder` provides the same lifecycle for inline builders:

```dart
final widget = HookBuilder(
  builder: (context) {
    final enabled = useState(false);
    return Text(enabled.value ? 'enabled' : 'disabled');
  },
);
```

## Noir-specific model

Noir is Flutter-like, but it is an independent widget framework. This package
does not install a custom Element or copy Flutter's scheduler. `HookWidget` is
a normal Noir `StatefulWidget`; rebuilds flow through Noir's `State` and
`BuildOwner`, and animations use Noir's ticker scheduler. Effects run
synchronously while the hook widget builds.

To combine explicit `State` lifecycle methods with hooks, keep a
`HookBuilder` at a stable position inside the state's `build` method. The
package does not expose a `StatefulHookWidget`: Noir's public API does not
intercept an arbitrary user-created `State`, and the package does not depend
on framework-owned Element classes to simulate that behavior.

## Rules

Stateful hooks use call order as identity. `useContext` is a build-only
lookup and does not consume a hook slot.

- Call hooks only while a `HookWidget` or `HookBuilder` is building.
- Call the same stateful hooks in the same order on every build.
- Do not put stateful hook calls in conditions or loops.
- Do not call any hook from event callbacks, effects, or class-based lifecycle
  methods other than `HookState.build`.
- Prefix custom hook functions with `use`.
- Use top-level hook functions to compose other hooks.

A runtime hook-type change resets that slot and every later slot. A key change
recreates only that hook slot. Key lists are snapshotted, so later mutation of
a caller-owned list cannot corrupt retained identity.

## Included hooks

Core lifecycle:

- `useState`, `useEffect`, `useMemoized`, `useCallback`, `useRef`
- `usePrevious`, `useValueChanged`, `useReducer`
- `useDisposable`, `useOnDispose`, `useIsMounted`, `useContext`

Observable values:

- `useListenable`, `useValueListenable`, `useListenableSelector`
- `useValueNotifier`, `useChangeNotifier`, `useOnListenableChange`

Asynchronous values:

- `useFuture` and `useStream`, returning `AsyncSnapshot`
- stale future and stream callbacks are ignored after replacement or disposal
- stream subscriptions are canceled when replaced or disposed

Noir integrations:

- `useTickerProvider`, `useAnimationController`, `useAnimation`,
  `useAnimationStatus`
- `useTextEditingController`, `useFocusNode`, `useScrollController`,
  `useViewportController`

## Effects and cleanup

`useEffect` is synchronous. Without keys, it cleans up and reruns on every
build. With keys, it reruns when a key changes. Its cleanup runs before the next
effect and during disposal.

Owned hooks dispose in reverse call order. Cleanup continues after a failure,
and the first error is rethrown after all cleanup attempts.

## Custom hooks

Most custom hooks should be top-level functions that compose existing hooks:

```dart
ValueNotifier<int> useCounter([int initialValue = 0]) {
  final counter = useState(initialValue);
  useEffect(() {
    // Subscribe or record diagnostics here.
    return null;
  }, <Object?>[counter.value]);
  return counter;
}
```

For lifecycle logic that cannot be expressed by composition, extend `Hook` and
`HookState`. A class-based hook can initialize state, respond to new hook
configuration, request rebuilds, access the host context and ticker provider,
and release resources. `HookState.build` may compose later hooks. Other
class-based lifecycle callbacks must not call hooks.

## Architecture

`HookWidget` is implemented as a public Noir `StatefulWidget` adapter. Its
`State` owns the ordered hook slots and shares Noir's ticker scheduler. This
keeps widget identity and rebuild scheduling in Noir's normal framework path
without exposing or depending on concrete Element implementations.
