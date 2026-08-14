# Flutter-style Counter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Noir's diagnostic counter panel with the approved full-screen Flutter-inspired counter, prove every keyboard and pointer route, and repair the inherited-example test so it genuinely depends on `didChangeDependencies` notification.

**Architecture:** Keep `_CounterAppState` as the only counter-state owner, express the UI entirely with supported `package:noir/noir.dart` widgets, and route keyboard and pointer activation into the same private state methods. Keep inherited theme derivation in a stateful dependent's `didChangeDependencies`, so an ordinary parent rebuild cannot fabricate the visible notification count. The work stays above FFI, rendering, compositor, native, and OpenTUI ownership boundaries.

**Tech Stack:** Dart 3, Noir widgets and parser-backed input, `package:test`, `createTuiTestApp`, `MockInput`, `MockMouse`, `CapturedBuffer`/`BufferMatchers`, VS Code's integrated terminal, and Git.

## Global Constraints

- Work only in `/Users/leofarias/conductor/workspaces/noir/trenton` on the current branch; do not rename it.
- Treat `origin/main` as the comparison/base branch and preserve unrelated user changes.
- The approved contract is `docs/superpowers/specs/2026-08-13-flutter-style-counter-design.md` at baseline commit `c08d52e`.
- Baseline evidence before the implementation is `dart test --concurrency=1`: 1,253 tests passed.
- Replace `example/counter.dart`; do not add a second counter or a new public framework widget.
- Widgets remain declarative; Elements retain identity; RenderObjects own layout/paint; widgets never call FFI or receive a `Buffer`.
- Import only `package:noir/noir.dart` from the examples.
- Do not edit or advance `external/opentui`, rebuild native libraries, change the ABI, manifest, hashes, bundled assets, workflow behavior, tag, release, visibility, or publication state.
- Use only the existing test harnesses. Counter behavior uses `createTuiTestApp`, parser-backed `mockInput`/`mockMouse`, and cell assertions through `CapturedBuffer`/`BufferMatchers`.
- Begin each production behavior change with a focused failing test, verify that it fails for the intended behavioral reason, then implement the smallest coherent fix.
- Use `apply_patch` for source edits and format touched Dart files before committing.
- `main()` must retain the `TuiApp`, call `app.enableMouse()` exactly once without movement reporting, and preserve `registerHotReloadExtension(app)`.
- The click surface handles only left-button down events. Releases, middle/right clicks, unrelated keys, and key releases do not mutate the counter.
- Do not claim a true circle, elevation, or `BoxShape.circle`; use a rectangular 7x3 surface and the approved rounded box-drawing table.
- Do not update the ordinary-test count or manual evidence in `TODO.md` until it comes from the exact assembled and reviewed tree.
- Final completion requires the requested VS Code screenshots, an independent behavior/full-diff review with no unresolved Critical or Important finding, and every authorized release gate.

---

## File Structure Map

| Responsibility | Files |
| --- | --- |
| Counter behavior and composition | `example/counter.dart` |
| Counter visual/input regressions | `test/example/counter_test.dart` |
| Inherited-notification evidence | `example/inherited_example.dart`, `test/example/static_examples_test.dart` |
| User-facing example contract | `README.md`, `example/README.md`, `CHANGELOG.md` |
| Exact reviewed-tree evidence | `TODO.md` |
| Visual artifacts | `.context/flutter-counter/` (gitignored) |

---

### Task 1: Lock the Counter Visual and Interaction Contract

**Files:**

- Modify: `test/example/counter_test.dart`

**Interfaces:**

- Consumes: `CounterApp`, `createTuiTestApp`, `MockInput`, `MockMouse`, `CapturedBuffer`, and the real `example/counter.dart` source.
- Produces: five focused example tests covering 64x18 styling/placement, keyboard behavior, pointer behavior, entrypoint mouse setup, and compact rendering.

- [ ] **Step 1: Replace the brittle visual test with located cell assertions**

Add `dart:io` as `io` and define test colors with `Color.fromHex`. Render at exactly 64x18, locate `Noir Counter`, both body lines, `0`, the hint, and the right-side `+`, then assert:

