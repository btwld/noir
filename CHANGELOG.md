# Changelog

## 0.0.1-alpha.1

- The native-asset build hook now declares `native_manifest.json` and the
  selected bundled library as file-system dependencies. Dart can therefore
  invalidate cached hook output, repeat SHA-256 verification, and regenerate
  the derived macOS bundle copy when either input changes.
- Added focused regression coverage for the hook dependency declarations and
  documented how to suppress routine build-hook status without skipping native
  asset verification.
- Added the Like Reactor example, demonstrating deterministic heart particles,
  animation-driven morphing, and overlapping keyboard and mouse activation.
- Added the Pub search example, a live pub.dev browser demonstrating an
  injected async data source behind an application-owned `PubCatalog` seam,
  explicit loading/empty/error/ready states, stale-response suppression, paging
  and sort controls, and a four-tab package detail view. Its tests inject a
  fake catalog, so every async path stays deterministic without network access.
- A `Focus` whose element is deactivated now releases its `FocusNode`
  immediately instead of holding it until unmount. Reconciliation defers
  unmounting to `BuildOwner.finalizeTree`, so relocating a supplied node within
  a single build previously threw `FocusNode ... is already attached to a live
  Focus widget`. This also lets the deferred autofocus microtask's
  `isAttached` guard bail correctly for a node detached mid-relocation.
- `Select`'s scroll indicator now describes the rows layout actually granted
  rather than the constructor `height` hint, so a list constrained shorter than
  its hint shows its up/down arrows, positions the down arrow on the last
  painted row, and draws no arrow at all when no option row was painted.

## 0.0.1-alpha.0

- First public alpha of Noir's Flutter-like reactive widget framework for
  terminal applications.
- Declarative stateless and stateful widgets, `setState`, layout, text styling,
  focus, keyboard and mouse input, text editing, scrolling, and animation.
- `Align` positions naturally sized children within bounded boxes while still
  filling bounded axes and shrink-wrapping unbounded axes.
- Hot reload support: `TuiApp.reassemble()` rebuilds every mounted element and
  forces a full layout and paint pass, preserving `State`, focus, scroll, and
  animation state and recreating no terminal or native resource.
- Opt-in `registerHotReloadExtension(app)` publishes the `ext.noir.reassemble`
  VM service extension so a development driver can rebuild a running app after
  `reloadSources`.
- The Flutter-inspired counter example composes a flat blue app bar, centered
  body, and solid square-style clickable action surface. Up/Down, `+`/`-`,
  Enter, Space, and left click drive its state; an unconsumed Ctrl+C key follows
  the terminal session's cleanup and interrupt exit path while higher-priority
  handlers can override it.
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
