# Pub Search Interaction Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make pub-search commands, mouse activation, active tabs, and cursor ownership explicit, testable, and visually clean at 80×24 and 120×32.

**Architecture:** Keep the existing `PubSearchApp` state/focus ownership and `PubPackageDetail` composition. Derive scaffold help from current focus and page capabilities, retain the existing `Select`/`PointerListener` activation paths, and add application regressions plus refreshed visual evidence instead of introducing new widgets or state owners.

**Tech Stack:** Dart, Noir widgets and focus/input APIs, `WidgetTester` through `createTuiTestApp`, `BufferCapture` cursor/style assertions, Noir Driver, OpenTUI test renderer.

## Global Constraints

- The supported layout floor is exactly 80×24; validate the wider layout at 120×32.
- Keep `DemoScaffold`, `DemoPanel`, `pubTheme`, `TextInput`, `Select`, and `ScrollBox` as the owning components.
- Keep one-row non-focusable tabs; do not add a new framework widget, hover system, pointer-cursor API, split view, modal, animation, or second help row.
- A package row and any padded tab hitbox activate on one left click.
- The query cursor is an amber blinking block only while the query owns focus; it is hidden in results and detail.
- Mouse reporting stays enabled through `runTuiApp(..., enableMouse: true)`.
- Preserve catalog, model, sorting, filtering, pagination, loading, empty, error, Escape, and keyboard behavior.
- Use only authorized repository checks; no PTY, crash, native-build, ABI, publication, or manual-workflow operations beyond the user-authorized visual session.
- Preserve unrelated worktree edits and do not stage overlapping WIP without a clean ownership boundary.

> **Superseded traversal note:** Task 1 below records the pre-selector
> implementation steps. Its one-Tab examples and `Tab results` copy are not
> current behavior. The implemented order is query → Sort → Filter →
> results when results exist; query help says `Tab sort`, and each launcher
> names the next available control. The later selector-polish contract and
> application tests are authoritative.

---

### Task 1: Contextual Search Commands

**Files:**
- Modify: `example/pub_search/app.dart:428-435`
- Test: `test/example/pub_search_test.dart`

**Interfaces:**
- Consumes: `_searchState`, `_showSuggestions`, `_resultsFocus`, `_searchPage`, `PackageSearchPage.page`, and `PackageSearchPage.hasNextPage`.
- Produces: private `_searchHint`, `_focusedResultHint`, and `_pageCommandHint` getters returning the exact one-row scaffold copy.

- [ ] **Step 1: Add focused-result help tests before production code**

Add tests that render a deterministic ready page, move focus with Tab, and assert the exact focus-specific commands:

```dart
test('search help follows query and result focus', () async {
  final catalog = _FakePubCatalog()
    ..searchResults.add(_page(['noir']));
  final app = createTuiTestApp(
    PubSearchApp(catalog: catalog, onQuit: () {}),
    width: 80,
    height: 24,
  );

  try {
    await _settle(app);
    expect(
      _render(app),
      contains('Enter search   Tab results   Esc quit'),
    );

    app.mockInput.pressTab();
    await _settle(app);

    expect(
      _render(app),
      contains('↑↓ select  Enter/click open  / search  s/f  Esc quit'),
    );
  } finally {
    app.dispose();
  }
});
```

Add a table-driven pagination test with ready pages representing no movement,
next only, previous only, and both directions:

```dart
test('search help advertises only available page commands', () async {
  const cases = [
    (page: 1, hasNext: false, expected: null),
    (page: 1, hasNext: true, expected: 'n next'),
    (page: 2, hasNext: false, expected: 'p prev'),
    (page: 2, hasNext: true, expected: 'n/p page'),
  ];
  const pageCommands = ['n next', 'p prev', 'n/p page'];

  for (final testCase in cases) {
    final catalog = _FakePubCatalog()
      ..searchResults.add(
        _page(
          ['noir'],
          page: testCase.page,
          hasNextPage: testCase.hasNext,
        ),
      );
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () {}),
      width: 80,
      height: 24,
    );

    try {
      await _settle(app);
      app.mockInput.pressTab();
      await _settle(app);
      final frame = _render(app);

      for (final command in pageCommands) {
        expect(
          frame,
          command == testCase.expected
              ? contains(command)
              : isNot(contains(command)),
        );
      }
    } finally {
      app.dispose();
    }
  }
});
```

