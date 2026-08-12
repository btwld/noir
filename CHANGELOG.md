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
- Bundled, SHA-256-verified OpenTUI native libraries for macOS, Linux, and
  Windows on x64 and arm64.
- Canonical OpenTUI v0.5.1 source and unchanged official release assets.
- macOS bundles require macOS 13.0 or later.
- See
  [Known Limitations](https://github.com/leoafarias/noir#known-limitations)
  for current platform and rendering constraints.
