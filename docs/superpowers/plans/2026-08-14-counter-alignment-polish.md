# Counter Alignment Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct Noir's bounded `Align` layout and use it to render a flat, vertically centered counter app bar and a solid square-reading action tile without outlines.

**Architecture:** `RenderPositionedBox` will loosen only the constraints passed to its child, then keep its own existing bounded-fill/unbounded-shrink-wrap sizing rule and position the natural child within the remaining cells. The counter will consume that corrected public behavior through plain colored `Container`s, with its state and input ownership unchanged.

**Tech Stack:** Dart, Noir widgets/render objects, `BufferCapture`, `TuiTestApp`, Dart test, VS Code integrated terminal, Computer Use.

## Global Constraints

- Preserve `package:noir/noir.dart`, `package:noir/noir_low_level.dart`, and `package:noir/noir_ffi.dart` ownership boundaries.
- Do not change FFI, native ABI, bundled binaries, the OpenTUI gitlink, workflows, tags, releases, or publication state.
- Keep `CounterApp` as the sole count owner and keep every activation path routed through `_incrementCounter` or `_decrementCounter`.
- Keep `app.enableMouse()` exactly once without movement reporting and preserve `registerHotReloadExtension(app)`.
- Use `BufferCapture` for focused render layout, `createTuiTestApp` for the interactive example, and `BufferMatchers` for cell evidence; do not add another harness.
- Write each behavior assertion before its production change, observe the intended failure, implement the smallest fix, and rerun the focused test.
- Keep screenshots under gitignored `.context`; do not add them to package sources.
- Update `TODO.md` only after the exact final test count, independent review, and live VS Code evidence are known.

---

### Task 1: Correct bounded Align positioning

**Files:**
- Modify: `test/rendering/align_offset_test.dart`
- Modify: `lib/src/rendering/positioned_box.dart`
- Regenerate if changed by corrected semantics: `test/goldens/text_widgets.buffer.txt`
- Regenerate if changed by corrected semantics: `test/goldens/text_widgets.styles.txt`
- Regenerate if changed by corrected semantics: `test/goldens/alignment_combinations.buffer.txt`
- Regenerate if changed by corrected semantics: `test/goldens/alignment_combinations.styles.txt`

**Interfaces:**
- Consumes: `BoxConstraints.loose({int? maxWidth, int? maxHeight})`, `Alignment`, `RenderBox.layout`, and `positionChild`.
- Produces: `RenderPositionedBox.performBoxLayout` behavior in which a naturally sized child can be positioned inside a bounded parent.

- [ ] **Step 1: Establish the pre-change package baseline**

Run:

```bash
dart test --concurrency=1
```

Expected: the unchanged starting tree ends with `+1256: All tests passed!`.

- [ ] **Step 2: Add exact failing alignment tests**

Append these tests inside the existing `Align painting offsets` group in
`test/rendering/align_offset_test.dart`:

```dart
test('center positions a natural child within tight bounds', () {
  final frame = capture.capture(
    const SizedBox(
      width: 7,
      height: 3,
      child: Align(child: Text('C')),
    ),
  );

  expect(frame.findText('C').single, const BufferPosition(3, 1));
});

test('centerLeft vertically centers a natural child', () {
  final frame = capture.capture(
    const SizedBox(
      width: 7,
      height: 3,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text('L'),
      ),
    ),
  );

  expect(frame.findText('L').single, const BufferPosition(0, 1));
});

test('bottomRight positions a natural child at both trailing edges', () {
  final frame = capture.capture(
    const SizedBox(
      width: 7,
      height: 3,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Text('R'),
      ),
    ),
  );

  expect(frame.findText('R').single, const BufferPosition(6, 2));
});
```

- [ ] **Step 3: Run the alignment test and verify the defect**

Run:

```bash
dart test test/rendering/align_offset_test.dart --concurrency=1
```

Expected: the three new tests fail with actual `BufferPosition(0, 0)` values;
the existing visibility/offset tests still pass.

- [ ] **Step 4: Loosen only the child constraints**

Replace the child layout call in
`RenderPositionedBox.performBoxLayout` with:

```dart
// Align fills bounded axes but lets its child choose a natural size within
// those bounds, leaving an extent for the requested alignment to position.
child.layout(
  BoxConstraints.loose(
    maxWidth: constraints.maxWidth,
    maxHeight: constraints.maxHeight,
  ),
);
```

Keep the existing `selfWidth`, `selfHeight`, `size`, available-extent,
rounding, and `positionChild` logic unchanged.

