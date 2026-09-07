# Changelog

## 0.0.1-alpha.0

First prerelease of the optional companion package for
[Noir](https://pub.dev/packages/noir).

### Added

- Added the widget lifecycle hook runtime and the built-in hooks, moved
  unchanged from Noir's `package:noir/hooks.dart` library: `HookWidget`,
  `HookBuilder`, `Hook`, `HookState`, `use`, `useContext`, `useTickerProvider`,
  the state and effect primitives, the listenable and asynchronous hooks, and
  the controller and animation hooks. Every name, return type, and lifecycle
  rule is unchanged. `useState` returns a `ValueNotifier` and
  `useTextEditingController` returns a `TextEditingController`.
- Added `package:noir_signals/noir_signals.dart` as the one authoring
  entrypoint. It also re-exports the `signals_core` primitives an application
  needs to declare a model. Noir's hook `Effect` typedef keeps its name; the
  upstream class of the same name is excluded from the re-export.
