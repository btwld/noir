---
name: noir
description: >-
  Build, review, and test Dart terminal applications with package:noir, a
  Flutter-inspired declarative widget framework backed by OpenTUI. Use for
  Noir app and example code involving widget layout, text and styling, themes,
  state, animation, focus, keyboard or mouse input, scrolling, forms, lists,
  tables, lifecycle, hot reload, drive mode, and application-facing tests.
  Trigger on package:noir imports, including package:noir/hooks.dart, or Dart
  TUI work in a Noir project. Do not use for Noir framework internals or the
  TypeScript/React/Solid OpenTUI APIs.
---

# Noir — Flutter-like TUI framework for Dart

Build Noir applications as declarative `Widget` trees. Noir lays them out in
character cells and paints them through OpenTUI's native renderer over Dart
FFI. Transfer Flutter concepts cautiously: terminal constraints and Noir's
prerelease contracts differ. Noir signatures are authoritative; verify them
instead of assuming Flutter API parity.

Import the complete application-authoring surface from one library:

```dart
import 'package:noir/noir.dart';
```

Widget lifecycle hooks are opt-in through `package:noir/hooks.dart`; import it
together with `package:noir/noir.dart` when using `HookWidget` or `use...`
functions.

`package:noir/noir_low_level.dart` is for advanced hosting, renderer/buffer
access, and supported custom render-object protocols. Concrete Element
implementations and the recorder/display-list/compositor backend stay
framework-owned. Raw FFI lives in `package:noir/noir_ffi.dart`; ordinary apps
almost never need the low-level or FFI import.

## Workflow

1. **Confirm the boundary.** Use this skill for application and example code.
   For render objects, Elements, the compositor, FFI, native assets, or a new
   framework widget, follow the repository's contributor workflow instead.
2. **Verify the available version.** In this repository, check `lib/noir.dart`
   and a nearby file in `example/` when a signature matters. In a consumer
   project, check the installed Noir version rather than assuming repository
   head.
3. **Load only the matching reference.** Use the routing table below; do not
   load every reference for a focused task.
4. **Compose from the shipped catalog.** Prefer an existing widget or example
   pattern. Do not invent Flutter or generic-TUI APIs that Noir does not export.
5. **Validate at the right layer.** Test state owners and callbacks directly,
   add a headless lifecycle check when useful, and inspect a drive-mode capture
   for visual or interactive work.

## Reference routing

| Task | Load |
|---|---|
| Layout, geometry, painting, text, themes, and chrome | `references/widgets.md` |
| Fields, lists, tables, scrolling, focus, keys, shortcuts, and pointer input | `references/inputs-and-focus.md` |
| Stateful lifecycle, notifiers, controllers, animation, and inherited data | `references/state-and-animation.md` |
| Opt-in widget lifecycle hooks and effect rules | `../noir-hooks/SKILL.md`, then `../../doc/hooks.md` |
| Screen composition, spacing, palette, and terminal visual review | `references/design.md` |
| Consumer-facing test strategy and supported seams | `references/testing.md` |

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
   widget.** This decides whether your key handler ever fires. Read
   [How a key reaches your code](references/inputs-and-focus.md#how-a-key-reaches-your-code)
   before adding a handler.
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
`image_demo.dart`, `parity_components_demo.dart`, `focus_form.dart`, `select_demo.dart`, `scrollbox_demo.dart`,
`textarea_demo.dart`, `listview_demo.dart`, `components_demo.dart`,
`data_table_demo.dart`, `theme_demo.dart`, `pulse_animation.dart`,
`inherited_example.dart`, `framework_primitives.dart`, `hooks_counter.dart`,
`chat_demo.dart`, `widgets_tour.dart`) — read one before inventing a pattern.

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
| Pixel images | `Image` / `TerminalImage` with negotiated Kitty, Sixel, or block fallback | Protocol support and pixel resolution vary by terminal |
| Gestures (`GestureDetector`) | `PointerListener` + mouse events | Terminal mouse reporting |
| `MediaQuery` | `TerminalCapabilities` / resize callbacks | Terminal size & color support |

