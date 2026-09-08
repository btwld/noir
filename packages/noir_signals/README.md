# noir_signals

Reusable widget lifecycle hooks and Signals reactive state for
[Noir](https://pub.dev/packages/noir), the Flutter-like terminal UI framework
for Dart.

This package is optional. Installing Noir alone does not pull it in.

Start with the [task-list walkthrough](doc/getting-started.md). It connects
hook-owned text input, signals, a computed remaining count, and user actions
in one runnable app.

## Install

The versions below are unpublished candidates. In this repository, run
`dart pub get` at the root to resolve both workspace packages. See the
[walkthrough](doc/getting-started.md#run-the-examples) for checkout commands.
After publication, an application can use:

```yaml
dependencies:
  noir: ^0.0.1-alpha.5
  noir_signals: ^0.0.1-alpha.0
```

## Import

One entrypoint carries the whole surface:

```dart
import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
```

## Use SignalWidget

Extend `SignalWidget` to retain lifecycle hooks and reactive state across
builds. Use `SignalBuilder` when a small inline subtree needs hooks.

```dart
class Counter extends SignalWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useSignal(0);
    return Button(label: '${count.value}', onPressed: () => count.value++);
  }
}
```

`useSignal` owns and observes the value above. Use `useState` for a simple
local value, or `useComputed` for a value derived from other signals. Hooks
must be called in the same order on every build.

There is no automatic whole-build tracking. Observe borrowed signals with
`useSignalValue` or `SignalValueBuilder`; a plain `.value` read does not
subscribe the widget. The package also re-exports the public `signals_core`
primitives needed to define a model.

## Examples and reference

The [example directory](example/README.md) contains the runnable counter, task list,
and file search, with setup and run commands. Follow
[Build a task list](doc/getting-started.md) for the step-by-step tutorial.

- [Hooks reference](doc/hooks.md): hook families, call order, resource ownership,
  and custom hooks.
- [Signals reference](doc/signals.md): signal ownership, observation, replacement,
  and effect cleanup.

## Boundaries

The production code here imports only `package:noir/noir.dart` and the public
`signals_core` API. It reaches no Noir private library, no low-level or FFI
barrel, and no native code. Noir keeps owning scheduling, reconciliation,
layout, paint recording, and native resources.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
