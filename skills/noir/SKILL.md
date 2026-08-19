---
name: noir
description: >-
  Build terminal user interfaces in Dart with the noir framework — a
  Flutter-like declarative widget system (StatelessWidget/StatefulWidget,
  Row/Column/Container/Expanded, Text/TextStyle, Theme/ThemeData,
  TextInput/TextArea/Select/ListView/ScrollBox, Checkbox/Switch/Button,
  DataTable, Focus, setState, AnimationController) that renders through
  OpenTUI over FFI.
  Use this whenever writing or reviewing application code against
  `package:noir` — importing `package:noir/noir.dart`, building or editing a
  TUI app or example, wiring layout/state/focus/input/animation for a terminal
  app, or testing one — even if the user only says "terminal UI", "TUI", "CLI
  interface", or names a widget like Row, Column, Container, or Text without
  saying "noir". Not for the TypeScript/React/Solid OpenTUI bindings
  (`@opentui/react`, `@opentui/core`, Bun/tsx projects), and not for changing
  noir's own internals — see the "Boundaries" section for where those go.
---

# Noir — Flutter-like TUI framework for Dart

Noir uses a Flutter-inspired declarative widget model for the terminal. You
write `Widget` trees; noir lays them out in character cells and paints them
through OpenTUI's native renderer over Dart FFI. Familiar concepts transfer,
but terminal constraints and noir's prerelease contracts differ. Noir
signatures are authoritative — verify against them rather than assuming Flutter
API parity.

**Single import gets you the whole authoring surface:**

```dart
import 'package:noir/noir.dart';
```

`package:noir/noir_low_level.dart` is for advanced hosting, renderer/buffer
access, and supported custom render-object protocols. Concrete Element
implementations and the recorder/display-list/compositor backend stay
framework-owned. Raw FFI lives in `package:noir/noir_ffi.dart`; ordinary apps
almost never need either companion import.

## Critical rules

These catch the mistakes that don't surface until runtime:

1. **Sizes are `int` character cells, not logical pixels.** `width`, `height`,
   `EdgeInsets`, `SizedBox` dimensions, and `Row`/`Column` `spacing` are all
   `int`; `Flex.spacing` is a non-negative `int` measured in whole cells. A
   "cell" is one monospace character. Animated `double` values need `.round()`
   before they reach layout.
2. **Colors are `0.0–1.0` channels, not `0–255`.** `Color.rgb(0.05, 0.06, 0.1)`,
   named constants like `Color.cyan`, or `Color.fromHex('#1e90ff')`. There is
   no `Color(0xFF...)` ARGB form.
3. **`Container` takes `color` OR `decoration`, never both** — passing both
   trips an assertion. Use `color:` for a plain background; use
   `decoration: BoxDecoration(color:, border:)` when you need a border. Note
   `Border.all()` defaults to **black**, which is invisible on a dark panel, so
   pass `color:` explicitly.
4. **Quit through the tree, not `dart:io`.** `runTuiApp` returns the handle
   synchronously; the returned `TuiApp` owns `onKey()`, `onMouse()`, and
   `onPaste()` app-priority registrations (each returns an idempotent
   canceler) and the terminal session. `dispose()` is idempotent. Call
   `TuiApp.exit(context)` from a widget to end the app — that disposes the
   handle, sets the process exit code, and lets the event loop drain. Do not
   call `io.exit()`; it leaves the terminal in raw mode if the app has not
   been disposed. An unconsumed Ctrl+C key exits with cleanup by default;
   app and focused-widget handlers may consume it to override that fallback.