Add suggestion-specific coverage before implementation as well:

```dart
test('focused suggestions advertise choosing instead of opening', () async {
  final catalog = _FakePubCatalog()
    ..suggestions.addAll(const [
      PubSuggestion.package('noir'),
      PubSuggestion.package('noir_router'),
    ]);
  final app = createTuiTestApp(
    PubSearchApp(
      catalog: catalog,
      onQuit: () {},
      initialQuery: '',
      autoSearch: false,
    ),
    width: 80,
    height: 24,
  );

  try {
    await _settle(app);
    app.mockInput.typeText('noi');
    await _settle(app);
    app.mockInput.pressTab();
    await _settle(app);

    expect(
      _render(app),
      contains('↑↓ select  Enter/click choose  / search  Esc quit'),
    );
    expect(_render(app), isNot(contains('Enter/click open')));
  } finally {
    app.dispose();
  }
});
```

- [ ] **Step 2: Run the new search-help tests and verify RED**

Run:

```bash
dart test test/example/pub_search_test.dart --concurrency=1 -n 'search help follows query and result focus|search help advertises only available page commands|focused suggestions advertise choosing instead of opening'
```

Expected: FAIL because the current generic hint is
`Enter search   Tab   ↑↓   s/f   n/p   Esc quit`.

- [ ] **Step 3: Implement the smallest contextual hint derivation**

Add these private getters to `_PubSearchAppState` and pass `_searchHint` to
`DemoScaffold.hint`:

```dart
String get _searchHint {
  if (_searchState == PubLoadState.idle) {
    return 'Enter search   Esc quit';
  }
  if (!_resultsFocus.hasFocus) {
    return 'Enter search   Tab results   Esc quit';
  }
  if (_showSuggestions && _suggestions.isNotEmpty) {
    return '↑↓ select  Enter/click choose  / search  Esc quit';
  }
  return _focusedResultHint;
}

String get _focusedResultHint => [
  '↑↓ select',
  'Enter/click open',
  '/ search',
  's/f',
  if (_pageCommandHint case final hint?) hint,
  'Esc quit',
].join('  ');

String? get _pageCommandHint {
  final page = _searchPage;
  if (page == null) return null;
  final previous = page.page > 1;
  final next = page.hasNextPage;
  if (previous && next) return 'n/p page';
  if (next) return 'n next';
  if (previous) return 'p prev';
  return null;
}
```

Replace the inline ternary at `DemoScaffold.hint` with `hint: _searchHint`.

- [ ] **Step 4: Verify every contextual-help test is GREEN**

Run the three contextual-help tests from Step 2. Expected: PASS.

- [ ] **Step 5: Run the entire pub-search application test file**

Run:

```bash
dart test test/example/pub_search_test.dart --concurrency=1
```

Expected: all tests pass with no warnings.

---

### Task 2: Mouse, Tab, and Cursor Contracts

**Files:**
- Modify: `example/pub_search/package_detail.dart:103-107`
- Test: `test/example/pub_search_test.dart`
- Test: `test/golden/pub_search_golden_test.dart`
- Update: `test/goldens/pub_search_detail.buffer.txt`
- Update: `test/goldens/pub_search_detail.styles.txt`
- Inspect: `test/goldens/pub_search_detail.cursor.txt`

