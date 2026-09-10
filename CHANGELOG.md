# Changelog

## 0.0.1-alpha.5

Unreleased. This prerelease adds `LayoutBuilder` and one framework lifecycle
seam, fixes focus recovery and keyed `ListView` rows, and moves the opt-in
hooks library to a separate package. The native ABI and the bundled native
artifacts are unchanged from alpha.4.

### Added

- Added `LayoutBuilder`, which builds its child from the incoming
  `BoxConstraints`. The builder runs during layout and its result is laid out
  in the same frame, so the constraints it reads are the constraints its child
  receives. It runs on the first layout, on a constraint change, on a widget
  update, on an inherited dependency change, and on reassembly; repeated layout
  at unchanged constraints does not run it. A builder that throws leaves the
  element marked, so the next layout retries.
- Added `State.deferDispose` and `HookState.deferDispose`. A host registers a
  cleanup for a resource it retires while the descendants built by the previous
  configuration may still read it. The framework releases that resource after
  the host successfully updates its descendants and the removed descendants
  finish unmounting, or during unmount before `State.dispose` runs. Batches
  release descendants before ancestors, registration order is preserved inside
  one host, and a failed initialization, widget update, or build keeps the
  resource alive until a later reconciliation succeeds.

### Fixed

- The packaged hot-reload runner now recompiles detected edits whose file
  timestamps predate compilation, including recovery after a rejected reload.
  This forces recompilation and can take longer than an incremental reload.
- `FocusManager` now recovers focus after an involuntary loss. Disabling the
  focused control or removing the region that owns focus previously left the
  tree with no primary focus, and `Shortcuts.handleKeyEvent` routes from the
  focused element, so the tree stopped answering every binding. Recovery runs
  after the synchronous tree updates finish and focuses the first control
  inside the nearest surviving explicit scope, so bindings mounted inside
  that scope answer again; the scope itself takes focus only when it holds no
  control. It then falls back to the first node in traversal order, and leaves
  focus empty when nothing is eligible. An explicit `requestFocus()` and an
  incoming `autofocus` both claim focus first, and an intentional `unfocus()`
  is not recovered.
- `autofocus` is now honored when it is enabled after mount.
- A layout request raised during layout is now answered in the same frame.
  `PipelineOwner.flushLayout` used to run one pass and then discard any
  render object marked while that pass ran, for example by a `LayoutBuilder`
  whose build touched a render object already laid out or still performing
  layout, and nothing retried it. The flush now runs another full pass while
  such requests remain, up to three passes, and then throws a `StateError` naming
  the render objects that kept requesting layout from inside layout. A
  request followed by that object's layout in the same pass does not cost a
  second pass. Adopting a child during layout also invalidates its active
  parent and conservatively retries that parent. Architecture tests now
  freeze the layout-time build seam to `LayoutBuilder` and keep the
  rendering layer free of element-layer imports.
- A keyed `ListView` row now names exactly one element. The row's `LocalKey`
  was copied onto the `SizedBox` wrapping it, so the key named two elements and
  a strict driver locator reported an ambiguous match. A keyed row that stays
  in the window still keeps its `State` while the window scrolls or the rows
  reorder, and a row that leaves the window is still disposed.
- `ListView` now follows its highlight when its own height or item extent
  changes, so a resized list keeps the selected row on screen while the
  controller keeps a valid scroll position.

### Changed

- The task-list walkthrough is now a five-lesson tutorial. Lesson 1 stays in
  `doc/getting-started.md`; lessons 2 to 5 live in `doc/tutorials/task-list/`.
  Each lesson keeps its exact changes, complete runnable checkpoint, and
  screenshot, and its earlier checkpoints ship as runnable files under
  `example/tutorials/task_list/`. The shipped `example/task_list.dart` is the
  final checkpoint, so the tutorial and the example cannot drift apart. The old
  step anchors still resolve from the tutorial's first page.
- `doc/hooks.md` and `doc/signals.md` are reference documents. Their
  introductions no longer restate the tutorial, and dependency setup points at
  the package overview.
- The core `example/` directory now carries the two first-app tutorial
  checkpoints under `example/tutorials/first_app/`. The published documentation
  captures its terminal frames from those exact files.

### Removed

