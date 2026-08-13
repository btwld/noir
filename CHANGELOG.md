# Changelog

## 1.0.0-alpha.1

- First 1.0 prerelease of Noir's Flutter-like reactive widget framework for
  terminal applications.
- Declarative stateless and stateful widgets, `setState`, layout, text styling,
  focus, keyboard and mouse input, text editing, scrolling, and animation.
- Hot reload support: `TuiApp.reassemble()` rebuilds every mounted element and
  forces a full layout and paint pass, preserving `State`, focus, scroll, and
  animation state and recreating no terminal or native resource.
- Opt-in `registerHotReloadExtension(app)` publishes the `ext.noir.reassemble`
  VM service extension so a development driver can rebuild a running app after
  `reloadSources`.
- The counter example is keyboard-driven with Up/Down and `+`/`-`; an
  unconsumed Ctrl+C key follows the terminal session's cleanup and interrupt
  exit path while higher-priority handlers can override it.
- Terminal shutdown restores inherited line and echo modes before cancelling
  the stdin subscription, avoiding Dart/macOS `EBADF` errors during Escape or
  other normal disposal paths.
- Terminal input preserves modifiers from xterm `modifyOtherKeys` reports,
  maps Home/Insert/End and function-key reports to pinned OpenTUI semantics,
  and retains press/repeat/release metadata from Kitty functional and tilde
  reports. The multiline examples use Ctrl+D as a portable submit key while
  `TextArea` still accepts Ctrl+Enter when the terminal reports that chord.
- Bundled, SHA-256-verified OpenTUI native libraries for macOS, Linux, and
  Windows on x64 and arm64.
- Canonical OpenTUI v0.5.1 source and unchanged official release assets.
- macOS bundles require macOS 13.0 or later.
- See
  [Known Limitations](https://github.com/leoafarias/noir#known-limitations)
  for current platform and rendering constraints.