**Interfaces:**
- Consumes: `Select.onSelect`, `PointerListener.onPointerDown`, `MouseButton.left`, `CapturedBuffer.cursor`, `pubTheme.cursor`, and `PackageDetailTab.values`.
- Produces: exact detail help `←→/1–4/click tabs  ↑↓/PgUp/PgDn scroll  / search  Esc results` and regression evidence for existing single-click and cursor semantics.

- [ ] **Step 1: Add the detail-help regression before changing copy**

In the existing detail test, assert the exact new footer after opening a
package:

```dart
expect(
  _render(app),
  contains(
    '←→/1–4/click tabs  ↑↓/PgUp/PgDn scroll  / search  Esc results',
  ),
);
```

- [ ] **Step 2: Run the focused detail-help test and verify RED**

Run:

```bash
dart test test/example/pub_search_test.dart --concurrency=1 -n 'clicking a detail tab selects that section'
```

Expected: FAIL because the current footer does not mention mouse activation.

- [ ] **Step 3: Replace the detail footer with the approved 71-cell copy**

Use exactly:

```dart
Text(
  '←→/1–4/click tabs  ↑↓/PgUp/PgDn scroll  / search  Esc results',
  style: TextStyle(color: theme.textMuted),
),
```

- [ ] **Step 4: Lock single-click package opening and cursor ownership**

Add a test that captures the focused query cursor, clicks the result row
without first pressing Tab, and verifies both detail navigation and cursor
hiding:

```dart
test('single-clicking a package opens detail and hides the query cursor', () async {
  final catalog = _FakePubCatalog()
    ..searchResults.add(_page(['noir']))
    ..detailResults['noir'] = Future.value(examplePubPackage);
  final app = createTuiTestApp(
    PubSearchApp(catalog: catalog, onQuit: () {}),
    width: 100,
    height: 32,
  );

  try {
    await _settle(app);
    final queryCursor = app.captureFrame().cursor;
    expect(queryCursor.visible, isTrue);
    expect(queryCursor.style, CursorStyle.block);
    expect(queryCursor.color, Color.fromHex(pubTheme.cursor.toHex()));
    expect(queryCursor.blinking, isTrue);

    final result = app.captureFrame().findText('noir').last;
    app.mockMouse.click(result.x, result.y);
    await _settle(app);

    expect(catalog.detailCalls, ['noir']);
    expect(_render(app), contains('dart pub add noir'));
    expect(app.captureFrame().cursor.visible, isFalse);
  } finally {
    app.dispose();
  }
});
```

This is characterization coverage for already observed behavior; it should
pass immediately. If it fails, treat that as a correctness defect and fix only
the failing activation/focus path.

- [ ] **Step 5: Exercise every padded tab hitbox and active style**

Refactor `clicking a detail tab selects that section` to loop over these
observable pairs:

```dart
const cases = [
  ('1 OVERVIEW', 'PACKAGE PROFILE'),
  ('2 VERSIONS', 'PUBLISHED VERSIONS'),
  ('3 DEPENDENCIES', 'DIRECT DEPENDENCIES'),
  ('4 HEALTH', 'PUB SCORE'),
];
for (final (label, content) in cases) {
  final tab = app.captureFrame().findText(label).single;
  app.mockMouse.click(tab.x - 1, tab.y);
  await _settle(app);
  expect(_render(app), contains(content));
  expect(_tabStyle(app, label).background, _painted(pubTheme.accent));
  expect(
    _tabStyle(app, label).foreground,
    _painted(pubTheme.accentForeground),
  );
  expect(_tabStyle(app, label).bold, isTrue);
  expect(app.captureFrame().cursor.visible, isFalse);
}
```

Expected: PASS without production changes because the existing padded
`PointerListener` and active fill are preserved.

- [ ] **Step 6: Regenerate and inspect the affected detail golden**

Run:

```bash
UPDATE_GOLDENS=1 dart test test/golden/pub_search_golden_test.dart --concurrency=1
git diff -- test/goldens/pub_search_detail.buffer.txt test/goldens/pub_search_detail.styles.txt test/goldens/pub_search_detail.cursor.txt
```