- Removed `package:noir/hooks.dart`. The hook runtime, the built-in resource
  hooks, and their guide now live in the optional companion package
  `noir_signals`, published from `packages/noir_signals/` in this repository.
  Replace `package:noir/hooks.dart` with
  `package:noir_signals/noir_signals.dart` and add `noir_signals` to the
  application's dependencies. Rename `HookWidget` to `SignalWidget`,
  `HookBuilder` to `SignalBuilder`, and `HookWidgetBuilder` to
  `SignalWidgetBuilder`. Every hook function, return type, and lifecycle rule
  is unchanged: `useState` still returns a `ValueNotifier` and
  `useTextEditingController` still returns a `TextEditingController`.

## 0.0.1-alpha.4

This release corrects the package archive and moves checkout-only code to its
owning directories. Noir's public API shapes and runtime behavior, native ABI,
and bundled native artifacts are unchanged from alpha.3.

### Changed

- Large example implementations now live under `example/src/`, while every
  runnable entry point remains directly under `example/`. Shared example
  chrome has one owner under `example/src/shared/`.
- Package and contributor guidance now distinguish supported library surfaces,
  publishable examples, repository-only scripts, and website sources.
- Checkout-only entry points `bin/patch_manager.dart` and
  `bin/snapshot_scenes.dart` now live under `scripts/`, and the Patch Manager
  implementation now lives under `scripts/patch_manager/`. Both entry points
  were already excluded from the published alpha.3 archive.

### Fixed

- The archive now includes `third_party/opentui-v0.5.1/LICENSE-YOGA` and names
  Yoga v3.2.1 in `THIRD_PARTY_NOTICES.md`. The published
  `0.0.1-alpha.3` archive omitted this MIT license notice even though Yoga is
  compiled into the bundled OpenTUI libraries.

## 0.0.1-alpha.3

This release includes the work from the unpublished alpha.2 candidate; no
`0.0.1-alpha.2` package was published.

> **Post-release notice:** The published `0.0.1-alpha.3` archive omitted the
> Yoga v3.2.1 MIT license notice for the Yoga sources compiled into the bundled
> OpenTUI native libraries. The repository correction will ship in the next
> package version; the published alpha.3 archive cannot be changed.

### Added

- Added `Theme` / `ThemeData` and the first themed component tier:
  `ListView`, `Checkbox`, `Switch`, `Button`, `Divider`, `ProgressBar`,
  `Spinner`, `Badge`, and `DataTable`. Existing inputs, selects, and scroll
  views also resolve omitted colors through the nearest theme.
- Added the opt-in `package:noir/hooks.dart` library with `HookWidget`, state
  and effect primitives, async and listenable observation, and hooks for Noir
  controllers and animations.
- Added whole-cell `Stack` / `Positioned` and `Wrap`; horizontal `TabSelect`;
  horizontal and vertical `Slider`; seven original `AsciiFont` treatments;
  and rich, selectable `TextTable` grids.
- Added selectable `CodeView`, unified and split `DiffView`, and
  GitHub-flavoured `MarkdownView` with grapheme-safe selection, OSC52 copy,
  async highlighting, GFM tables, and semantic terminal hyperlinks.
- Added `TerminalImage` and the stateful `Image` widget for PNG, JPEG, WebP,
  first-frame GIF, and raw RGBA sources. They negotiate Kitty, Sixel, or block
  rendering and support measured pixel sizing, fit modes, cancellation, and
  explicit ownership.
- Added the root `OverlayPortal` / `OverlayPortalController` surface and
  launcher-anchored `MenuAnchor` / `MenuController` menus. This prerelease API
  does not claim Flutter's nested overlay, transform, animation, or cascade
  behavior.
- Added `Icons`, a width-audited catalog of 119 single-cell glyph strings.
  Terminal icons remain plain text (`Text(Icons.check)`), not an `Icon` widget
  or `IconData` hierarchy.
- Added the packaged `dart run noir:run` development command. It watches Dart
  sources, performs VM reload plus Noir reassembly, preserves the last good app
  after rejected edits, forwards arguments and exit status, and records
  diagnostics in `.dart_tool/noir/run.log`.
- Added headless drive mode, with a repository-only Dart client and CLI,
  parser-backed key and pointer input, exact key/type/text locators, focus
  snapshots, and production hit-test-path clicks. `scripts/noir_drive.dart`
  accepts `key space`.
- Added six guarded raw scissor- and opacity-stack operations to
  `package:noir/noir_ffi.dart`. These expose pinned OpenTUI availability only:
  its opacity stack does not fade ordinary text and cannot underpin an
  `Opacity` widget.
