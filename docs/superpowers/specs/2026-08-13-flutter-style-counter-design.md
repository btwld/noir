# Flutter-style counter example

## Context and selected direction

The existing `example/counter.dart` proves `StatefulWidget`, `setState`, and
parsed keyboard input, but it reads as a small bordered diagnostics panel. The
replacement must look and behave like one composed application: a full-width
app bar, a centered counter body, and a visually distinct action button at the
bottom-right. It must remain an idiomatic Noir example rather than imitate
Flutter APIs that Noir does not provide.

Three approaches were considered:

1. **Full-screen scaffold analogue (selected):** compose a light application
   surface, blue app bar, centered body, and bottom-right floating-action-style
   button from Noir's supported layout and pointer widgets. This most closely
   preserves the hierarchy and visual rhythm of Flutter's generated counter.
2. **Centered card:** restyle the existing bordered panel and place a button
   inside it. This is smaller, but it still reads as a widget sample instead of
   a complete UI.
3. **Expanded controls showcase:** add decrement/reset buttons, animation, and
   hover behavior. This would dilute the counter's `setState` lesson, duplicate
   other examples, and diverge from Flutter's single-action template.

The selected approach replaces the existing counter entrypoint. It does not
add a second catalog item or a new framework widget.

## Visual contract

At the ordinary 64x18 validation size, the composition is:

```text
+--------------------------------------------------------------+
|  Noir Counter                                                | blue app bar
+--------------------------------------------------------------+
|                                                              |
|                 You have pushed the button                   |
|                       this many times:                       |
|                              0                               |
|                                                              |
|  Up/+ add | Down/- subtract | Enter/Space | Ctrl+C   ███████ |
|                                                      ███+███ |
|                                                      ███████ |
+--------------------------------------------------------------+
```

The ASCII outline above describes placement, not literal outer borders, and
the block run represents blue background cells rather than rendered glyphs.
The rendered app uses these terminal-native equivalents of Material styling:

- Root surface: full-frame warm white (`#FAFAFA`).
- App bar: one flat Material-like blue (`#1976D2`) surface, three rows high,
  with a vertically centered, left-aligned bold white `Noir Counter` title.
- Body: an `Expanded` region with the standard counter sentence and current
  value centered as a single visual group.
- Counter value: bold blue text with surrounding whitespace for hierarchy;
  Noir has no font-size axis, so weight, color, and spacing replace Flutter's
  `headlineMedium` scale.
- Action area: a muted one-line keyboard hint on the left and a 7x3 blue
  increment surface on the right, separated from the terminal edges by two
  horizontal cells and one bottom row.
- Action surface: one solid 7x3 blue body with a centered white bold `+` and no
  box-drawing outline.

Noir's `BoxShape.circle` does not paint a circular body, and terminal cells
cannot reproduce Material elevation or a true circle. The design therefore
uses coherent palette, hierarchy, spacing, bottom-right placement, and a 7x3
filled region that reads approximately square at the observed terminal cell
ratio rather than claiming unsupported pixel geometry.

## Widget composition and ownership

`CounterApp` remains a `StatefulWidget`, and `_CounterAppState` remains the
single owner of the integer count.

The tree uses only `package:noir/noir.dart`:

- `Focus` owns the keyboard interaction boundary.
- A root `Container` paints the application surface.
- `Column` divides the app bar, expanded body, and bottom action area.
- `Expanded` plus `Align` centers the body independently of terminal height.
- `Row` keeps the muted control hint and action surface in one bottom region.
- A private stateless `_IncrementButton` composes `PointerListener`,
  `Container`, `Align`, and `Text`.

The button receives a callback; it does not reach into the parent's state.
Its pointer handler accepts only `MouseButton.left` and uses the listener's
normal render-tree hit testing. No widget calls FFI or receives a `Buffer`.

`main()` retains the `TuiApp` returned by `runTuiApp`, calls
`app.enableMouse()` exactly once for click reporting, and preserves
`registerHotReloadExtension(app)`. Pointer movement remains disabled because
the UI has no hover or drag behavior. Ctrl+C remains the framework-owned clean
exit path.