5. **Input is one ordered pipeline, and `app.onKey` runs before the focused
   widget.** This decides whether your key handler ever fires — see
   [Input routing](#input-routing-one-ordered-pipeline) below.
6. **Whatever you construct, you dispose.** `FocusNode`, `FocusScopeNode`,
   `TextEditingController`, `ScrollController`, `AnimationController`, and
   notifiers are all caller-owned when you pass them in; dispose them in
   `State.dispose`. Widgets create and own only the ones you omit.

## Quick start

A minimal stateless app — this is a complete, runnable program:

```dart
import 'package:noir/noir.dart';

void main() => runTuiApp(const HelloApp());

class HelloApp extends StatelessWidget {
  const HelloApp({super.key});

  @override
  Widget build(BuildContext context) => Container(
    color: Color.rgb(0.05, 0.06, 0.1),
    padding: const EdgeInsets.all(2),
    child: Column(
      spacing: 1,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('Noir', style: TextStyle(color: Color.yellow, fontWeight: FontWeight.bold)),
        Text('Flutter-like widgets for terminal apps.'),
        Text('Press Ctrl+C to exit.', style: TextStyle(color: Color.lightGray)),
      ],
    ),
  );
}
```

Add `noir` to `pubspec.yaml` (`dart pub add noir`), then `dart run` the file.
Inside this repo, `example/` has a runnable reference for every major feature
(`hello.dart`, `counter.dart`, `layout_basics.dart`, `layout_demo.dart`,
`focus_form.dart`, `select_demo.dart`, `scrollbox_demo.dart`,
`textarea_demo.dart`, `listview_demo.dart`, `components_demo.dart`,
`data_table_demo.dart`, `theme_demo.dart`, `pulse_animation.dart`,
`inherited_example.dart`, `framework_primitives.dart`, `chat_demo.dart`,
`widgets_tour.dart`) — read one before inventing a pattern.

## Mental model

- **Widgets declare; Elements preserve identity; RenderObjects lay out and
  paint.** You write widgets. Noir reconciles them into a persistent element
  tree (so `State` survives supported rebuilds) and a render tree that lays out
  in cells and records paint ops for OpenTUI.
- **`StatelessWidget`** = pure `build(context)`. **`StatefulWidget`** = a `State`
  object that persists across rebuilds and calls `setState(...)` to schedule a
  rebuild.
- **Constraints go down, sizes come up, parent sets position** — noir's layout
  protocol, expressed in integer cells.

### Representative differences from Flutter

| Flutter | Noir | Why |
|---|---|---|
| `double` logical pixels | `int` character cells | Terminals are a cell grid |
| `Color(0xFFRRGGBB)` | `Color.rgb(r, g, b)` with 0–1 channels | Maps to terminal color |
| `MaterialApp`/`Scaffold` | `runTuiApp(widget)` | No design system; just a root |
| `Image`, `Canvas` paths | text, box-drawing glyphs, cell colors | Terminal can't draw arbitrary pixels |
| Gestures (`GestureDetector`) | `PointerListener` + mouse events | Terminal mouse reporting |
| `MediaQuery` | `TerminalCapabilities` / resize callbacks | Terminal size & color support |

Noir provides familiar layout building blocks including `Row`, `Column`,
`Container`, `Padding`, `SizedBox`, `Align`, `Expanded`, `Flexible`,
`ConstrainedBox`, `DecoratedBox`, `Text`, `RichText`, and layering through
`Container.foregroundDecoration`. There is no `Stack`, `Wrap`, or
`GestureDetector` — check the catalog below before reaching for a Flutter name.

## Widget catalog (cheat sheet)

| Need | Widget(s) | Reference |
|---|---|---|
| Box with padding/color/border/size | `Container` | `references/widgets.md` |
| Horizontal / vertical layout | `Row`, `Column` (both extend the abstract `Flex`) | `references/widgets.md` |
| Share remaining space | `Expanded`, `Flexible` | `references/widgets.md` |
| Fixed gap or size | `SizedBox` | `references/widgets.md` |
| Inset a child | `Padding` | `references/widgets.md` |
| Position a child in a box | `Align` | `references/widgets.md` |
| Constrain min/max | `ConstrainedBox` | `references/widgets.md` |
| Plain or styled text | `Text`, `TextStyle`, `TextStyles` | `references/widgets.md` |
| Mixed-style text runs | `RichText`, `TextSpan` | `references/widgets.md` |
| Border / background paint | `BoxDecoration`, `Border`, `DecoratedBox` | `references/widgets.md` |
| App-wide color tokens | `Theme`, `ThemeData` | `references/widgets.md` |
| Horizontal / vertical rule | `Divider` | `references/widgets.md` |
| Status tag | `Badge` | `references/widgets.md` |
| Fraction of work | `ProgressBar` | `references/widgets.md` |
| One-cell activity glyph | `Spinner` | `references/widgets.md` |
| Single-line text field | `TextInput` | `references/inputs-and-focus.md` |
| Multi-line editor | `TextArea` | `references/inputs-and-focus.md` |
| Closed set of named options | `Select<T>` | `references/inputs-and-focus.md` |
| Windowed builder list | `ListView` | `references/inputs-and-focus.md` |
| Aligned columns + windowed body | `DataTable`, `DataColumn` | `references/inputs-and-focus.md` |
| Two-state mark | `Checkbox` | `references/inputs-and-focus.md` |
| Two-state on/off | `Switch` | `references/inputs-and-focus.md` |
| Push action | `Button` | `references/inputs-and-focus.md` |
| Scroll overflowing content | `ScrollBox`, `ScrollController` | `references/inputs-and-focus.md`
| Keyboard focus | `Focus`, `FocusScope`, `FocusNode` | `references/inputs-and-focus.md` |
| Mouse / pointer | `PointerListener` | `references/inputs-and-focus.md` |
| Keybindings → semantic intents | `Shortcuts`, `Actions`, `Intent` | `references/inputs-and-focus.md` |
| Local mutable state | `StatefulWidget` + `setState` | `references/state-and-animation.md` |
| Observable values | `ChangeNotifier`, `ValueNotifier` | `references/state-and-animation.md` |
| Editable text + cursor | `TextEditingController` | `references/state-and-animation.md` |
| Time-based animation | `AnimationController` + ticker mixin | `references/state-and-animation.md` |
| Share data down the tree | `InheritedWidget` | `references/state-and-animation.md` |

## Common patterns

### Layout: Row / Column / Expanded

`Row` and `Column` are the two concrete `Flex` subclasses (`Flex` itself is
abstract — you can name the type but not construct it). `mainAxisAlignment`
positions along the axis; `crossAxisAlignment` across it; `spacing` inserts
gaps between children. Wrap a child in `Expanded` to make it absorb leftover
main-axis space; leave a child unwrapped to keep its natural or fixed size:

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,     // full-width children
  children: [
    Expanded(                                         // above the status bar
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,  // full-height panes
        children: [
          SizedBox(width: 24, child: _sidebar()),     // fixed 24 cells
          Expanded(child: _main()),                   // the rest of the width
        ],
      ),
    ),
    SizedBox(height: 1, child: _statusBar()),         // pinned last row
  ],
)
```

Equal `flex` values split evenly; `Expanded(flex: 2)` beside `Expanded(flex: 1)`
takes two-thirds. Note the explicit `crossAxisAlignment`: it defaults to
`center`, which shrink-wraps children on the cross axis — a full-bleed panel or
status bar needs `stretch`.

### Input routing: one ordered pipeline

Every key event walks the same path, and the first handler that returns
`KeyEventResult.handled` (or calls `event.consume()`) ends the walk:

1. **`app.onKey` handlers** on the `TuiApp` handle — these run *before* the
   focus tree.
2. **`Shortcuts`** ancestors of the focused element: matching activator →
   `Intent` → nearest `Actions` handler.
3. **Printable characters** dispatched as `InsertTextIntent` — this is how text
   fields receive typing.
4. **`onKeyEvent`** on the focused `FocusNode`, then each ancestor node
   (`Focus`, `FocusScope`), bubbling up.
5. **Default Tab / Shift+Tab focus traversal** — only if nothing above handled
   the event.
6. **Terminal-session Ctrl+C fallback** — an unconsumed key press restores the
   terminal and exits with interrupt status 130.

Two consequences worth internalizing:

- **Tab already moves focus.** A `FocusScope` traverses its focusable
  descendants for free. Hand-written Tab handling runs at step 4 and pre-empts
  the built-in policy, so only write it when you deliberately want different
  traversal.
- **A bare-letter global binding steals typing.** `app.onKey` sees `q` before a
  focused `TextInput` does, which makes the letter untypable. Use a modifier
  (`Ctrl+Q`) for app-level bindings, or scope the binding with `Shortcuts`
  inside the tree so it only applies where focus is.
- **Ctrl+C is overridable.** Consume it in an app, shortcut, or focused-widget
  handler when the application needs different behavior; otherwise the final
  terminal-session fallback shuts down cleanly.

### State: StatefulWidget + setState

```dart
class Counter extends StatefulWidget {
  const Counter({super.key});
  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;
  @override
  Widget build(BuildContext context) => Column(children: [
    Text('Count: $_count'),
    // call setState(() => _count++) from an input handler to rebuild
  ]);
}
```

Noir's current `State` hooks are `initState`, `didChangeDependencies`,
`didUpdateWidget`, `deactivate`, `reassemble`, and `dispose`, with the
`mounted` guard. Check `mounted` before `setState` in an async callback.
Override `reassemble` to refresh `initState`-derived values after a hot
reload. Details and disposal discipline are in
`references/state-and-animation.md`.

### Text & styling

`Text(data, style: TextStyle(...))`. `TextStyle` defaults to white foreground;
set `color`, `backgroundColor`, `fontWeight: FontWeight.bold` (also `.dim`),
`fontStyle: FontStyle.italic`, `decoration`, and terminal `effect`s. Reach for
the prebuilt `TextStyles.error` / `.success` / `.muted` / `.bold` constants for
common cases. Full styling surface in `references/widgets.md`.

### Compose the shipped components

Chrome — surfaces, borders, hints, selection highlight — reads
`Theme.of(context).token`. `Theme.of` falls back to `ThemeData.dark`, which
*is* the unthemed look of every built-in widget. Content color stays a
literal only when the color is the subject (a speaker, a specimen block, a
teaching palette).

`Checkbox`, `Switch`, and `Button` activate on Space, Enter, or a left
click. A null callback disables the control (muted, skipped by Tab).
Focused controls go bold; a focused `ListView`, `Select`, or `DataTable`
paints `selectedBackground` and mutes to `surfaceVariant` when it does
not own the keyboard.

Pick the list by the job:

- `Select<T>` — a closed set of named options; `onChanged` on highlight,
  `onSelect` on Enter/click.
- `ListView` — a windowed `itemBuilder` over `itemCount` rows. Pass
  `selectedIndex` for a highlight; omit it for plain scroll.
- `ScrollBox` — one child that may overflow. Not a list of items.
- `DataTable` — aligned `DataColumn`s over a `ListView` body.

Hand-roll a bordered box with `Container` + `BoxDecoration` +
`Theme.of(context).border`. There is no public `Panel` widget.
Spacing, chrome tokens, and what not to invent are in
`references/design.md`.

### Interactive widgets (overview)

`TextInput`, `TextArea`, `Select<T>`, `ListView`, `ScrollBox`, `Checkbox`,
`Switch`, and `Button` are focus-aware: give each a `FocusNode` (or
`autofocus: true`). For anything you need to read or mutate from code —
clearing a form, seeding a draft — pass a `TextEditingController` rather
than the `value:` shorthand; the two are mutually exclusive. The callback
split to remember: `Select.onChanged` / `ListView.onChanged` fire as the
highlight moves; `onSelect` fires on confirm (Enter/click). Full
constructors and key bindings are in `references/inputs-and-focus.md`.

## Hot reload during development

Noir apps hot reload through the VM service, in two steps a driver performs
for you: `reloadSources` swaps edited code, then the `ext.noir.reassemble`
extension rebuilds the live tree. `runTuiApp` registers that extension
automatically:

```dart
void main() => runTuiApp(const MyApp());
```

The function stays exported for custom hosts that do not go through
`runTuiApp`.

Inside this repo, run the app under the bundled driver and save a `.dart`
file to reload:

```sh
dart run scripts/hot_reload_driver.dart example/counter.dart
```

Outside the repo, any driver works that calls `reloadSources` and then the
extension — for instance `package:hotreloader` with
`onAfterReload: (_) => app.reassemble()`. `app.reassemble()` invokes
`State.reassemble()` on every retained state, then re-runs every `build()`
and forces a full layout and paint pass; `State`, focus, scroll, and
animation values survive, and no terminal or native resource is recreated.
`main()` and `initState` of already-mounted state are not re-run — override
`State.reassemble()` to re-derive what those `initState` bodies computed.
Other changes the VM cannot swap still need a restart: signatures held by
live stack frames, enum-to-class conversions, and the native OpenTUI library.

## See and drive a running app (drive mode)

Setting `NOIR_DRIVE=1` in the environment makes `runTuiApp` mount any app
headlessly — no TTY, no raw mode, no code change — and publish an
`ext.noir.driver.*` VM-service surface: capture the rendered frame
(characters, 24-bit colors, cursor), inspect the widget tree, inject input
bytes through the production ANSI parser, resize the emulated terminal
(`NOIR_DRIVE_SIZE=WxH`, default 80×24), and quit.

Inside this repo, the bundled driver CLI launches an app that way and reads
commands from its own stdin — interactively, or piped for scripted checks:

```sh
printf 'capture --ansi\nkey up\ncapture --ansi\nquit\n' | \
  dart run --verbosity=error scripts/noir_drive.dart example/counter.dart
