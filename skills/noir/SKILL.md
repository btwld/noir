---
name: noir
description: >-
  Build terminal user interfaces in Dart with the noir framework — a
  Flutter-like declarative widget system (StatelessWidget/StatefulWidget,
  Row/Column/Container/Expanded, Text/TextStyle, TextInput/TextArea/Select/ScrollBox,
  Focus, setState, AnimationController) that renders through OpenTUI over FFI.
  Use this whenever working with `package:noir`, building or editing TUI apps,
  widgets, examples, or tests in this repo, importing `package:noir/noir.dart`,
  or wiring layout/state/input/animation for a terminal app — even if the user
  only says "terminal UI", "TUI", "CLI interface", or names a widget like Row,
  Column, Container, or Text without saying "noir". For the TypeScript / React /
  Solid OpenTUI bindings instead, use the `opentui` skill, not this one.
metadata:
  references: widgets, inputs-and-focus, state-and-animation, testing
---

# Noir — Flutter-like TUI framework for Dart

Noir uses a Flutter-inspired declarative widget model for the terminal. You
write `Widget` trees; noir lays them out in character cells and paints them
through OpenTUI's native renderer over Dart FFI. Familiar concepts transfer,
but terminal constraints and noir's prerelease contracts differ. Noir signatures
are authoritative.

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
   `EdgeInsets`, and `SizedBox` dimensions are all `int`. A "cell" is one
   monospace character. `Flex.spacing` is a non-negative `int` measured in
   whole cells.
2. **Colors are `0.0–1.0` channels, not `0–255`.** `Color.rgb(0.05, 0.06, 0.1)`
   or named constants like `Color.cyan`. There is no `Color(0xFF...)` ARGB form.
3. **`Container` takes `color` OR `decoration`, never both.** Use `color:` for a
   plain background; use `decoration: BoxDecoration(color:, border:)` when you
   need a border. Passing both is an error.
4. **`runTuiApp(widget)` returns the handle synchronously.** Keep the returned
   `TuiApp` to register `onKey()`, `onMouse()`, or `onPaste()` at app-priority;
   each registration returns an idempotent canceler. `dispose()` is idempotent
   and cancels registrations still owned by the app before unmounting it and
   asking the pinned renderer to restore its terminal session. On the observed
   macOS/iTerm path, shutdown can return to main-screen row 1/column 1 instead
   of the launch cursor and overwrite prior rows. This does not make disposal
   optional. With `headless: true`, `isHeadless` is true and no terminal
   renderer exists, so mouse and Kitty mode controls are unavailable. Native
   capability replies are acquired and consumed before application input.
   Ctrl+C exits by default; to quit programmatically call `app.dispose()` then
   `io.exit(0)`.
5. **Focus-owning and text-editing widgets are controller-driven.** `TextInput`/
   `TextArea` accept `controller` XOR `value` (never both); pass a `FocusNode`
   you own and dispose. See `references/inputs-and-focus.md`.
6. **No backwards-compat shims during prerelease.** Prefer the current API;
   don't add deprecation layers.

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

Run it with `dart run path/to/file.dart`. Inside this repo, the
`example/` directory has runnable references for every major feature
(`hello.dart`, `counter.dart`, `focus_form.dart`, `select_demo.dart`,
`scrollbox_demo.dart`, `textarea_demo.dart`, `pulse_animation.dart`,
`layout_demo.dart`, `widgets_tour.dart`).

## Mental model

- **Widgets declare; Elements preserve identity; RenderObjects lay out and
  paint.** You write widgets. Noir reconciles them into a persistent element
  tree (so `State` survives supported rebuilds) and a render tree that lays out
  in cells and records paint ops for OpenTUI.
- **`StatelessWidget`** = pure `build(context)`. **`StatefulWidget`** = a `State`
  object that persists across rebuilds and calls `setState(...)` to schedule a
  rebuild. These are Flutter-inspired concepts with noir's current lifecycle
  and reconciliation contracts.
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
`Container.foregroundDecoration`. Consult noir's constructors rather than
assuming Flutter API parity.

## Widget catalog (cheat sheet)

