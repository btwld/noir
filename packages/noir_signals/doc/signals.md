# Signals reference

`package:noir_signals/noir_signals.dart` connects the
[`signals_core`](https://pub.dev/packages/signals_core) reactive engine to
Noir's widget lifecycle. Signals owns the reactive graph. Noir keeps owning
scheduling, reconciliation, layout, paint recording, and native resources.

A subscription callback never runs a builder, flushes a frame, or paints. It
only asks Noir to rebuild, and Noir's scheduler coalesces repeated requests
into one frame.

This document is the reference. To learn `useSignal` and `useComputed` by
building an app, start with [Build a task list](getting-started.md).

## Install and import

The companion requires Noir 0.0.3. An application declares both packages; the
[package overview](../README.md) also covers a repository checkout:

```yaml
dependencies:
  noir: ^0.0.3
  noir_signals: ^0.0.1-alpha.1
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

## Observe borrowed state

A model owns the signals it creates and exposes them to widgets through
constructors or an `InheritedWidget`. The
[file-search model](../example/models/file_search_model.dart) and its
[screen](../example/file_search.dart) show the complete ownership pattern.

The file-search screen observes each derived source with
`SignalValueBuilder`, so the field host does not rebuild on every filter:

```dart
SignalValueBuilder<int>(
  signal: model.visibleCount,
  builder: (context, count) => Text('$count files'),
),
SignalValueBuilder<List<String>>(
  signal: model.visibleFiles,
  builder: (context, visible) => Column(
    children: [for (final file in visible) Text(file)],
  ),
),
```

`useSignalValue` observes one borrowed source on the host instead.

These observers borrow their source; the model remains responsible for disposal.
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
by Signals, including dependencies that change between evaluations. Do not
list those signals in `keys`; the latest computation and effect callback run
on the next reactive evaluation.

Ordinary Dart values the closure captures are not tracked. A computed keeps
its last result until a tracked signal changes. An effect does not re-run
until a tracked signal changes. List a captured value in `keys` only when a
change must recreate the computed or re-install the effect immediately.
Creation options stay tied to the slot that installed them.

## Effects

`useSignalEffect` runs its body once on install and again when a tracked
dependency changes. Return a cleanup to release what the run acquired; Signals
runs it before the next run and once at teardown.

The install and the lifecycle cleanup run under the same guard as `useEffect`,
so neither may request a hook rebuild while it runs. That guard covers every
hook host in the isolate, not only the one that owns the effect: a cleanup
that writes a signal another `SignalWidget` observes makes that widget's rebuild
request throw, and the failure escapes the frame. Write to shared signals from
an input callback, a timer, or a future instead — the effect has returned by
then. Later dependency-driven reruns are not guarded and keep upstream timing.

A failure raised by the install run propagates unchanged. Signals wraps a
failure raised by a later rerun in a `SignalEffectException`, whose `error`
holds the original.

## Observation limits

Reads inside event handlers, asynchronous callbacks, and deferred child
builders are outside any observation this package installs. Reading
`model.visibleFiles.value` alone does not subscribe the widget.

There is no automatic whole-build tracking. `SignalWidget` and
`SignalBuilder` retain lifecycle and signal hooks; reading a borrowed signal
alone does not subscribe. Observe it with `useSignalValue` or
`SignalValueBuilder`.

This integration reduces which widget builds Noir is asked to run. Noir still
accepts full-root layout and paint recording on dirty frames, so it is not a
changed-cell rendering claim or a measured performance improvement.
