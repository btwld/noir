# Test helpers

There are four different ways to mount a widget for testing in this project.
They serve different purposes and **should not be unified** — pick the right
one for your test.
This file is repository-contributor-only; its private helpers are
not package-consumer API.

| Helper | Purpose | When to use |
|---|---|---|
| `tester.pumpWidget(...)` (`widget_tester.dart`) | Mounts an element tree and runs layout. Doesn't paint. | Asserting on `width`, `height`, child positions, or other layout-math results. |
| `capture.capture(...)` (`buffer_capture.dart`) | Preferred direct single-frame capture into a real OpenTUI `Buffer`, returning a `CapturedBuffer` containing a `CapturedCursor`. | Asserting on rendered output: characters, colours, attributes, cursor position. Used by a golden tester. |
| `KeyDriver` (`key_driver.dart`) | Wraps a headless `TuiBinding` and lets you send synthetic `KeyEvent` / `MouseEvent` through `InputManager`. | Behavioural tests for input handling — focus, keyboard shortcuts, mouse clicks. |
| `createTuiTestApp` (`tui_test_app.dart`) | Runs the repository-only `runTuiAppForTesting` path with a real `TuiBinding`, `StdinInputDriver`, scheduler frame pump, and byte-level input mocks. | End-to-end app/event-loop tests where ANSI parsing, resize propagation, frame scheduling, or shutdown behavior matters. |

**Drive mode is not a fifth harness.** `NOIR_DRIVE=1` plus
`scripts/noir_drive.dart` drives a *live app process*: it mounts nothing here.
Inside that process it reuses exactly the `createTuiTestApp` composition —
headless binding, injected testing renderer, and `StdinInputDriver` bytes — so
there is nothing to unify. Use it to look at or script a running app; use the
four harnesses above to test widget behavior. See `CONTRIBUTING.md`.

## Instance lifecycles

```dart
final tester = WidgetTester();
try {
  tester.pumpWidget(widget);
} finally { tester.dispose(); }

final capture = BufferCapture();
try {
  final captured = capture.capture(widget);
} finally { capture.dispose(); }

final golden = GoldenTester();
try {
  await golden.expectGolden(widget, name);
} finally { golden.dispose(); }
```

## Golden tests (`GoldenTester`)

A constructed golden tester writes / compares three visual files
under `test/goldens/`:

- `<name>.buffer.txt` — character grid, always written.
- `<name>.styles.txt` — per-cell foreground / background / attributes
  (RLE-encoded, only non-default cells listed). Written by default; opt
  out with `expectGolden(..., captureStyles: false)`.
- `<name>.cursor.txt` — cursor visibility + position + style. Written by
  default; opt out with `expectGolden(..., captureCursor: false)`.

Set `UPDATE_GOLDENS=1` in the environment to regenerate goldens instead of
comparing against them. Missing sidecars without `UPDATE_GOLDENS=1` are a
hard failure pointing you to the updater command.

## Behavioural tests (`KeyDriver`)

```dart
final driver = KeyDriver(MyWidget(autofocus: true));
await driver.ready();
await driver.sendLogicalKey(LogicalKeyboardKey.arrowDown);
await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
driver.dispose();
```

`KeyDriver` covers the post-ANSI-parser path — it injects parsed
`KeyEvent`s directly into `InputManager`. It does **not** exercise the byte
parser (escape sequences, mouse SGR, Kitty keyboard). Use `createTuiTestApp`
when the parser path is part of the behavior under test.

## Integration tests (`createTuiTestApp`)

```dart
final app = createTuiTestApp(MyWidget(autofocus: true));
app.pumpFrame();
app.mockInput.typeText('hello');
app.mockMouse.click(10, 5);
final captured = app.captureFrame();
app.dispose();
```

`createTuiTestApp` covers the full advanced binding path: `runTuiAppForTesting`, scheduler
frames, `StdinInputDriver` byte parsing, `InputDispatcher`, render layout,
paint, and captured buffer reads. It is the right harness for app/event-loop
tests and parser round-trips; keep `KeyDriver` for focused synthetic input
tests that do not need byte parsing.
`TuiTestApp.captureFrame()` is integration-path capture after those
interactions and includes style and cursor state.

## Matchers (`BufferMatchers`)

When asserting against a `CapturedBuffer`:

```dart
expect(captured, BufferMatchers.hasCharAt(0, 0, 'A'));
expect(captured, BufferMatchers.hasColorAt(5, 0, Color.yellow));
expect(captured, BufferMatchers.hasBackgroundAt(0, 1, const Color(0.2, 0.4, 0.8)));
expect(captured, BufferMatchers.cursorAt(3, 0));     // visibility + coords
```

Or read fields off the captured object directly:

```dart
final fg = captured.getForegroundColor(0, 0);
final attr = captured.getCell(0, 0).attributes;
final cursor = captured.cursor;        // CapturedCursor
```

## Known testing gaps

- **No pseudo-TTY harness.** `createTuiTestApp` feeds bytes into the same
  parser used by production stdin, but it does not allocate an OS pseudo-TTY.
- **No ANSI-byte snapshot.** `Renderer.render()`'s actual byte output isn't
  captured, so cross-platform escape-sequence drift is invisible.
- **Cursor goldens are point-in-time.** They reflect controller state at
  the end of paint. Multi-frame interactions (cursor blink) aren't tested.