Noir provides familiar layout building blocks including `Row`, `Column`,
`Container`, `Padding`, `SizedBox`, `Align`, `Expanded`, `Flexible`,
`ConstrainedBox`, `DecoratedBox`, `Stack`, `Positioned`, `Wrap`, `Text`, and
`RichText`. There is no `GestureDetector`; terminal pointer input is exposed
through `PointerListener` and cell-local `MouseEvent.localPosition`.

## Widget catalog (cheat sheet)

| Need | Widget(s) | Reference |
|---|---|---|
| Box with padding/color/border/size | `Container` | `references/widgets.md` |
| Horizontal / vertical layout | `Row`, `Column` (both extend the abstract `Flex`) | `references/widgets.md` |
| Share remaining space | `Expanded`, `Flexible` | `references/widgets.md` |
| Fixed gap or size | `SizedBox` | `references/widgets.md` |
| Inset a child | `Padding` | `references/widgets.md` |
| Position a child in a box | `Align` | `references/widgets.md` |
| Overlay or absolutely position children | `Stack`, `Positioned` | `references/widgets.md` |
| Flow children into runs | `Wrap` | `references/widgets.md` |
| Constrain min/max | `ConstrainedBox` | `references/widgets.md` |
| Plain or styled text | `Text`, `TextStyle`, `TextStyles` | `references/widgets.md` |
| Mixed-style text runs | `RichText`, `TextSpan` | `references/widgets.md` |
| Multi-row terminal font | `AsciiFont` | `references/widgets.md` |
| Encoded, file, network, or RGBA image | `Image`, `TerminalImage` | `references/widgets.md` |
| Border / background paint | `BoxDecoration`, `Border`, `DecoratedBox` | `references/widgets.md` |
| App-wide color tokens | `Theme`, `ThemeData` | `references/widgets.md` |
| Horizontal / vertical rule | `Divider` | `references/widgets.md` |
| Status tag | `Badge` | `references/widgets.md` |
| Fraction of work | `ProgressBar` | `references/widgets.md` |
| One-cell activity glyph | `Spinner` | `references/widgets.md` |
| Single-line text field | `TextInput` | `references/inputs-and-focus.md` |
| Multi-line editor | `TextArea` | `references/inputs-and-focus.md` |
| Closed set of named options | `Select<T>` | `references/inputs-and-focus.md` |
| Horizontal tabs | `TabSelect<T>` | `references/widgets.md` |
| Controlled numeric track | `Slider` | `references/widgets.md` |
| Windowed builder list | `ListView` | `references/inputs-and-focus.md` |
| Aligned columns + windowed body | `DataTable`, `DataColumn` | `references/inputs-and-focus.md` |
| Static rich-text grid | `TextTable` | `references/widgets.md` |
| Selectable code, diff, or Markdown | `CodeView`, `DiffView`, `MarkdownView` | `references/widgets.md` |
| Two-state mark | `Checkbox` | `references/inputs-and-focus.md` |
| Two-state on/off | `Switch` | `references/inputs-and-focus.md` |
| Push action | `Button` | `references/inputs-and-focus.md` |
| Scroll overflowing content | `ScrollBox`, `ScrollController` | `references/inputs-and-focus.md` |
| Keyboard focus | `Focus`, `FocusScope`, `FocusNode` | `references/inputs-and-focus.md` |
| Mouse / pointer | `PointerListener` | `references/inputs-and-focus.md` |
| Keybindings → semantic intents | `Shortcuts`, `Actions`, `Intent` | `references/inputs-and-focus.md` |
| Local mutable state | `StatefulWidget` + `setState` | `references/state-and-animation.md` |
| Reusable lifecycle state | `HookWidget` and `use...` from `package:noir/hooks.dart` | `../../doc/hooks.md` |
| Observable values | `ChangeNotifier`, `ValueNotifier` | `references/state-and-animation.md` |
| Editable text + cursor | `TextEditingController` | `references/state-and-animation.md` |
| Time-based animation | `AnimationController` + ticker mixin | `references/state-and-animation.md` |
| Share data down the tree | `InheritedWidget` | `references/state-and-animation.md` |

