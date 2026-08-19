# Changelog

## 0.0.1-alpha.1

- Added `Theme` / `ThemeData` and a first component tier: `ListView`,
  `Checkbox`, `Switch`, `Button`, `Divider`, `ProgressBar`, `Spinner`,
  `Badge`, and `DataTable`. Built-in widgets resolve omitted colors as
  `explicit ?? Theme.of(context).token`. `ThemeData.dark` is the unthemed
  look. Nullable `backgroundColor` still uses `Theme.maybeOf` so "no fill"
  stays expressible.
- `Checkbox`, `Switch`, and `Button` activate on Space, Enter, or a left
  click. A null callback disables them. `ListView` is windowed; omit
  `selectedIndex` for plain scroll. `DataTable` shares one column list
  between header and body, with `columnSpacing` (default 1).
- A focused `ListView`, `Select`, or `DataTable` paints
  `selectedBackground`; unfocused, the highlight mutes to `surfaceVariant`.
- `Select`, `TextInput`, `TextArea`, and `ScrollBox` take nullable colors
  and resolve them through `Theme` the same way.
- `runTuiApp` is one line: `runTuiApp(const MyApp(), enableMouse: true)`.
  It registers hot reload itself and no longer takes `width`/`height`.
  `TuiApp.exit(context)` ends the app (dispose, set the exit code, drain
  the loop). A mid-build exit throws. Drive mode follows an in-app exit.
  Examples and the patch manager quit through the tree.
- Examples share `example/src/demo_scaffold.dart` for chrome. The authoring
  skill catalogs the new widgets and how to compose them.
- `scripts/noir_drive.dart` accepts `key space`.
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