| Need | Widget(s) | Reference |
|---|---|---|
| Box with padding/color/border/size | `Container` | `references/widgets.md` |
| Horizontal / vertical layout | `Row`, `Column` (both extend `Flex`) | `references/widgets.md` |
| Share remaining space | `Expanded`, `Flexible` | `references/widgets.md` |
| Fixed gap or size | `SizedBox` | `references/widgets.md` |
| Inset a child | `Padding` | `references/widgets.md` |
| Position a child in a box | `Align` | `references/widgets.md` |
| Constrain min/max | `ConstrainedBox` | `references/widgets.md` |
| Plain or styled text | `Text`, `TextStyle`, `TextStyles` | `references/widgets.md` |
| Mixed-style text runs | `RichText`, `TextSpan` | `references/widgets.md` |
| Border / background paint | `BoxDecoration`, `Border`, `DecoratedBox` | `references/widgets.md` |
| Single-line text field | `TextInput` | `references/inputs-and-focus.md` |
| Multi-line editor | `TextArea` | `references/inputs-and-focus.md` |
| Pick from a list | `Select<T>` | `references/inputs-and-focus.md` |
| Scroll overflowing content | `ScrollBox`, `ScrollController` | `references/inputs-and-focus.md` |
| Keyboard focus | `Focus`, `FocusScope`, `FocusNode` | `references/inputs-and-focus.md` |
| Mouse / pointer | `PointerListener` | `references/inputs-and-focus.md` |
| Keybindings → semantic intents | `Shortcuts`, `Actions`, `Intent` | `references/inputs-and-focus.md` |
| Local mutable state | `StatefulWidget` + `setState` | `references/state-and-animation.md` |
| Observable values | `ChangeNotifier`, `ValueNotifier` | `references/state-and-animation.md` |
| Time-based animation | `AnimationController` + ticker mixin | `references/state-and-animation.md` |
| Share data down the tree | `InheritedWidget` | `references/state-and-animation.md` |

## Common patterns

### Layout: Row / Column / Expanded

`Row` and `Column` are `Flex` with a fixed axis. `mainAxisAlignment` positions
along the axis; `crossAxisAlignment` across it; `spacing` inserts gaps between
children. Wrap a child in `Expanded` to make it absorb leftover main-axis space
(equal `flex` shares split evenly):

```dart
Row(
  spacing: 1,
  children: [
    Expanded(child: _panel('Left', Color.cyan)),
    Expanded(child: _panel('Right', Color.green)),
  ],
)
```

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
`didUpdateWidget`, `deactivate`, and `dispose`, with the `mounted` guard.
Check `mounted` before `setState` in an async callback. Details and disposal
discipline are in `references/state-and-animation.md`.

### Text & styling

`Text(data, style: TextStyle(...))`. `TextStyle` defaults to white foreground;
set `color`, `backgroundColor`, `fontWeight: FontWeight.bold` (also `.dim`),
`fontStyle: FontStyle.italic`, `decoration`, and terminal `effect`s. Reach for
the prebuilt `TextStyles.error` / `.success` / `.muted` / `.bold` constants for
common cases. Full styling surface in `references/widgets.md`.

### Interactive widgets (overview)

`TextInput`, `TextArea`, `Select<T>`, and `ScrollBox` are focus-aware: give each
a `FocusNode` (or `autofocus: true`), and route keys through a `Focus`/
`FocusScope` ancestor. The callback split to remember: `Select.onChanged` fires
as the highlight moves; `Select.onSelect` fires on confirm (Enter/click). Full
constructors, key bindings, and the controller-vs-value rule are in
`references/inputs-and-focus.md`.

## Reference index

Load the file that matches your task — each is self-contained:

| File | Covers |
|---|---|
| `references/widgets.md` | Every layout/text/painting widget: exact constructors, params, defaults, examples (`Container`, `Row`/`Column`/`Flex`, `Expanded`/`Flexible`, `Padding`, `SizedBox`, `Align`, `ConstrainedBox`, `DecoratedBox`, `Text`/`RichText`/`TextSpan`, `TextStyle`/`TextStyles`, `Color`, `BoxDecoration`/`Border`, `EdgeInsets`/`Alignment`/`BoxConstraints`) |
| `references/inputs-and-focus.md` | `TextInput`, `TextArea`, `Select<T>`, `ScrollBox`; `Focus`/`FocusScope`/`FocusNode`; `KeyEvent`/`MouseEvent`/`LogicalKeyboardKey`; `PointerListener`; `Shortcuts`/`Actions`/`Intent`s |
| `references/state-and-animation.md` | `StatefulWidget` lifecycle, `setState`, `mounted`; `ChangeNotifier`/`ValueNotifier`; `TextEditingController`; `AnimationController` + `SingleTickerProviderStateMixin`; `InheritedWidget` |
| `references/testing.md` | Consumer-facing testing through supported package APIs, headless lifecycle checks, and testability patterns |

## Terminal-specific gotchas

- **Wide characters take 2 cells.** CJK and many emoji occupy two columns. Noir
  handles width internally; use `terminalStringWidth(...)` if you need to measure
  a string yourself before laying it out.
- **The cursor is not part of the character buffer.** `TextInput`/`TextArea`
  render the caret through terminal cursor state rather than a character cell.
  Design application-level tests around controller selection and observable
  callbacks instead of expecting a caret glyph in text output.
- **`color` vs `decoration` on `Container`** — see Critical Rule 3.
- **Don't call `io.exit()` mid-frame** without disposing the returned `TuiApp`
  first, or you'll leave the terminal in raw mode. Dispose the app, then exit.

## Working on noir itself (not just building apps with it)

If you're modifying the framework's internals — render objects, the element
tree, FFI bindings, or adding a new core widget — that work is governed by the
development repository's architecture invariants and widget-development rules.
This skill is about *using* noir to build apps, not refactoring its internals.