```dart
final title = frame.findText('Noir Counter').single;
final firstLine = frame.findText('You have pushed the button').single;
final secondLine = frame.findText('this many times:').single;
final count = frame.findText('0').single;
final hint = frame.findText('Up/+ add').single;
final increment = frame
    .findText('+')
    .where((position) => position.x > frame.width ~/ 2)
    .single;

expect(title.x, 2);
expect(title.y, lessThan(firstLine.y));
expect(frame.getForegroundColor(title.x, title.y), Color.white);
expect(frame.getBackgroundColor(title.x, title.y), _materialBlue);
expect(frame.getCell(title.x, title.y).isBold, isTrue);
expect(frame.getChar(0, 2), '─');
expect(frame.getForegroundColor(0, 2), _darkMaterialBlue);
expect(frame.getBackgroundColor(0, 3), _surface);

expect(firstLine.x, (frame.width - 'You have pushed the button'.length) ~/ 2);
expect(secondLine.x, (frame.width - 'this many times:'.length) ~/ 2);
expect(count.x, frame.width ~/ 2);
expect(count.y, greaterThan(secondLine.y));
expect(frame.getForegroundColor(count.x, count.y), _materialBlue);
expect(frame.getCell(count.x, count.y).isBold, isTrue);

expect(hint.y, greaterThan(count.y));
expect(frame.getForegroundColor(hint.x, hint.y), _mutedText);
expect(increment.x, greaterThanOrEqualTo(frame.width - 8));
expect(increment.y, greaterThanOrEqualTo(frame.height - 4));
expect(increment.y, lessThan(frame.height - 1));
expect(frame.getForegroundColor(increment.x, increment.y), Color.white);
expect(frame.getBackgroundColor(increment.x, increment.y), _materialBlue);
expect(frame.getCell(increment.x, increment.y).isBold, isTrue);
expect(frame.getChar(increment.x - 3, increment.y - 1), '╭');
expect(frame.getChar(increment.x + 3, increment.y - 1), '╮');
expect(frame.getChar(increment.x - 3, increment.y + 1), '╰');
expect(frame.getChar(increment.x + 3, increment.y + 1), '╯');
expect(frame.getBackgroundColor(0, frame.height - 1), _surface);
```

Also assert the complete one-line hint text `Up/+ add | Down/- subtract | Enter/Space | Ctrl+C` is present.

- [ ] **Step 2: Expand parsed keyboard coverage**

Keep one stateful app alive and prove this sequence after autofocus settles:

```text
0 --Up--> 1 --+--> 2 --Enter--> 3 --Space--> 4
  --Down--> 3 ----> 2 --x/release--> 2
```

Use `pressEnter()`, `typeText(' ')`, and `pressKittyKey(43, eventType: 3)` for the release report. Locate the count through the full body frame after every input rather than inspecting private state.

- [ ] **Step 3: Add parser-backed pointer coverage**

Locate the right-side `+` cell from the captured frame. Use `pressDown` and `release` separately to prove left-button down increments exactly once and release does not increment. Then send right and middle clicks at the same cell and prove both are ignored.

- [ ] **Step 4: Add real-entrypoint source and compact-layout tests**

Read `example/counter.dart` and assert `app.enableMouse();` occurs exactly once, `enableMouse(enableMovement: true)` is absent, and `registerHotReloadExtension(app);` remains present. Render `CounterApp` at 32x12, pump without exception, and require the title, centered count, and right-side `+` to survive even though the long optional hint may clip.

- [ ] **Step 5: Run the counter test and confirm the intended red state**

Run:

```bash
dart test test/example/counter_test.dart --concurrency=1
```

Expected: FAIL against the old diagnostics panel because it lacks `Noir Counter`, the light/blue visual hierarchy, Enter/Space activation, pointer activation, `enableMouse()`, and the rounded bottom-right surface. Confirm failures are behavioral assertions, not syntax, imports, or harness setup.

---

### Task 2: Build the Flutter-inspired Counter Application

**Files:**

- Modify: `example/counter.dart`

**Interfaces:**

- Preserves: `CounterApp`, `main()`, and hot-reload registration.
- Adds privately: `_incrementCounter()`, `_decrementCounter()`, and stateless `_IncrementButton` with a `VoidCallback onPressed`.
- Produces: the exact keyboard and pointer behavior specified in the approved design.