- [ ] **Step 5: Prove the alignment fix is green**

Run:

```bash
dart test test/rendering/align_offset_test.dart test/container_widget_test.dart test/rendering/flex_correctness_test.dart --concurrency=1
```

Expected: all tests pass, including center `(3, 1)`, center-left `(0, 1)`, and
bottom-right `(6, 2)`.

- [ ] **Step 6: Review and regenerate only affected visual goldens**

Run the existing golden checks first:

```bash
dart test test/golden/text_widget_golden_test.dart test/golden/widget_golden_test.dart --concurrency=1
```

Expected: failures are limited to cases whose old buffers/styles encoded a
child at the origin despite a non-top-left `Align`.

Regenerate those two suites:

```bash
UPDATE_GOLDENS=1 dart test test/golden/text_widget_golden_test.dart test/golden/widget_golden_test.dart --concurrency=1
```

Inspect:

```bash
git diff -- test/goldens/text_widgets.buffer.txt test/goldens/text_widgets.styles.txt test/goldens/alignment_combinations.buffer.txt test/goldens/alignment_combinations.styles.txt
```

Accept only coordinate/style relocation consistent with the declared
alignment, then rerun the two golden test files without `UPDATE_GOLDENS` and
expect all tests to pass.

- [ ] **Step 7: Format and commit the framework slice**

Run:

```bash
dart format lib/src/rendering/positioned_box.dart test/rendering/align_offset_test.dart
git diff --check
git add lib/src/rendering/positioned_box.dart test/rendering/align_offset_test.dart test/goldens/text_widgets.buffer.txt test/goldens/text_widgets.styles.txt test/goldens/alignment_combinations.buffer.txt test/goldens/alignment_combinations.styles.txt
git commit -m "fix(rendering): honor bounded Align positioning"
```

Expected: one coherent commit containing the render fix, three regression
tests, and only directly affected golden sidecars.

---

### Task 2: Replace the counter outlines with flat surfaces

**Files:**
- Modify: `test/example/counter_test.dart`
- Modify: `example/counter.dart`

**Interfaces:**
- Consumes: corrected `Alignment.centerLeft` and `Alignment.center`, `Container(color:, width:, height:)`, `PointerListener`, and the existing `_incrementCounter` callback.
- Produces: a flat three-row app bar and a solid 7x3 action tile whose entire area is pointer-active.

- [ ] **Step 1: Strengthen the visual test before changing the example**

Remove the `_darkMaterialBlue` test constant. In the initial hierarchy test,
replace the weak title/rule and rounded-corner assertions with this exact
evidence:

```dart
expect(title.x, 2);
expect(title.y, 1);
expect(frame.getForegroundColor(title.x, title.y), Color.white);
expect(frame.getBackgroundColor(title.x, title.y), _materialBlue);
expect(frame.getCell(title.x, title.y).isBold, isTrue);
for (var y = 0; y < 3; y++) {
  for (var x = 0; x < frame.width; x++) {
    expect(
      frame.getBackgroundColor(x, y),
      _materialBlue,
      reason: 'app-bar cell ($x, $y) must use one flat blue surface',
    );
  }
}
expect(frame.getChar(0, 2), ' ');
expect(frame.getBackgroundColor(0, 3), _surface);
```

Keep the existing body and hint assertions. Replace the action assertions with:

```dart
final actionLeft = increment.x - 3;
final actionTop = increment.y - 1;
expect(actionLeft, frame.width - 9);
expect(actionTop, frame.height - 4);
expect(frame.getForegroundColor(increment.x, increment.y), Color.white);
expect(frame.getBackgroundColor(increment.x, increment.y), _materialBlue);
expect(frame.getCell(increment.x, increment.y).isBold, isTrue);
for (var y = actionTop; y < actionTop + 3; y++) {
  for (var x = actionLeft; x < actionLeft + 7; x++) {
    expect(
      frame.getBackgroundColor(x, y),
      _materialBlue,
      reason: 'action cell ($x, $y) must be part of the solid surface',
    );
  }
}
final actionRegion = frame.getRegion(actionLeft, actionTop, 7, 3);
for (final borderGlyph in ['╭', '╮', '╰', '╯', '─', '│']) {
  expect(actionRegion, isNot(contains(borderGlyph)));
}
expect(frame.getBackgroundColor(0, frame.height - 1), _surface);
```

- [ ] **Step 2: Make the full action surface part of the pointer proof**