```

`capture --ansi` prints the frame in true color ("see the design");
`--plain`/`--cells` give text or JSON. Other commands: `tree [depth]`,
`key <name>`, `type <text>`, `click <x> <y>`, `scroll`, `resize <WxH>`,
`reload` (hot reload + reassemble), `watch on|off`. Viewing an app at several
sizes this way is how layout problems at small terminals get caught early.

Outside the repo the extension surface still activates, but the CLI and the
`NoirDriver` client are not part of the published package, and the surface is
development tooling rather than stable API. Drive mode is for looking at and
driving a live app; automated assertions belong in ordinary tests
(`references/testing.md`).

## Reference index

Load the file that matches your task — each is self-contained:

| File | Covers |
|---|---|
| `references/widgets.md` | Layout/text/painting plus `Theme`/`ThemeData`, `Divider`, `Badge`, `ProgressBar`, `Spinner`: exact constructors, params, defaults, examples |
| `references/inputs-and-focus.md` | `TextInput`, `TextArea`, `Select<T>`, `ListView`, `DataTable`, `Checkbox`, `Switch`, `Button`, `ScrollBox`; `Focus`/`FocusScope`/`FocusNode`; the key-routing pipeline; `KeyEvent`/`MouseEvent`/`LogicalKeyboardKey`; `PointerListener`; `Shortcuts`/`Actions`/`Intent`s |
| `references/state-and-animation.md` | `StatefulWidget` lifecycle, `setState`, `mounted`; `ChangeNotifier`/`ValueNotifier`; `TextEditingController`; `AnimationController` + `SingleTickerProviderStateMixin`; `InheritedWidget` |
| `references/design.md` | Screen design: 0/1/2-cell spacing, `ThemeData` chrome, catalog-only layout, anti-slop |
| `references/testing.md` | Testing an app through supported package APIs: headless mount/dispose, testable state owners, what noir does *not* export |

## Terminal-specific gotchas

- **Wide characters take 2 cells.** CJK and many emoji occupy two columns. Noir
  handles width internally; use `terminalStringWidth(...)` if you need to
  measure a string yourself before laying it out.
- **The cursor is not part of the character buffer.** `TextInput`/`TextArea`
  render the caret through terminal cursor state rather than a character cell.
  Design tests around controller selection and observable callbacks instead of
  expecting a caret glyph in text output.
- **Mouse reporting is opt-in.** Pass `enableMouse: true` to `runTuiApp` for
  clicks and wheel events. Use the handle's `enableMouse(enableMovement: true)`
  only when the app needs hover, drag, or other pointer-move events. Use
  `MouseEvent.localPosition` for hit logic rather than recomputing absolute
  origins.
- **Headless mode has no renderer.** `runTuiApp(..., headless: true)` mounts the
  widget tree with `isHeadless == true` and no owned terminal renderer, so
  mouse and Kitty keyboard mode controls are unavailable. It is a lifecycle
  seam, not a visual snapshot facility.
- **Shutdown can disturb the scrollback.** On the observed macOS/iTerm path the
  pinned native layer can return to main-screen row 1/column 1 instead of the
  launch cursor and overwrite prior shell rows. This is a known limitation, not
  a reason to skip `dispose()`.

## Boundaries

**This skill covers building applications with noir.** Two adjacent areas it
deliberately does not cover:

- **Changing noir itself** — render objects, the element tree, FFI bindings,
  the compositor, or adding a new core widget. That work is governed by the
  repository's contributor guide and change-workflow entry point at the repo
  root, which own architecture boundaries, authorized verification commands,
  and widget/test rules. Read those instead of extrapolating from this skill.
  One rule that reaches app code too: this is a prerelease, so prefer the
  current API and do not add backwards-compatibility shims.
- **OpenTUI's TypeScript bindings** — `@opentui/react`, `@opentui/core`,
  `@opentui/solid`, JSX elements like `<box>`/`<text>`, Bun or Node projects.
  Those are a separate implementation that shares only the native renderer.
  Nothing in this skill transfers; answer from the TypeScript packages'
  own documentation.
