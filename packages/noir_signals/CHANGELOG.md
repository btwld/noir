# Changelog

## 0.0.1-alpha.1

This release pairs the companion with the next Noir candidate. The library,
its public API, and its behavior are unchanged from 0.0.1-alpha.0.

### Changed

- `noir: ^0.0.3`. A caret constraint on a `0.0.x` version ends at the next
  patch, so the previous `^0.0.2` excluded Noir 0.0.3 and an application could
  not resolve the two together.

## 0.0.1-alpha.0

First prerelease of the optional companion package for
[Noir](https://pub.dev/packages/noir).

### Added

- Added the widget lifecycle hook runtime and the built-in hooks, moved
  from Noir's `package:noir/hooks.dart` library: `SignalWidget`,
  `SignalBuilder`, `Hook`, `HookState`, `use`, `useContext`, `useTickerProvider`,
  the state and effect primitives, the listenable and asynchronous hooks, and
  the controller and animation hooks. The hosts are renamed from `HookWidget`
  and `HookBuilder`; `HookWidgetBuilder` becomes `SignalWidgetBuilder`. Hook
  functions, return types, and lifecycle rules are unchanged. `useState` returns a `ValueNotifier` and
  `useTextEditingController` returns a `TextEditingController`.
- Added the Signals integration: `useSignal` and `useComputed` own and observe
  the upstream object they create, `useSignalValue` observes a borrowed source,
  `useSignalEffect` owns a reactive effect and its cleanup, and
  `SignalValueBuilder` rebuilds only its own subtree. `useComputed` and
  `useSignalEffect` run the latest callback on the next reactive evaluation;
  `keys` recreate the slot and are not a list of tracked signals. Hook-owned
  signals reject `autoDispose: true`, and a key change hands the retired signal
  to Noir's `State.deferDispose` so a child observer never reads a signal
  released too early. Automatic whole-build tracking is not part of this
  release.
- Added `package:noir_signals/noir_signals.dart` as the one authoring
  entrypoint. It also re-exports the `signals_core` primitives an application
  needs to declare a model. Noir's hook `Effect` typedef keeps its name; the
  upstream class of the same name is excluded from the re-export.