In `counter increments only on left-button down inside the action`, derive the
top-left tile coordinate from the located plus and use it for the first press:

```dart
final increment = _incrementGlyph(app.captureFrame());
final actionLeft = increment.x - 3;
final actionTop = increment.y - 1;

app.mockMouse.pressDown(actionLeft, actionTop);
await _settle(app);
_expectCount(app, 1);

app.mockMouse.release(actionLeft, actionTop);
```

Keep the existing release, right-button, and middle-button assertions.

- [ ] **Step 3: Run the counter test and verify the old composition fails**

Run:

```bash
dart test test/example/counter_test.dart --concurrency=1
```

Expected: the hierarchy test fails because the old bottom rule and border cells
are not flat blue. The corner-click assertion may already pass because the
listener wraps the outer 7x3 box; it strengthens the proof without changing
that existing hit area.

- [ ] **Step 4: Simplify the app bar and action widget**

Delete `_darkMaterialBlue` and `_roundedBorderCharacters` from
`example/counter.dart`.

Replace the app-bar `Container` decoration with a plain color while retaining
height, alignment, padding, title, and typography:

```dart
Container(
  alignment: Alignment.centerLeft,
  padding: const EdgeInsets.symmetric(horizontal: 2),
  color: _materialBlue,
  child: const Text(
    'Noir Counter',
    style: TextStyle(fontWeight: FontWeight.bold),
  ),
)
```

Replace `_IncrementButton.build` with:

```dart
@override
Widget build(BuildContext context) => PointerListener(
  onPointerDown: _handlePointerDown,
  child: Container(
    width: 7,
    height: 3,
    alignment: Alignment.center,
    color: _materialBlue,
    child: const Text(
      '+',
      style: TextStyle(fontWeight: FontWeight.bold),
    ),
  ),
);
```

Do not change key routing, callback ownership, mouse enablement, hot reload, or
terminal padding.

- [ ] **Step 5: Prove the counter polish is green**

Run:

```bash
dart test test/example/counter_test.dart test/rendering/align_offset_test.dart --concurrency=1
dart analyze --fatal-infos
```

Expected: ten focused tests pass and analysis reports `No issues found!`.

- [ ] **Step 6: Format and commit the example slice**

Run:

```bash
dart format example/counter.dart test/example/counter_test.dart
git diff --check
git add example/counter.dart test/example/counter_test.dart
git commit -m "feat(examples): polish counter action surfaces"
```

Expected: one coherent commit containing only the example and its behavioral
tests.

---

### Task 3: Align documentation with the rendered UI

**Files:**
- Modify: `docs/superpowers/specs/2026-08-13-flutter-style-counter-design.md`
- Modify: `README.md`
- Modify: `example/README.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: final observable UI from Tasks 1 and 2.
- Produces: package documentation with no stale rounded-border or dark-rule claims.

- [ ] **Step 1: Update the original design record**

Make these factual replacements in the original design:

- Describe the three-row app bar as one flat blue surface with a vertically
  centered title and no bottom rule.
- Describe the action as one solid 7x3 blue surface with a centered bold white
  plus and no box-drawing outline.
- Replace the rounded-glyph rationale with the terminal cell-ratio rationale:
  the 7x3 filled region reads approximately square in the observed terminal.
- Change the private button composition list to `PointerListener`, `Container`,
  `Align`, and `Text`.
- Change “rounded increment surface” and “rounded blue action surface” to
  “solid increment surface” and “solid blue action surface”.

- [ ] **Step 2: Update package-facing descriptions**

In `README.md`, replace both “rounded action surface” descriptions with “solid
square-style action surface”. The existing code sample already shows the final
plain colored `Container` and needs no structural rewrite.

In `example/README.md`, describe the counter as having “a flat app bar,
centered body, solid square-style action tile” before listing controls.

In `CHANGELOG.md`, change the counter bullet to “flat blue app bar, centered
body, and solid square-style clickable action surface”, and add this framework
behavior bullet after the general widget-framework bullet:

```markdown
- `Align` positions naturally sized children within bounded boxes while still
  filling bounded axes and shrink-wrapping unbounded axes.
