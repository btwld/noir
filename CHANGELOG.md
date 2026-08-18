# Changelog

## 0.0.1-alpha.1

- Added `Theme` and `ThemeData`: a flat, inherited color-token palette that
  built-in widgets resolve against as
  `explicitParameter ?? Theme.maybeOf(context)?.token ?? widgetDefault`.
  `ThemeData.dark` reproduces the literals the built-in widgets already used,
  so an app with no `Theme` ancestor renders unchanged. The renamed
  `DemoThemeData` in `example/inherited_example.dart` no longer shadows the
  real API.
- Added `ListView`, a windowed list that calls its row builder only for the
  rows currently on screen, so list cost tracks the viewport rather than the
  item count. One widget covers both a selectable list (arrows, `j`/`k`,
  paging, Home/End, Enter, click) and a plain scrolling one; the mouse wheel
  scrolls either.
- Added `Checkbox`, `Switch`, `Button`, `Divider`, `ProgressBar`, `Spinner`,
  and `Badge`. The three interactive controls share one activation contract —
  Space, Enter, or a left click — and are disabled by leaving their callback
  null, which also drops them out of Tab traversal.
- The development driver (`scripts/noir_drive.dart`) accepts `key space`.
  `type` cannot send a lone space because the CLI trims each command line, so
  Space was previously unreachable from a script.
- Added `DataTable` and `DataColumn`: an aligned header over a windowed body,
  with fixed or proportional columns, keyboard and mouse row selection, and
  presentational click-to-sort headers. The header and every body row are
  built from the same ordered column list, which is what keeps their cell
  boundaries identical.
- `Select`'s color parameters are now nullable and resolve through the
  nearest `Theme`. An unthemed `Select` is byte-identical to before;
  `backgroundColor: null` now means "the theme's surface, else no fill", so
  pass `Color.transparent` for an explicitly unfilled list inside a themed
  subtree.
- `TextInput`, `TextArea`, and `ScrollBox` resolve their colors through the
  nearest `Theme` on the same terms as `Select`: nullable parameters, previous
  literals as the unthemed fallback, and an explicit argument always winning.
- `Spinner` retunes its one `AnimationController` instead of replacing it. It
  previously built a second controller when `interval` or the frame count
  changed, which asked `SingleTickerProviderStateMixin` for a second ticker
  and asserted.
- The native-asset build hook now declares `native_manifest.json` and the
  selected bundled library as file-system dependencies. Dart can therefore
  invalidate cached hook output, repeat SHA-256 verification, and regenerate
  the derived macOS bundle copy when either input changes.
- Added focused regression coverage for the hook dependency declarations and
  documented how to suppress routine build-hook status without skipping native
  asset verification.
- Added the Like Reactor example, demonstrating deterministic heart particles,
  animation-driven morphing, and overlapping keyboard and mouse activation.

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