## Interaction contract

Every increment route calls one `_incrementCounter()` method and therefore one
`setState` transition:

- Up arrow
- `+`
- Enter
- Space
- left-click anywhere inside the solid increment surface

Down arrow and `-` call one `_decrementCounter()` method. Key releases are
ignored, unrelated keys bubble, and middle/right clicks do not change state.

There is no editable field, so the example does not synthesize a text caret or
change cursor style. The visible action surface and its keyboard bindings are
the relevant terminal interaction affordances.

## Review repairs included in this slice

The full-diff review found no Critical or Important issue, but identified two
test-quality gaps that this work closes:

1. `test/example/counter_test.dart` currently treats a non-black foreground at
   absolute cell `(0, 0)` as evidence for a visible border. The replacement
   assertions locate the title, counter, hint, and `+` glyph, then verify their
   exact colors/styles and relative regions. No assertion depends on an
   unrelated absolute corner.
2. The inherited-theme example's color test can pass through ordinary subtree
   reconciliation even if inherited notification stops. A small stateful
   dependent will cache its derived theme only in `didChangeDependencies` and
   render a visible dependency-update count. After `t`, the test must observe
   the second dependency update and the derived forest style. Ordinary parent
   rebuilding alone cannot satisfy that assertion.

The inherited repair preserves the existing ocean/forest interaction and
keeps the framework implementation unchanged.

## Automated verification

`test/example/counter_test.dart` will cover:

1. Initial visual hierarchy at 64x18, including app-bar position and exact
   foreground/background/style cells.
2. Centered body placement and bottom-right action placement by comparing the
   located text coordinates with the captured frame dimensions.
3. Existing Up/Down and `+`/`-` behavior.
4. Enter and Space activation.
5. Left-click activation at the located `+` cell and ignored right-click.
6. Real-entrypoint mouse enablement without movement reports.
7. Safe rendering at a compact terminal size without requiring every optional
   hint character to remain visible.

`test/example/static_examples_test.dart` will assert the visible
`didChangeDependencies`-backed update as well as the inherited foreground and
background transition.

The implementation follows red/green order: strengthen each focused test,
observe the intended failure against the old example, then make the smallest
application change that satisfies it.

## Documentation and evidence

The counter descriptions in `README.md`, `example/README.md`, and
`CHANGELOG.md` will describe the composed visual layout and mouse/keyboard
controls. `TODO.md` will be updated only after the exact full-suite count and
post-change review/terminal evidence are known.

No second counter file is added. No public API, native binding, ABI, bundled
asset, OpenTUI gitlink, workflow, tag, release, or publication surface changes.

## VS Code visual acceptance

After automated checks pass, Computer Use will operate the already-open VS
Code integrated terminal and run `dart run example/counter.dart`.

The visual pass must:

1. Capture the initial full application showing the flat blue app bar, centered
   zero, light body, bottom hint, and solid blue action surface.
2. Activate the action by keyboard and by a real click inside the surface,
   confirming exactly one increment for each action.
3. Exercise Up, Down, `+`, `-`, Enter, and Space and observe the expected count.
4. Capture an incremented frame.
5. Send Ctrl+C and confirm the integrated terminal returns to a usable shell
   without a stack trace.

Screenshots are validation artifacts, not package sources; they remain under
the gitignored `.context` workspace or are returned directly to the user.

## Acceptance criteria

The change is complete only when:

- the rendered counter reads as one Flutter-inspired application at a glance;
- every advertised input path is behaviorally covered;
- color and bold styling are asserted through captured buffer sidecars;
- the inherited example test genuinely depends on inherited notification;
- focused, architecture, and full package checks pass;
- an independent reviewer reports no unresolved Critical or Important
  finding;
- the requested VS Code screenshots and interaction evidence are captured;
- the worktree and PR contain only coherent, reviewed changes.