- [ ] **Step 1: Define readable Material-inspired palette and border constants**

Use private top-level values so example and output intent remain obvious:

```dart
final _surfaceColor = Color.fromHex('#FAFAFA');
final _materialBlue = Color.fromHex('#1976D2');
final _darkMaterialBlue = Color.fromHex('#0D47A1');
final _bodyTextColor = Color.fromHex('#424242');
final _mutedTextColor = Color.fromHex('#616161');

const _roundedBorderCharacters = <int>[
  0x256D, 0x256E, 0x2570, 0x256F,
  0x2500, 0x2502, 0x252C, 0x2534,
  0x251C, 0x2524, 0x253C,
];
```

- [ ] **Step 2: Centralize state transitions and broaden keyboard activation**

Add `_incrementCounter()` and `_decrementCounter()` methods, each containing one `setState`. In `_handleKey`, return ignored immediately for non-press events. Treat Up/`+`/Enter/Space as increment, Down/`-` as decrement, and return ignored for everything else.

- [ ] **Step 3: Compose the full-frame scaffold analogue**

Build:

```text
Focus(autofocus)
└─ Container(color #FAFAFA)
   └─ Column(stretch)
      ├─ SizedBox(height: 3)
      │  └─ Container(blue, dark bottom border, horizontal padding 2)
      │     └─ Align(centerLeft, bold white "Noir Counter")
      ├─ Expanded
      │  └─ Align(center)
      │     └─ Column(min) with two sentence lines, one spacer, bold blue count
      └─ Padding(left/right 2, bottom 1)
         └─ Row
            ├─ Expanded(muted one-line hint)
            ├─ SizedBox(width: 1)
            └─ _IncrementButton(onPressed: _incrementCounter)
```

Use `CrossAxisAlignment.stretch` for the root column, `Align` for app-bar/body positioning, and the exact hint `Up/+ add | Down/- subtract | Enter/Space | Ctrl+C`.

- [ ] **Step 4: Implement the private stateless action surface**

`_IncrementButton` accepts `VoidCallback onPressed`. Its private pointer handler calls the callback only when `event.button == MouseButton.left`. Build a `PointerListener(onPointerDown: ...)` around a `SizedBox(width: 7, height: 3)` and a blue `Container` with `Border.all(color: _materialBlue, borderChars: _roundedBorderCharacters)`, centered bold white `+`. Do not register pointer-up/move callbacks and do not use `BoxShape.circle`.

- [ ] **Step 5: Enable renderer-backed clicks in the real entrypoint**

Immediately after `runTuiApp`, call `app.enableMouse();` exactly once. Keep movement reporting disabled by default and preserve the existing hot-reload comments and `registerHotReloadExtension(app)` call.

- [ ] **Step 6: Format and turn the counter suite green**

Run:

```bash
dart format example/counter.dart test/example/counter_test.dart
dart test test/example/counter_test.dart --concurrency=1
dart analyze --fatal-infos
```

Expected: all five counter tests pass and focused analysis reports no issue. If a cell coordinate differs because of real terminal-cell layout, inspect the captured frame and adjust composition or assertions to preserve the design's semantic regions; do not weaken exact color/style or input assertions.

- [ ] **Step 7: Review and commit the coherent counter slice**

Inspect `git diff -- example/counter.dart test/example/counter_test.dart`, confirm there is no second counter, FFI use, public API growth, or unsupported shape claim, then commit:

```bash
git add example/counter.dart test/example/counter_test.dart
git commit -m "feat(examples): redesign counter as Flutter-style app"
```

---

### Task 3: Prove Inherited Dependency Notification

**Files:**

- Modify: `test/example/static_examples_test.dart`
- Modify: `example/inherited_example.dart`

**Interfaces:**

- Preserves: `ThemeData`, `ThemedText`, `ThemedApp`, and the `t` palette toggle.
- Adds privately: `_ThemeDependencyStatus` and its state, with cached derived color and visible notification count.

- [ ] **Step 1: Strengthen the existing static example test first**

Before `t`, locate `Dependency updates: 1`, assert its foreground is `Color.white`, and retain the ocean background assertions. After `t`, require `Dependency updates: 2`, assert its foreground is `Color.yellow`, and retain the normalized forest background assertion. The visible count is the proof that notification reached the dependent; ordinary reconciliation alone cannot change it.