```

- [ ] **Step 3: Prove no stale visual claim remains**

Run:

```bash
rg -n "rounded action|rounded increment|dark.*bottom rule|rounded blue action|╭|╮|╰|╯" README.md example/README.md CHANGELOG.md docs/superpowers/specs/2026-08-13-flutter-style-counter-design.md example/counter.dart
```

Expected: no matches. The counter regression test intentionally retains the
removed glyphs as negative assertions and is not part of this stale-copy scan.

Run:

```bash
dart test test/architecture/package_distribution_ownership_test.dart --concurrency=1
git diff --check
```

Expected: distribution checks pass and the documentation diff has no whitespace
errors.

- [ ] **Step 4: Commit the documentation slice**

Run:

```bash
git add README.md example/README.md CHANGELOG.md docs/superpowers/specs/2026-08-13-flutter-style-counter-design.md
git commit -m "docs: describe polished counter alignment"
```

---

### Task 4: Verify behavior and compare the live VS Code rendering

**Files:**
- Create ignored artifact: `.context/flutter-counter-polished/initial.jpeg`
- Create ignored artifact: `.context/flutter-counter-polished/incremented.jpeg`

**Interfaces:**
- Consumes: the final framework, counter, tests, and documentation.
- Produces: fresh automated and real-terminal evidence for the exact reviewed tree.

- [ ] **Step 1: Run the assembled automated checks**

Run:

```bash
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ scripts/
dart analyze --fatal-infos
dart test test/rendering/align_offset_test.dart test/example/counter_test.dart --concurrency=1
dart test test/architecture/ --concurrency=1
dart test --concurrency=1
dart run scripts/fetch_opentui_binaries.dart --verify-only
dart pub publish --dry-run
git diff --check
```

Expected: format changes zero files, analysis has zero issues, the focused
suite has ten tests, architecture remains green, the ordinary suite ends at
1259 tests, all six binaries verify, publish dry-run has zero warnings, and the
diff check is clean.

- [ ] **Step 2: Run the counter in the already-open VS Code terminal**

Use Computer Use rather than a new external terminal. Run:

```bash
dart run example/counter.dart
```

Capture the initial frame to
`.context/flutter-counter-polished/initial.jpeg`. Compare it directly with
`.context/flutter-counter/initial.jpeg` and confirm the title moved from the
top row to the middle app-bar row, the dark rule disappeared, and the action is
one filled 7x3 surface rather than a framed 5x1 fill.

- [ ] **Step 3: Exercise keyboard, pointer, and shutdown behavior**

Press Up and verify `0 -> 1`. Click a non-glyph blue cell inside the action and
verify `1 -> 2` exactly once. Capture the incremented frame to
`.context/flutter-counter-polished/incremented.jpeg`. Send Ctrl+C and confirm a
usable VS Code shell returns without a stack trace.

---

### Task 5: Independent review and final release evidence

**Files:**
- Modify after evidence is known: `TODO.md`

**Interfaces:**
- Consumes: exact committed implementation, tests, docs, screenshots, and gate output.
- Produces: reviewed release evidence and a clean final branch.

- [ ] **Step 1: Obtain independent behavior and full-diff review**

Ask the independent reviewer to compare the complete `origin/main...HEAD` diff
with both counter design specs and inspect the before/after screenshots. Require
severity-ranked findings and an explicit statement about unresolved Critical
or Important issues.

Expected: no unresolved Critical or Important finding. Resolve any material
finding test-first and rerun its focused checks before continuing.

- [ ] **Step 2: Record only the exact final evidence**

Update `TODO.md` from 1256 to the observed final count of 1259. Extend the
Conductor-terminal evidence to state that the polished frame has a vertically
centered title, flat app bar, solid action tile, direct non-glyph click evidence
for `1 -> 2`, and clean Ctrl+C restoration. Preserve every unrelated release
gate and known limitation.

- [ ] **Step 3: Review and commit the evidence update**

Run:

```bash
git diff --check
git diff -- TODO.md
```

Have the independent reviewer confirm the TODO-only evidence diff, then run:

```bash
git add TODO.md
git commit -m "docs: record counter polish verification"
```

- [ ] **Step 4: Rerun every final gate on the exact final commit**

Run:

```bash
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ scripts/
dart analyze --fatal-infos
dart test test/rendering/align_offset_test.dart test/example/counter_test.dart --concurrency=1
dart test test/architecture/ --concurrency=1
dart test --concurrency=1
dart run scripts/fetch_opentui_binaries.dart --verify-only
dart pub publish --dry-run
git diff --check
git status --short --branch
```

Expected: every command exits zero, focused tests total ten, architecture is
green, the ordinary suite totals 1259, assets verify six binaries, publish
dry-run reports zero warnings, and the worktree is clean.
