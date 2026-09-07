# noir_signals

Reusable widget lifecycle hooks and Signals reactive state for
[Noir](https://pub.dev/packages/noir), the Flutter-like terminal UI framework
for Dart.

This package is optional. Noir does not depend on it, and an application that
never writes a hook or a signal never resolves it.

## Install

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

## Hooks

Hooks package one local state or lifecycle concern into a reusable function.
They run on Noir's ordinary retained widget lifecycle and use call order as
identity.

```dart
class Counter extends HookWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useState<int>(0);

    return Column(
      children: [
        Text('Count: ${count.value}'),
        Button(
          autofocus: true,
          label: '+ Add one',
          onPressed: () => count.value++,
        ),
      ],
    );
  }
}
```

Read [`doc/hooks.md`](doc/hooks.md) for the complete contract, and run
[`example/counter.dart`](example/counter.dart) for a finished application.

## Signals

The package connects the
[`signals_core`](https://pub.dev/packages/signals_core) reactive engine to
Noir's rebuild scheduling. It re-exports the upstream primitives an
application needs to declare a model, so a widget file normally imports only
Noir and this package. Import `package:signals_core/signals_core.dart`
directly when a model needs the wider upstream surface.

| API | Ownership | Rebuild behavior |
| --- | --- | --- |
| `useSignal(initialValue, {keys, options})` | Creates and disposes a `Signal`. | Rebuilds the host after the value changes. |
| `useComputed(compute, {keys, options})` | Creates and disposes a `Computed`. | Rebuilds the host after the result changes. |
| `useSignalValue(source)` | Borrows the source; owns only the subscription. | Rebuilds the host and returns the current value. |
| `useSignalEffect(callback, {keys, options})` | Owns a reactive effect and its cleanup. | Requests no rebuild. |
| `SignalValueBuilder(signal:, builder:)` | Borrows one source. | Rebuilds only its own subtree. |

```dart
class Counter extends HookWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useSignal(0);
    return Button(label: '${count.value}', onPressed: () => count.value++);
  }
}
```

There is no automatic whole-build tracking yet: `SignalWidget` and
`SignalBuilder` remain a separate feature. Observe explicitly with
`useSignalValue` or `SignalValueBuilder`. Read
[`doc/signals.md`](doc/signals.md) for the complete contract.

## Examples

| Command | What it shows |
| --- | --- |
| `dart run example/counter.dart` | `HookWidget` and `useState` in a finished application. |
| `dart run example/file_search.dart` | A Signals model behind a text field, with a scoped subtree rebuild. |

## Boundaries

The production code here imports only `package:noir/noir.dart` and the public
`signals_core` API. It reaches no Noir private library, no low-level or FFI
barrel, and no native code. Noir keeps owning scheduling, reconciliation,
layout, paint recording, and native resources.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