- [ ] **Step 2: Run the inherited test and confirm the intended red state**

Run:

```bash
dart test test/example/static_examples_test.dart --concurrency=1 --name 'inherited theme'
```

Expected: FAIL because the old example has no `didChangeDependencies`-backed status line. Confirm the failure is the missing `Dependency updates: 1`, not the existing palette behavior.

- [ ] **Step 3: Implement the stateful dependency observer**

Add a private stateful child to the themed column. Its state must derive only inside `didChangeDependencies`:

```dart
class _ThemeDependencyStatusState extends State<_ThemeDependencyStatus> {
  late Color _derivedTextColor;
  var _dependencyUpdates = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _derivedTextColor = ThemeData.of(context).textColor;
    _dependencyUpdates++;
  }

  @override
  Widget build(BuildContext context) => Text(
    'Dependency updates: $_dependencyUpdates',
    style: TextStyle(color: _derivedTextColor),
  );
}
```

The `build` method must not call `ThemeData.of`; it renders only the cached value and count. Add `const _ThemeDependencyStatus()` to the existing themed column without changing the ocean/forest values.

- [ ] **Step 4: Format and turn inherited coverage green**

Run:

```bash
dart format example/inherited_example.dart test/example/static_examples_test.dart
dart test test/example/static_examples_test.dart test/inherited_widget_test.dart --concurrency=1
dart analyze --fatal-infos
```

Expected: all focused example and framework inherited tests pass; the visible count moves from 1 to 2 and forest styling is derived from the notified dependency.

- [ ] **Step 5: Review and commit the inherited-evidence slice**

Inspect the focused diff and confirm the dependent owns only cached presentation state, registers only in `didChangeDependencies`, and changes no framework implementation. Commit:

```bash
git add example/inherited_example.dart test/example/static_examples_test.dart
git commit -m "test(examples): prove inherited dependency notifications"
```

---

### Task 4: Align Documentation With Shipped Behavior

**Files:**