Expected: the buffer footer changes to the approved copy; styles remain muted
for the footer and accent/foreground styling remains confined to the active
tab; the cursor sidecar remains `hidden`.

- [ ] **Step 7: Run all coupled focused tests**

Run:

```bash
dart test test/example/pub_search_test.dart test/golden/pub_search_golden_test.dart test/example/demo_scaffold_test.dart --concurrency=1
```

Expected: all tests pass.

---

### Task 3: Visual Iteration, Independent Review, and Release Gates

**Files:**
- Use: `.context/pub_search_drive.dart`
- Use: `.context/capture_pub_search.dart`
- Generate: `.context/screenshots/pub_search_review/*.png`
- Review: `example/pub_search/app.dart`
- Review: `example/pub_search/package_detail.dart`
- Review: `test/example/pub_search_test.dart`
- Review: `test/golden/pub_search_golden_test.dart`

**Interfaces:**
- Consumes: the deterministic `_DriveCatalog`, `NoirDriver.captureCells`, production ANSI parser input, click coordinates resolved from rendered labels, and the authorized repository checks.
- Produces: paired 80×24/120×32 screenshots for autocomplete loading,
  suggestions, both open pickers, sort and filter refresh loading, empty/error,
  detail loading, and all four detail tabs, plus exact mouse/cursor evidence,
  an independent review verdict, and full green verification.

- [ ] **Step 1: Re-capture every approved visual state**

Run:

```bash
dart run --verbosity=error .context/capture_pub_search.dart
```

Expected screenshots for both sizes: idle, autocomplete loading and
suggestions, query-focused and list-focused results, open sort and filter
pickers, sort and filter refresh loading, empty/error, detail loading, and
overview, versions, dependencies, and health. The live pass uses the actual
online executable rather than deterministic capture data.

- [ ] **Step 2: Review every 80×24/120×32 pair**

Inspect each `*_compare.png` and record pass/fail for:

- full bottom border and one-row help preservation;
- contextual copy matching the focus owner;
- amber block cursor visible only in the query;
- muted versus focused result selection;
- accent transfer between query, results, and detail panels;
- active-tab fill across label and padding;
- readable wrapping and scrollbar placement; and
- no information-architecture change between sizes.

If any pair fails, add a focused failing test, make the smallest correction,
and repeat Tasks 1 or 2 before continuing.

- [ ] **Step 3: Recheck the live VS Code surface through Computer Use**

Inspect the VS Code integrated terminal and attempt the deterministic app
there. Treat Noir Driver as authoritative if alternate-screen painting remains
unavailable to Computer Use. Do not retry Apple Terminal or iTerm control if
the environment repeats its safety-policy rejection.

- [ ] **Step 4: Obtain independent behavior and diff review**

Ask an independent reviewer to compare the implementation against
`docs/superpowers/specs/2026-08-20-pub-search-interaction-cleanup-design.md`,
prioritizing correctness defects, 80×24 fit, misleading commands, mouse hit
targets, cursor ownership, and unintended changes. Address every material
finding with a failing regression first.

- [ ] **Step 5: Run the authorized verification sequence**

Run in order:

```bash
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ scripts/
dart analyze --fatal-infos
dart test test/example/pub_search_test.dart test/golden/pub_search_golden_test.dart test/example/demo_scaffold_test.dart --concurrency=1
dart test test/architecture/ --concurrency=1
dart test --concurrency=1
git diff --check
```

Expected: zero formatting changes, no analyzer issues, every focused,
architecture, and full-suite test passes, and no whitespace errors.

- [ ] **Step 6: Audit completion against every specification requirement**

For each requirement in the design specification, cite current file/test,
driver capture, Computer Use result, or command output. Confirm no unrelated
worktree edit was staged or overwritten. Report any host-policy limitation
without weakening the Noir Driver evidence.
