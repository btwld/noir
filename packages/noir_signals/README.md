# noir_signals

Reusable widget lifecycle hooks and Signals reactive state for
[Noir](https://pub.dev/packages/noir), the Flutter-like terminal UI framework
for Dart.

This package is optional. Installing Noir alone does not pull it in.

Start with the task-list tutorial, which begins at
[Build a task list](doc/getting-started.md). Its five lessons connect
hook-owned text input, signals, a computed remaining count, and user actions
in one runnable app.

## Install

`noir_signals` and its required Noir 0.0.1 are unpublished candidates, so
both packages come from one checkout of the
[public Noir repository](https://github.com/conceptadev/noir) today.

### In your own application

Clone Noir beside your application directory, then declare both packages:

```yaml
dependencies:
  noir: ^0.0.1
  noir_signals:
    path: ../noir/packages/noir_signals
dependency_overrides:
  noir:
    path: ../noir
```

Run `dart pub get` from your application directory. The override routes the
companion's own `noir` dependency to the same checkout, so one revision
supplies both packages.

### Inside the Noir repository

The repository is one Pub workspace, so `dart pub get` at its root resolves
both packages. The task-list tutorial builds its app there, in
`packages/noir_signals/example/`.

### After publication

An application will declare hosted versions instead. This block cannot resolve
from pub.dev yet:

```yaml
dependencies:
  noir: ^0.0.1
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

The [example directory](example/README.md) contains the runnable counter, task
list, and file search, with setup and run commands. The tutorial's earlier
checkpoints are in
[`example/tutorials/task_list/`](example/tutorials/task_list/); its final
checkpoint is [`example/task_list.dart`](example/task_list.dart).

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