- Modify: `README.md`
- Modify: `example/README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update the README counter snippet and catalog**

Make the main snippet show the same centralized increment/decrement keyboard routes, light full-screen `Column` structure, and `enableMouse()` entrypoint behavior as the actual example without pretending to include every private styling constant. Change the catalog summary to mention the Flutter-inspired app bar/body/action layout plus Up/Down, `+`/`-`, Enter/Space, and click controls.

- [ ] **Step 2: Update the example catalog and changelog**

Describe `counter.dart` as a composed Flutter-inspired full-screen stateful app with keyboard and clickable increment routes. Update the changelog's old keyboard-only bullet to include the rounded action surface, parser-backed click, Enter, and Space while retaining Ctrl+C cleanup wording.

- [ ] **Step 3: Check documentation references and commit**

Run:

```bash
rg -n "counter|Counter|keyboard-driven|Up/Down" README.md example/README.md CHANGELOG.md
dart test test/architecture/package_distribution_ownership_test.dart --concurrency=1
git diff --check
```

Confirm no stale keyboard-only claim remains, links still name the replaced `example/counter.dart`, and no second example was advertised. Commit:

```bash
git add README.md example/README.md CHANGELOG.md
git commit -m "docs: describe Flutter-style counter interactions"
```

---

### Task 5: Verify the Visual Application in VS Code

**Files:**

- Create (gitignored evidence): `.context/flutter-counter/initial.png`
- Create (gitignored evidence): `.context/flutter-counter/incremented.png`

- [ ] **Step 1: Open and size the integrated terminal through Computer Use**

Use the Computer Use skill's `node_repl` and `@oai/sky` only. Inspect the current VS Code state, focus the already-open integrated terminal, clear it if needed, and size the visible terminal sufficiently to show the full composition. Do not use shell-driven UI automation.

- [ ] **Step 2: Run the real example and capture the initial frame**

Type `dart run example/counter.dart` into the integrated terminal. Wait for the 0 frame, inspect it visually for the blue three-row app bar, warm-white body, centered sentence/count, bottom hint, and rounded bottom-right action. Save/return a screenshot as `.context/flutter-counter/initial.png`.

- [ ] **Step 3: Exercise every real input path**

Send Up, Down, `+`, `-`, Enter, and Space through VS Code and observe the expected one-step count changes. Click inside the visible rounded `+` surface with a real left click and confirm exactly one increment. The automated parser-backed test remains the precise evidence for ignored right/middle/release behavior.

- [ ] **Step 4: Capture an incremented frame and cleanly stop**

Leave a nonzero value visible and save/return `.context/flutter-counter/incremented.png`. Send Ctrl+C, wait for the integrated terminal to return to a usable shell, and verify there is no stack trace or terminal corruption.

---

### Task 6: Assemble, Review, and Run Every Release Gate

**Files:**

- Modify only after exact evidence exists: `TODO.md`

- [ ] **Step 1: Run focused and architecture checks on the assembled code**

Run:

```bash
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ scripts/
dart analyze --fatal-infos
dart test test/example/counter_test.dart test/example/static_examples_test.dart test/inherited_widget_test.dart --concurrency=1
dart test test/architecture/ --concurrency=1
```

- [ ] **Step 2: Obtain independent behavior and full-diff review**

Give the independent reviewer the approved design, implementation plan, complete `origin/main...HEAD` diff, baseline evidence, focused results, and VS Code artifacts. Ask specifically about interaction completeness, exact visual assertions, inherited-notification validity, layout safety, ownership boundaries, documentation drift, and accidental scope expansion. Resolve every Critical or Important finding; assess and either fix or explicitly document lower-severity findings. Rerun affected checks after any change.

- [ ] **Step 3: Run the full ordinary suite and record its exact count**

Run fresh:

```bash
dart test --concurrency=1
```

Record the final reported count from the exact reviewed tree. Do not infer it from the number of edited `test()` declarations.

- [ ] **Step 4: Run remaining package gates**

Run:

```bash
dart run scripts/fetch_opentui_binaries.dart --verify-only
dart pub publish --dry-run
git diff --check
git status --short
git diff --stat origin/main...
```

Expected: six bundled binaries plus the manifest verify, publish dry-run has zero warnings, whitespace checks pass, and only the approved coherent slice differs from `origin/main`.

- [ ] **Step 5: Update exact reviewed-tree evidence in TODO**

Only now update `TODO.md` with the final ordinary-test count, the two VS Code screenshot/interaction observations, the real clickable action, clean Ctrl+C return, and independent-review result. Preserve all unrelated release limitations and authorization boundaries.

- [ ] **Step 6: Re-run gates affected by the evidence-only edit**

Run at minimum:

```bash
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ scripts/
dart analyze --fatal-infos
dart test test/architecture/ --concurrency=1
dart test --concurrency=1
dart run scripts/fetch_opentui_binaries.dart --verify-only
dart pub publish --dry-run
git diff --check
```

The final full-suite count must match the value recorded in `TODO.md`.

- [ ] **Step 7: Final diff review and evidence commit**

Inspect `git diff origin/main...`, confirm the attached design and this plan are included, screenshots stay gitignored, no protected dependency/native surface changed, and there are no unresolved review findings. Commit the evidence-only update with:

```bash
git add TODO.md
git commit -m "docs: record counter validation evidence"
```

Do not push, merge, tag, publish, dispatch workflows, or alter repository visibility unless the user separately requests that external action.

## Completion Checklist

- [ ] The 64x18 render reads as one Flutter-inspired application with exact approved palette, hierarchy, and rounded action surface.
- [ ] Up, `+`, Enter, Space, and left-button down increment through one method; Down and `-` decrement through one method.
- [ ] Releases, unrelated keys, and right/middle clicks are behaviorally ignored.
- [ ] `main()` enables basic mouse reporting exactly once and retains hot reload.
- [ ] Compact rendering is safe and keeps the title, count, and primary action visible.
- [ ] Inherited evidence visibly advances from dependency update 1 to 2 and derives its style only in `didChangeDependencies`.
- [ ] README, example catalog, changelog, and final TODO evidence match the shipped tree.
- [ ] Initial and incremented VS Code screenshots exist, every real input route was observed, the button was actually clicked, and Ctrl+C returned a clean shell.
- [ ] Independent review has no unresolved Critical or Important finding.
- [ ] Focused, format, analysis, architecture, full-suite, asset, publish-dry-run, and diff checks all pass on the final tree.
