# Signals in Noir

`package:noir_signals/noir_signals.dart` connects the
[`signals_core`](https://pub.dev/packages/signals_core) reactive engine to
Noir's widget lifecycle. Signals owns the reactive graph. Noir keeps owning
scheduling, reconciliation, layout, paint recording, and native resources.

A subscription callback never runs a builder, flushes a frame, or paints. It
only asks Noir to rebuild, and Noir's scheduler coalesces repeated requests
into one frame.

## Install and import

```yaml
dependencies:
  noir: ^0.0.1-alpha.5
  noir_signals: ^0.0.1-alpha.0
```

```dart
import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
```

The entrypoint re-exports the upstream primitives an application normally
needs: `Signal`, `ReadonlySignal`, `Computed`, `signal`, `computed`, `effect`,
`batch`, `untracked`, and the option types. Import
`package:signals_core/signals_core.dart` directly for the wider upstream
surface. Noir's hook `Effect` typedef keeps its name; the upstream class of the
same name is not re-exported.

## The four hooks and the builder

| API | Ownership | Rebuild behavior |
| --- | --- | --- |
| `useSignal(initialValue, {keys, options})` | Creates and disposes a `Signal`. | Rebuilds the host after the value changes. |
| `useComputed(compute, {keys, options})` | Creates and disposes a `Computed`. | Rebuilds the host after the result changes. |
| `useSignalValue(source)` | Borrows the source; owns only the subscription. | Rebuilds the host and returns the current value. |
| `useSignalEffect(callback, {keys, options})` | Owns a reactive effect and its cleanup. | Requests no rebuild; runs an application side effect. |
| `SignalValueBuilder(signal:, builder:)` | Borrows one source. | Rebuilds only its own subtree. |

Local state:

```dart
class Counter extends HookWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useSignal(0);

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

`useState` remains simpler for a plain local counter. Signals earn their place
when state is derived or shared: filtered lists, selected-item details, counts,
and progress across several widgets.

## Keep the model out of the widget

An application model is ordinary Signals code:

```dart
import 'package:signals_core/signals_core.dart';

class FileModel {
  final query = signal('');
  final files = signal<List<String>>(const []);
  late final visibleFiles = computed(() {
    final term = query.value.toLowerCase();
    return List<String>.unmodifiable(
      files.value.where((file) => file.toLowerCase().contains(term)),
    );
  });

  void dispose() {
    visibleFiles.dispose();
    files.dispose();
    query.dispose();
  }
}
```

One owner creates and disposes the model. Pass it through constructors or an
`InheritedWidget`. Observe it from a widget with `useSignalValue`, or scope the
rebuild to a subtree with `SignalValueBuilder`:

```dart
final visible = useSignalValue(model.visibleFiles);
...
SignalValueBuilder<int>(
  signal: model.visibleCount,
  builder: (context, count) => Text('$count files'),
)
```

Replace a collection signal's value instead of mutating the list in place. A
newly allocated list normally has different equality even when its contents
match.

## Ownership

`useSignal` and `useComputed` own what they create, so `options.autoDispose`
must stay false; the hooks reject `true`. `useSignalValue` and
`SignalValueBuilder` borrow: they never dispose the source, and an
auto-disposing source keeps its upstream behavior when the last observer goes
away.

When a key change replaces an owned signal, the hook detaches its own
observation at once and hands disposal of the retired signal to Noir's
`State.deferDispose`. Noir releases it after the host successfully updates its
descendants and the removed descendants finish unmounting, so a child observer
or a child effect cleanup never reads a signal that was released too early. A
failed build keeps the retired signal alive until a later reconciliation
succeeds.

## Keys and captured values

Signals read inside a `useComputed` or a `useSignalEffect` callback are tracked
by Signals, including dependencies that change between evaluations. Ordinary
Dart values the closure captures are not tracked: list them in `keys`. A
changed key list creates the replacement.

`initialValue`, the computation, the effect callback, and the creation options
are used only when the slot is created. An unchanged key list does not refresh
a captured value.

## Effects

`useSignalEffect` runs its body once on install and again when a tracked
dependency changes. Return a cleanup to release what the run acquired; Signals
runs it before the next run and once at teardown.

The install and the lifecycle cleanup run under the same guard as `useEffect`,
so neither may synchronously request a hook rebuild. Signals wraps a failure
raised by the body in a `SignalEffectException`, whose `error` holds the
original. Later dependency-driven reruns keep upstream timing.

## What this is not

Reads inside event handlers, asynchronous callbacks, and deferred child
builders are outside any observation this package installs. A widget that
reads `model.value.value` without one of the hooks above is not reactive.

There is no automatic whole-build tracking yet: `SignalWidget` and
`SignalBuilder` remain a separate feature. Observe explicitly with
`useSignalValue` or `SignalValueBuilder`.

This integration reduces which widget builds Noir is asked to run. Noir still
accepts full-root layout and paint recording on dirty frames, so it is not a
changed-cell rendering claim or a measured performance improvement.