## Application invariants

- Use `Row` and `Column` as the concrete `Flex` widgets. Add `Expanded` only
  where a child should consume remaining space, and set
  `crossAxisAlignment: CrossAxisAlignment.stretch` for full-bleed regions.
- Let Tab and Shift+Tab traverse focus. Do not intercept Tab unless a custom
  policy is intentional. Avoid bare-letter `app.onKey` bindings because they
  run before a focused text field; prefer modified or scoped `Shortcuts`.
- Use the current `State` hooks: `initState`, `didChangeDependencies`,
  `didUpdateWidget`, `deactivate`, `reassemble`, and `dispose`. Guard async
  callbacks with `mounted` before calling `setState`.
- Resolve chrome through `Theme.of(context)` and `ThemeData` tokens. For
  `ListView`, omit `selectedIndex` for plain scrolling; use it only when the
  list owns a selection highlight.
- Give focus-aware fields and controls a `FocusNode` or `autofocus: true`.
  Pass a `TextEditingController` when code must read or mutate text; do not
  pass both `controller` and `value`.
- Read the routed reference for exact constructors, defaults, callback timing,
  and key bindings before producing non-trivial code.

## Hot reload during development

Noir apps hot reload through the VM service, in two steps a driver performs
for you: `reloadSources` swaps edited code, then the `ext.noir.reassemble`
extension rebuilds the live tree. `runTuiApp` registers that extension
automatically:

```dart
void main() => runTuiApp(const MyApp());
```

`registerHotReloadExtension` stays exported for custom hosts that do not
go through `runTuiApp`.

Run an app through Noir's packaged development command and save a `.dart` file
under `lib/` or beside the entry point to reload:

```sh
dart run noir:run example/counter.dart
```

The command is available to package consumers as `dart run noir:run`; replace
the example path with the consuming package's entry point. It inherits the
app's terminal streams and writes its own diagnostics to
`.dart_tool/noir/run.log`, keeping them out of the alternate-screen UI. A
compile error leaves the last good app running, and the next valid save retries
the reload. Arguments after the entry point pass through unchanged.

For a custom driver, call `reloadSources` and then the extension — for instance
use `package:hotreloader` with
`onAfterReload: (_) => app.reassemble()`. `app.reassemble()` invokes
`State.reassemble()` on every retained state, then re-runs every `build()` and
forces a full layout and paint pass; `State`, focus, scroll, and animation
values survive, and no terminal or native resource is recreated. `main()` and
`initState` of already-mounted state are not re-run — override
`State.reassemble()` to re-derive what those `initState` bodies computed. Other
changes the VM cannot swap still need a restart: signatures held by live stack
frames, enum-to-class conversions, and the native OpenTUI library.

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
`key <name>`, `type <text>`, `click <x> <y>`,
`scroll <up|down|left|right> <x> <y>`, `resize <WxH>`, `reload` (hot reload +
reassemble), and `watch on|off`. Set the CLI launch size with `--size 80x24`;
the client passes that geometry to the app through `NOIR_DRIVE_SIZE`. Use
`resize <WxH>` to change it during a session. Viewing an app at several sizes
this way is how layout problems at small terminals get caught early.

Outside the repo the extension surface still activates, but the CLI and the
`NoirDriver` client are not part of the published package, and the surface is
development tooling rather than stable API. Drive mode is for looking at and
driving a live app; automated assertions belong in ordinary tests
(`references/testing.md`).

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
- **Image ownership depends on the constructor.** `Image(image: decoded)`
  borrows the `TerminalImage`; the caller disposes it. `Image.memory`,
  `Image.rgba`, `Image.file`, and `Image.network` own and dispose decoded
  results. Drive mode validates layout and deterministic block fallback, but
  cannot prove that a real terminal renders Kitty or Sixel escape output.
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