- Added the live Pub search example with injected test data, stale-response
  suppression, paging, completion suggestions, anchored sort/filter menus,
  responsive package details, and rendered health and advisory documents.
- Added opt-in chronological tail following to `ScrollController` through
  `followTail` and `isFollowingTail`. An opted-in controller starts at the
  trailing extent, follows content growth and reflow, detaches when scrolled
  above the end while preserving the top-row offset, and reattaches on return.
- Added `TextArea.maxHeight` for bounded visual-row growth, `softWrap` for
  grapheme- and cell-aware wrapping, and `submitOnEnter` so Enter submits
  while a distinguishable Ctrl+J inserts a newline and multiline paste stays
  intact.
- Added `DiffView.canRequestFocus`, so a read-only embedded preview stays out
  of the enclosing surface's keyboard traversal, and
  `MarkdownView.tableCellPaddingX`, which defaults to `0` to match the pinned
  OpenTUI Markdown renderer and leaves the choice to the application.
- Added the agent chat example: a product-neutral transcript whose
  presentation consumes a semantic backend and never learns which agent
  produced an event. A deterministic offline replay backend is the default,
  and an opt-in bounded Claude CLI backend behind `--claude=/absolute/path`
  drives the same reducer and widget tree. The adapter starts `claude -p`
  without a PTY in safe mode, keeps tools, slash commands, MCP servers, and
  session persistence off, and exposes no permission channel.

### Changed

- Simplified startup to `runTuiApp(const MyApp(), enableMouse: true)`.
  `runTuiApp` owns hot-reload registration and terminal dimensions;
  `TuiApp.exit(context)` now performs in-tree disposal and exit-code handling.
- Added `BuildContext.mounted` and `State.reassemble()`, hardened the State
  teardown window, made exact-type inherited lookups truly exact, and made
  framework-owned focus and text-controller replacement transactional.
- Focus nodes can move between inactive elements in the same focus manager
  without losing focus. Focused lists, selects, and tables use the selected
  theme color and mute that highlight when focus moves elsewhere.
- Standardized example chrome around terminal-native titled regions and moved
  Patch Manager's tracked-file presentation to `DiffView` without changing its
  staging and action model.
- `DiffView` fills an added or removed row to the viewport edge, and a split
  row fills each half up to its own edge, which matches the pinned OpenTUI
  diff renderer. Earlier rows painted their background only under the text.
- `MarkdownView` renders `-` for an unordered list item, which matches the
  pinned OpenTUI Markdown renderer. Earlier lists used a bullet glyph.

### Fixed

- Restored legacy raw Ctrl+A selection and Ctrl+C copy in document views while
  preserving enhanced key reports with associated text. Interactive sessions
  request xterm `modifyOtherKeys` mode 2 so Ctrl+C remains application input
  through tmux, then restore xterm and Kitty keyboard modes independently.
- Tightened renderer and terminal lifecycle cleanup: late resizes are ignored,
  closed sessions release renderer references, borrowed native buffer views are
  invalidated after render attempts, stale native draw stacks are cleared, and
  best-effort finalization cannot leak a cleanup exception.
- Fixed flex overflow, decorated-child, and clipped-buffer painting at viewport
  boundaries; image replacement and cancellation ownership; one-ticker
  `Spinner` behavior; swapped `ListView` viewport anchoring; and `Select` scroll
  indicators under tighter layout constraints.
- Pub search completion starts fresh hosted requests for each eligible prefix,
  keeps either successful endpoint when the other fails, and does not retain a
  stale completion corpus.
- `ImageProtocol.auto` uses block cells under tmux. Forced Kitty graphics
  through tmux remain unsupported for alpha.3 because placement may stay
  displaced until a resize.
- `TextArea` and `TextInput` paint each grapheme cluster whole. The earlier
  per-cell path kept only a cluster's first scalar, so an extended cluster
  such as a zero-width-joiner emoji lost its tail.
- `ScrollBox` clips a descendant editor's terminal cursor to the same viewport
  as its painted cells, so an editor scrolled out of view no longer positions
  a stray cursor outside the viewport.

### Removed

- **Breaking prerelease change:** removed the unused `ColorSupport`,
  `TerminalCapabilities`, `TerminalSize`, and `CapabilitiesDetection` helpers
  without compatibility shims.

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
  [Known Limitations](https://github.com/conceptadev/noir#known-limitations)
  for current platform and rendering constraints.
