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

The package re-exports the `signals_core` primitives an application needs to
declare a model, so a widget file normally imports only Noir and this package.
Import `package:signals_core/signals_core.dart` directly when a model needs the
wider upstream surface.

## Boundaries

The production code here imports only `package:noir/noir.dart` and the public
`signals_core` API. It reaches no Noir private library, no low-level or FFI
barrel, and no native code. Noir keeps owning scheduling, reconciliation,
layout, paint recording, and native resources.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
