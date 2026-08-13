# Noir Example Validation Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair animation callback isolation, make every advertised example interaction real, and turn the review probes into permanent package regression coverage.

**Architecture:** Keep error containment inside the animation layer, terminal-mode setup inside real entrypoints, and behavior assertions in the existing parser-backed example harness. Add one cohesive high-level primitives example instead of widening the public API or manufacturing one demo per exported type; keep native, ABI, compositor, and OpenTUI ownership unchanged.

**Tech Stack:** Dart 3, Noir's widget/element/render pipeline, `package:test`, `createTuiTestApp`, `MockInput`, `MockMouse`, `CapturedBuffer`/`BufferMatchers`, Dart `Zone`, and Git.

## Global Constraints

- Work only in `/Users/leofarias/conductor/workspaces/noir/trenton` on the current branch; do not rename it.
- Treat `origin/main` as the comparison/base branch and preserve unrelated user changes.
- The approved contract is `docs/superpowers/specs/2026-08-13-example-validation-fixes-design.md` at baseline commit `6ea7b36`.
- Keep widgets declarative, Elements identity-owning, RenderObjects responsible for layout/paint, and the compositor as the normal OpenTUI bridge.
- No widget may call FFI; examples import only supported package barrels.
- Do not edit or advance `external/opentui`, rebuild native libraries, alter the ABI, hashes, manifests, provenance URLs, tags, releases, publication state, or CI runs.
- Status-listener and ticker failures must be reported with the original error and stack to the `Zone` current at the start of that dispatch boundary.
- `select_demo.dart` and `scrollbox_demo.dart` call `app.enableMouse()` exactly once and do not enable pointer movement.
- Do not force `TerminalCapabilities` into the high-level primitives example; its advanced renderer-extension behavior remains covered by the low-level consumer fixture and architecture tests.
- Preserve the inherited example's ocean colors: `Color(0.2, 0.4, 0.8)` with `Color.white`; use forest colors `Color(0.1, 0.5, 0.25)` with `Color.yellow` after `t`.
- Use only the four existing harnesses for their intended roles; example input coverage in this plan uses `createTuiTestApp` and parser-backed `mockInput`/`mockMouse`.
- Begin each production behavior change with a focused failing test, confirm the failure reason, implement the smallest coherent fix, and commit only after its focused checks pass.
- A passing characterization test is acceptable for the pulse test-only expansion because it changes no production behavior; record that it passes before and after the assertion expansion.
- Use `apply_patch` for file edits. Run format on touched Dart files before each commit.
- Do not change the ordinary-test count in `TODO.md` until a complete `dart test --concurrency=1` run reports the new count from the assembled tree.
- Final completion requires an independent behavior/diff review with no unresolved Critical or Important findings plus every authorized release gate.

---

## File Structure Map

| Responsibility | Files |
| --- | --- |
| Status-listener containment and run completion | `lib/src/animation/animation_controller.dart`, `test/animation/animation_listener_isolation_test.dart` |
| Per-ticker frame containment | `lib/src/animation/ticker.dart`, `test/animation/animation_listener_isolation_test.dart` |
| Public animation contract wording | `lib/src/animation/animation.dart`, `skills/noir/references/state-and-animation.md` |
| Renderer-backed mouse setup | `example/select_demo.dart`, `example/scrollbox_demo.dart` |
| Parser-backed pointer regression coverage | `test/example/interactive_examples_test.dart` |
| Dynamic inherited dependency example | `example/inherited_example.dart`, `test/example/static_examples_test.dart` |
| Full ping-pong animation evidence | `test/example/pulse_animation_test.dart` |
| Advanced high-level primitives tour | `example/framework_primitives.dart`, `test/example/framework_primitives_test.dart` |
| Catalog and release evidence | `README.md`, `example/README.md`, `skills/noir/SKILL.md`, `TODO.md` |

---

### Task 1: Isolate Animation and Ticker Callback Failures

**Files:**

- Create: `test/animation/animation_listener_isolation_test.dart`
- Modify: `lib/src/animation/animation_controller.dart:325-344`
- Modify: `lib/src/animation/ticker.dart:1-70`
- Modify: `lib/src/animation/animation.dart:3-42`

**Interfaces:**

- Consumes: `AnimationController.forward({double? from}) -> Future<void>`, `AnimationController.addStatusListener(AnimationStatusListener)`, `TickerScheduler.createTicker(TickerCallback, {String? debugLabel, void Function(Ticker)? onDispose})`, and `TickerScheduler.handleFrame(Duration)`.
- Produces: unchanged public signatures; `_setStatus(AnimationStatus)` and `TickerScheduler.handleFrame(Duration)` become zone-reporting containment boundaries.

- [ ] **Step 1: Add the focused status-listener regression test**

Create `test/animation/animation_listener_isolation_test.dart` with the provider and first test below:

```dart
import 'dart:async';

import 'package:noir/src/animation/animation.dart';
import 'package:noir/src/animation/animation_controller.dart';
import 'package:noir/src/animation/ticker.dart';
import 'package:test/test.dart';

final class _TestTickerProvider implements TickerProvider {
  _TestTickerProvider(this.scheduler);

  final TickerScheduler scheduler;

  @override
  Ticker createTicker(TickerCallback onTick, {String? debugLabel}) =>
      scheduler.createTicker(onTick, debugLabel: debugLabel);
}

void main() {
  test(
    'status listener failure is reported without starving listeners or run',
    () async {
      final scheduler = TickerScheduler();
      final controller = AnimationController(
        vsync: _TestTickerProvider(scheduler),
        duration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      final listenerError = StateError('status listener failed');
      final listenerStack = StackTrace.fromString('status listener stack');
      final log = <String>[];
      final reports = <(Object, StackTrace, Zone)>[];
      final boundaryMarker = Object();

      controller
        ..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          log.add('throwing');
          Error.throwWithStackTrace(listenerError, listenerStack);
        })
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) log.add('later');
        });

      late Future<void> run;
      late Zone notificationZone;
      notificationZone = Zone.current.fork(
        zoneValues: {#animationBoundary: boundaryMarker},
        specification: ZoneSpecification(
          handleUncaughtError: (_, _, zone, error, stackTrace) {
            reports.add((error, stackTrace, zone));
            log.add('reported');
          },
        ),
      );

      notificationZone.runGuarded(() {
        run = controller.forward(from: 0);
        scheduler
          ..handleFrame(Duration.zero)
          ..handleFrame(const Duration(milliseconds: 100));
      });

      await run.timeout(const Duration(milliseconds: 100));
      expect(log, ['throwing', 'reported', 'later']);
      expect(reports, hasLength(1));
      expect(identical(reports.single.$1, listenerError), isTrue);
      expect(reports.single.$2.toString(), listenerStack.toString());
      expect(reports.single.$3, same(notificationZone));
      expect(reports.single.$3[#animationBoundary], same(boundaryMarker));
      expect(controller.value, controller.upperBound);
      expect(controller.status, AnimationStatus.completed);
      expect(controller.isAnimating, isFalse);
    },
  );
}
```

- [ ] **Step 2: Run the status-listener test and confirm the intended red state**

Run:

```bash
dart test test/animation/animation_listener_isolation_test.dart --concurrency=1
```

Expected: FAIL because the throwing completion listener escapes `_setStatus`, `later` is absent, and the run future times out instead of completing. Confirm the error is `StateError: status listener failed`, not an import, syntax, or harness failure.

- [ ] **Step 3: Contain each status listener and guarantee endpoint completion**

Replace `_finishAnimation` and `_setStatus` in `lib/src/animation/animation_controller.dart` with:

```dart
  void _finishAnimation() {
    _ticker.stop();
    final old = _takeCompleter();
    try {
      _setStatus(
        _isAnimatingForward
            ? AnimationStatus.completed
            : AnimationStatus.dismissed,
      );
    } finally {
      old?.complete();
    }
  }

  void _setStatus(AnimationStatus newStatus) {
    if (_status == newStatus) {
      return;
    }
    _status = newStatus;
    final reportingZone = Zone.current;
    final listeners = List<AnimationStatusListener>.from(_statusListeners);
    for (final listener in listeners) {
      try {
        listener(newStatus);
      } on Object catch (error, stackTrace) {
        reportingZone.handleUncaughtError(error, stackTrace);
      }
    }
  }
```

The file already imports `dart:async`, so no new controller import is required. The `finally` protects the run future even if a custom zone error handler itself throws.

- [ ] **Step 4: Run the status-listener test and existing controller contracts**

Run:

```bash
dart format lib/src/animation/animation_controller.dart test/animation/animation_listener_isolation_test.dart
dart test test/animation/animation_listener_isolation_test.dart test/animation/animation_controller_sanity_test.dart test/animation/animation_controller_run_state_test.dart --concurrency=1
```

Expected: all tests PASS; the new test records exactly one original error/stack report, runs the later listener, and awaits the run normally.

- [ ] **Step 5: Add the focused ticker-scheduler regression test**

Add this test inside the existing `main()` in `test/animation/animation_listener_isolation_test.dart`:

```dart
  test('ticker failure is reported without starving siblings or frames', () {
    final scheduler = TickerScheduler();
    final tickerError = StateError('ticker callback failed');
    final tickerStack = StackTrace.fromString('ticker callback stack');
    final log = <String>[];
    final reports = <(Object, StackTrace, Zone)>[];
    var frameRequests = 0;

    scheduler.setFrameCallback(() => frameRequests++);
    final throwingTicker = scheduler.createTicker((_) {
      log.add('throwing');
      Error.throwWithStackTrace(tickerError, tickerStack);
    });
    final siblingTicker = scheduler.createTicker((_) => log.add('sibling'));
    addTearDown(throwingTicker.dispose);
    addTearDown(siblingTicker.dispose);

    throwingTicker.start();
    siblingTicker.start();
    frameRequests = 0;

    late Zone frameZone;
    frameZone = Zone.current.fork(
      specification: ZoneSpecification(
        handleUncaughtError: (_, _, zone, error, stackTrace) {
          reports.add((error, stackTrace, zone));
          log.add('reported');
        },
      ),
    );
    frameZone.runGuarded(() => scheduler.handleFrame(Duration.zero));

    expect(log, ['throwing', 'reported', 'sibling']);
    expect(reports, hasLength(1));
    expect(identical(reports.single.$1, tickerError), isTrue);
    expect(reports.single.$2.toString(), tickerStack.toString());
    expect(reports.single.$3, same(frameZone));
    expect(throwingTicker.isTicking, isTrue);
    expect(siblingTicker.isTicking, isTrue);
    expect(frameRequests, 1);
  });
```

- [ ] **Step 6: Run the ticker test and confirm the intended red state**

Run:

```bash
dart test test/animation/animation_listener_isolation_test.dart --concurrency=1 --name 'ticker failure'
```

Expected: FAIL with `log` missing `sibling`, both tickers still active, and `frameRequests == 0`; the first ticker exception currently aborts `handleFrame` before sibling dispatch and the next-frame request.

- [ ] **Step 7: Contain each ticker callback at the scheduler boundary**

Add `dart:async` before the existing relative import in `lib/src/animation/ticker.dart`:

```dart
import 'dart:async';

import '../framework/widget.dart';
```

Replace `handleFrame` with:

```dart
  /// Ticks an active snapshot and requests another frame while work remains.
  ///
  /// Callback failures are reported with their original stack traces to the
  /// zone in which this frame dispatch began. One ticker cannot starve a
  /// sibling or suppress the next frame while active work remains.
  void handleFrame(Duration timeStamp) {
    if (_activeTickers.isEmpty) {
      return;
    }

    final reportingZone = Zone.current;
    final tickers = List<Ticker>.from(_activeTickers);
    for (final ticker in tickers) {
      try {
        ticker._tick(timeStamp);
      } on Object catch (error, stackTrace) {
        reportingZone.handleUncaughtError(error, stackTrace);
      }
    }

    if (_activeTickers.isNotEmpty) {
      _requestFrame();
    }
  }
```

- [ ] **Step 8: Document the status-listener error contract**

Add the Dart zone import at the top of `lib/src/animation/animation.dart`:

```dart
import 'dart:async';

import '../foundation/change_notifier.dart';
```

Replace the `addStatusListener` documentation in `lib/src/animation/animation.dart` with:

```dart
  /// Registers [listener] for later status transitions.
  ///
  /// Listener failures are reported with their original stack traces to the
  /// zone in which status notification began. A failure does not prevent
  /// later listeners in that notification snapshot from running.
  void addStatusListener(AnimationStatusListener listener);
```

- [ ] **Step 9: Run the complete focused animation slice**

Run:

```bash
dart format lib/src/animation/animation.dart lib/src/animation/animation_controller.dart lib/src/animation/ticker.dart test/animation/animation_listener_isolation_test.dart
dart test test/animation/animation_listener_isolation_test.dart test/animation/animation_controller_sanity_test.dart test/animation/animation_controller_run_state_test.dart test/animation/ticker_provider_lifecycle_test.dart --concurrency=1
dart analyze --fatal-infos
```

Expected: all focused tests PASS and analysis reports `No issues found!`.

- [ ] **Step 10: Commit the animation containment slice**

```bash
git add lib/src/animation/animation.dart lib/src/animation/animation_controller.dart lib/src/animation/ticker.dart test/animation/animation_listener_isolation_test.dart
git commit -m "fix(animation): isolate callback failures"
```

Expected: one commit containing only the animation implementation, contract documentation, and focused regression test.

---

### Task 2: Enable and Permanently Test Example Mouse Input

**Files:**

- Modify: `example/select_demo.dart:13-24`
- Modify: `example/scrollbox_demo.dart:12-23`
- Modify: `test/example/interactive_examples_test.dart:1-190`

**Interfaces:**

- Consumes: `TuiApp.enableMouse({bool enableMovement = false})`, `TuiTestApp.mockMouse`, `CapturedBuffer.findText(String)`, and existing `SelectDemoApp`, `ScrollDemoApp`, and `FocusFormApp` constructors.
- Produces: real entrypoints with basic mouse reporting enabled and parser-backed regression cases for click/wheel behavior.

- [ ] **Step 1: Add the failing entrypoint contract test**

Add `dart:io` at the top of `test/example/interactive_examples_test.dart`:

```dart
import 'dart:io' as io;

import 'package:noir/noir.dart';
```

Add this test at the start of `main()`:

```dart
  test('mouse-capable example entrypoints enable mouse reporting once', () {
    for (final path in <String>[
      'example/select_demo.dart',
      'example/scrollbox_demo.dart',
    ]) {
      final source = io.File(path).readAsStringSync();
      expect(
        RegExp(r'app\.enableMouse\(\);').allMatches(source),
        hasLength(1),
        reason: path,
      );
      expect(
        source,
        isNot(contains('enableMouse(enableMovement: true)')),
        reason: '$path does not need movement reports',
      );
    }
  });
```

- [ ] **Step 2: Run the source contract and confirm the intended red state**

Run:

```bash
dart test test/example/interactive_examples_test.dart --concurrency=1 --name 'mouse-capable example entrypoints'
```

Expected: FAIL for both files because neither real-terminal `main()` currently contains `app.enableMouse();`.

- [ ] **Step 3: Add the permanent pointer interaction cases**

Add these three tests to `test/example/interactive_examples_test.dart`:

```dart
  test('focus form fields can be selected and submitted by mouse', () async {
    final app = createTuiTestApp(const FocusFormApp(), width: 80, height: 24);
    try {
      await _settleAutofocus(app);
      var frame = app.captureFrame();
      final name = frame.findText('Jane Doe').single;
      app.mockMouse.click(name.x, name.y);
      app.mockInput.typeText('Ada');
      await _settleInput();
      app.pumpFrame();

      frame = app.captureFrame();
      final email = frame.findText('jane@example.com').single;
      app.mockMouse.click(email.x, email.y);
      app.mockInput
        ..typeText('ada@example.com')
        ..pressEnter();
      await _settleInput();

      expect(_render(app), contains('Saved: Ada - ada@example.com'));
    } finally {
      app.dispose();
    }
  });

  test('select option can be confirmed by mouse', () async {
    final app = createTuiTestApp(
      SelectDemoApp(onQuit: () {}),
      width: 56,
      height: 20,
    );
    try {
      await _settleAutofocus(app);
      final cherry = app.captureFrame().findText('Cherry').single;
      app.mockMouse.click(cherry.x, cherry.y);
      await _settleInput();

      expect(_render(app), contains('You picked: cherry'));
    } finally {
      app.dispose();
    }
  });

  test('scrollbox responds to a wheel event inside its viewport', () async {
    final app = createTuiTestApp(
      ScrollDemoApp(onQuit: () {}),
      width: 56,
      height: 18,
    );
    try {
      await _settleAutofocus(app);
      final firstLine = app.captureFrame().findText('Line 1').single;
      app.mockMouse.scroll(firstLine.x, firstLine.y, ScrollDirection.down);
      await _settleInput();

      expect(_render(app), isNot(contains('offset: 0 /')));
    } finally {
      app.dispose();
    }
  });
```

Run the three new interaction tests before changing the entrypoints:

```bash
dart test test/example/interactive_examples_test.dart --concurrency=1 --name 'focus form fields|select option|scrollbox responds'
```

Expected: the parser-backed interaction cases PASS, while the source contract remains the known failing evidence. This proves widget behavior already works and isolates the defect to terminal-mode setup.

- [ ] **Step 4: Enable mouse reporting in both real entrypoints**

In `example/select_demo.dart`, make the end of `main()`:

```dart
  app = runTuiApp(SelectDemoApp(onQuit: quit));
  app.enableMouse();
}
```

In `example/scrollbox_demo.dart`, make the end of `main()`:

```dart
  app = runTuiApp(ScrollDemoApp(onQuit: quit));
  app.enableMouse();
}
```

- [ ] **Step 5: Run the complete interactive-example slice**

Run:

```bash
dart format example/select_demo.dart example/scrollbox_demo.dart test/example/interactive_examples_test.dart
dart test test/example/interactive_examples_test.dart --concurrency=1
dart test test/widgets/select_test.dart test/widgets/scroll_box_viewport_test.dart test/framework/pointer_hit_testing_test.dart --concurrency=1
```

Expected: all tests PASS; the source contract finds exactly one non-movement `enableMouse()` call in each entrypoint.

- [ ] **Step 6: Commit the mouse-input slice**

```bash
git add example/select_demo.dart example/scrollbox_demo.dart test/example/interactive_examples_test.dart
git commit -m "fix(examples): enable documented mouse input"
```

---

### Task 3: Make the Inherited Theme Example Prove Dependency Rebuilds

**Files:**

- Modify: `example/inherited_example.dart:1-70`
- Modify: `test/example/static_examples_test.dart:24-53`

**Interfaces:**

- Consumes: `ThemeData.of(BuildContext)`, `InheritedWidget.updateShouldNotify`, `Focus(autofocus:, onKeyEvent:)`, and parser-backed `MockInput.typeText(String)`.
- Produces: `const ThemedApp()` remains valid, while `t` toggles ocean/forest theme snapshots and the visible mode label.

- [ ] **Step 1: Replace the static inherited assertion with a failing interaction contract**

Replace the inherited test in `test/example/static_examples_test.dart` with:

```dart
  test('inherited theme repaints dependents when t changes the theme', () async {
    final app = createTuiTestApp(
      const inherited.ThemedApp(),
      width: 64,
      height: 12,
    );

    try {
      await _settleAutofocus(app);
      var frame = _render(app);
      expect(frame, BufferMatchers.containsText('Theme: ocean'));
      expect(frame, BufferMatchers.containsText('Welcome to OpenTUI'));
      final oceanMessage = frame.findText('Welcome to OpenTUI').single;
      expect(frame.getForegroundColor(oceanMessage.x, oceanMessage.y), Color.white);
      expect(
        frame.getBackgroundColor(oceanMessage.x, oceanMessage.y),
        const Color(0.2, 0.4, 0.8),
      );

      app.mockInput.typeText('t');
      await Future<void>.delayed(Duration.zero);
      frame = _render(app);

      expect(frame, BufferMatchers.containsText('Theme: forest'));
      final forestMessage = frame.findText('Welcome to OpenTUI').single;
      expect(
        frame.getForegroundColor(forestMessage.x, forestMessage.y),
        Color.yellow,
      );
      expect(
        frame.getBackgroundColor(forestMessage.x, forestMessage.y),
        const Color(0.1, 0.5, 0.25),
      );
    } finally {
      app.dispose();
    }
  });
```

Add this helper after `_render`:

```dart
Future<void> _settleAutofocus(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
```

- [ ] **Step 2: Run the inherited test and confirm the intended red state**

Run:

```bash
dart test test/example/static_examples_test.dart --concurrency=1 --name 'inherited theme'
```

Expected: FAIL because the current stateless example has no `Theme: ocean`/`Theme: forest` label, focus boundary, key handler, or alternate inherited value.

- [ ] **Step 3: Add named theme snapshots and stateful toggle behavior**

Keep `ThemeData`, `ThemedText`, and `_ThemeSurface`, and replace the current `ThemedApp` declaration with:

```dart
final class _ThemeSnapshot {
  const _ThemeSnapshot({
    required this.name,
    required this.primaryColor,
    required this.textColor,
  });

  final String name;
  final Color primaryColor;
  final Color textColor;
}

class ThemedApp extends StatefulWidget {
  const ThemedApp({super.key});

  @override
  State<ThemedApp> createState() => _ThemedAppState();
}

class _ThemedAppState extends State<ThemedApp> {
  static const _ocean = _ThemeSnapshot(
    name: 'ocean',
    primaryColor: Color(0.2, 0.4, 0.8),
    textColor: Color.white,
  );
  static const _forest = _ThemeSnapshot(
    name: 'forest',
    primaryColor: Color(0.1, 0.5, 0.25),
    textColor: Color.yellow,
  );

  var _isForest = false;

  KeyEventResult _toggleTheme(FocusNode node, KeyEvent event) {
    if (event.isPress && event.character == 't') {
      setState(() => _isForest = !_isForest);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = _isForest ? _forest : _ocean;
    return ThemeData(
      primaryColor: theme.primaryColor,
      textColor: theme.textColor,
      child: Focus(
        autofocus: true,
        onKeyEvent: _toggleTheme,
        child: _ThemeSurface(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ThemedText('Theme: ${theme.name} (press t to toggle)'),
              const ThemedText('Welcome to OpenTUI'),
              const ThemedText('This text uses inherited theme colors'),
            ],
          ),
        ),
      ),
    );
  }
}
```

Do not add a custom `q` or process exit handler; the existing `main()` and ordinary Ctrl+C terminal-session shutdown remain unchanged.

- [ ] **Step 4: Run inherited and framework dependency tests**

Run:

```bash
dart format example/inherited_example.dart test/example/static_examples_test.dart
dart test test/example/static_examples_test.dart --concurrency=1
dart test test/inherited_widget_test.dart --concurrency=1
```

Expected: all tests PASS; both foreground and surface background change after parser-backed `t` input.

- [ ] **Step 5: Commit the inherited-state slice**

```bash
git add example/inherited_example.dart test/example/static_examples_test.dart
git commit -m "feat(examples): demonstrate inherited rebuilds"
```

---

### Task 4: Extend the Pulse Example Test Through Reversal

**Files:**

- Modify: `test/example/pulse_animation_test.dart:1-34`

**Interfaces:**

- Consumes: unchanged `PulseAnimationDemo` and `TuiTestApp.pumpFrame([Duration timestamp])`.
- Produces: deterministic example evidence for `0.00 -> 0.50 -> 1.00 -> 0.50` including the reverse ticker's new time origin.

- [ ] **Step 1: Record the current characterization baseline**

Run:

```bash
dart test test/example/pulse_animation_test.dart --concurrency=1
```

Expected: PASS with the existing initial/midpoint assertions. This is a coverage-only task, so there is no production red state.

- [ ] **Step 2: Replace the partial test with the full ping-pong timeline**

Replace the test body in `test/example/pulse_animation_test.dart` with:

```dart
  test('pulse demo reaches its endpoint and reverses', () {
    final app = createTuiTestApp(
      const PulseAnimationDemo(),
      width: 56,
      height: 18,
    );

    try {
      app.pumpFrame();
      final initial = app.captureFrame().toText();

      app.pumpFrame(const Duration(milliseconds: 350));
      final midpoint = app.captureFrame().toText();

      app.pumpFrame(const Duration(milliseconds: 700));
      final endpoint = app.captureFrame().toText();

      // Completion starts the reverse ticker. Its next frame establishes a
      // fresh time origin, and the following 350 ms frame proves movement.
      app
        ..pumpFrame(const Duration(milliseconds: 1050))
        ..pumpFrame(const Duration(milliseconds: 1400));
      final reversing = app.captureFrame().toText();

      expect(initial, contains('AnimationController demo'));
      expect(initial, contains('controller.value: 0.00'));
      expect(midpoint, contains('controller.value: 0.50'));
      expect(endpoint, contains('controller.value: 1.00'));
      expect(reversing, contains('controller.value: 0.50'));
      expect(midpoint, isNot(initial));
      expect(endpoint, isNot(midpoint));
      expect(reversing, isNot(endpoint));
    } finally {
      app.dispose();
    }
  });
```

- [ ] **Step 3: Run and commit the strengthened characterization**

Run:

```bash
dart format test/example/pulse_animation_test.dart
dart test test/example/pulse_animation_test.dart --concurrency=1
git add test/example/pulse_animation_test.dart
git commit -m "test(examples): verify pulse animation reversal"
```

Expected: PASS and one test-only commit; do not alter `example/pulse_animation.dart` unless the deterministic test exposes a real behavior defect, in which case stop and amend the approved contract before expanding scope.

---

### Task 5: Add the Framework Primitives Example and Black-Box Test

**Files:**

- Create: `example/framework_primitives.dart`
- Create: `test/example/framework_primitives_test.dart`

**Interfaces:**

- Consumes: `ValueNotifier<int>`, `Intent`, `Shortcuts`, `Actions`, `CallbackAction<T>`, `GlobalKey<T>`, `RichText`, `TextSpan`, `PointerListener`, `MouseEvent.localPosition`, `TuiApp.enableMouse()`, and `createTuiTestApp`.
- Produces: `FrameworkPrimitivesApp({required VoidCallback onQuit, Key? key})`, private `IncrementIntent`, and one shared activation path used by Enter, Space, and left-click.

- [ ] **Step 1: Add the black-box behavior test before the example exists**

Create `test/example/framework_primitives_test.dart`:

```dart
import 'dart:io' as io;

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/framework_primitives.dart';
import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';

void main() {
  test('renders notifier state with a styled child span', () async {
    final app = createTuiTestApp(
      FrameworkPrimitivesApp(onQuit: () {}),
      width: 64,
      height: 14,
    );
    try {
      await _settle(app);
      final frame = app.captureFrame();
      expect(frame, BufferMatchers.containsText('Framework primitives'));
      expect(frame, BufferMatchers.containsText('Count: 0'));
      expect(frame, BufferMatchers.containsText('Last activation: none'));

      final count = frame.findText('Count: 0').single;
      final digitX = count.x + 'Count: '.length;
      expect(frame.getForegroundColor(digitX, count.y), Color.yellow);
      expect(frame.getCell(digitX, count.y).isBold, isTrue);
    } finally {
      app.dispose();
    }
  });

  test('Enter, Space, pointer, and q share observable app state', () async {
    var quits = 0;
    final app = createTuiTestApp(
      FrameworkPrimitivesApp(onQuit: () => quits++),
      width: 64,
      height: 14,
    );
    try {
      await _settle(app);

      app.mockInput.pressEnter();
      await _settle(app);
      expect(app.captureFrame().toText(), contains('Count: 1'));
      expect(
        app.captureFrame().toText(),
        contains('Last activation: keyboard'),
      );

      app.mockInput.typeText(' ');
      await _settle(app);
      expect(app.captureFrame().toText(), contains('Count: 2'));

      final activate = app.captureFrame().findText('Activate').single;
      expect(activate.x, greaterThan(0));
      expect(activate.y, greaterThan(0));
      app.mockMouse.click(activate.x, activate.y);
      await _settle(app);

      final pointerFrame = app.captureFrame().toText();
      expect(pointerFrame, contains('Count: 3'));
      expect(
        pointerFrame,
        contains('Last activation: pointer local 0,0'),
      );

      app.mockInput.typeText('q');
      await Future<void>.delayed(Duration.zero);
      expect(quits, 1);
    } finally {
      app.dispose();
    }
  });

  test('real entrypoint enables basic mouse reporting', () {
    final source = io.File(
      'example/framework_primitives.dart',
    ).readAsStringSync();
    expect(
      RegExp(r'app\.enableMouse\(\);').allMatches(source),
      hasLength(1),
    );
    expect(source, isNot(contains('enableMouse(enableMovement: true)')));
  });
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
```

- [ ] **Step 2: Run the new example test and confirm the intended red state**

Run:

```bash
dart test test/example/framework_primitives_test.dart --concurrency=1
```

Expected: FAIL at compilation because the planned `example/framework_primitives.dart` and `FrameworkPrimitivesApp` do not exist. This missing feature is the intended red state; resolve no unrelated diagnostics.

- [ ] **Step 3: Create the runnable framework-primitives example**

Create `example/framework_primitives.dart` with this complete implementation:

```dart
// ignore_for_file: cascade_invocations
// Run with: dart run example/framework_primitives.dart
//
// Press Enter or Space, or click Activate, to increment. Press q to quit.

import 'dart:io' as io;

import 'package:noir/noir.dart';

void main() {
  late final TuiApp app;
  void quit() {
    app.dispose();
    io.exit(0);
  }

  app = runTuiApp(FrameworkPrimitivesApp(onQuit: quit));
  app.enableMouse();
}

final class _IncrementIntent extends Intent {
  const _IncrementIntent();
}

class FrameworkPrimitivesApp extends StatefulWidget {
  const FrameworkPrimitivesApp({required this.onQuit, super.key});

  final VoidCallback onQuit;

  @override
  State<FrameworkPrimitivesApp> createState() =>
      _FrameworkPrimitivesAppState();
}

class _FrameworkPrimitivesAppState extends State<FrameworkPrimitivesApp> {
  final _activationKey = GlobalKey<_ActivationSurfaceState>();
  late final ValueNotifier<int> _count;
  var _lastActivation = 'none';

  @override
  void initState() {
    super.initState();
    _count = ValueNotifier<int>(0)..addListener(_handleCountChanged);
  }

  void _handleCountChanged() {
    if (mounted) setState(() {});
  }

  void _activate(String source) {
    _lastActivation = source;
    _count.value++;
  }

  KeyEventResult _handleQuit(FocusNode node, KeyEvent event) {
    if (event.isPress && event.character == 'q') {
      widget.onQuit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _count
      ..removeListener(_handleCountChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.enter): _IncrementIntent(),
      SingleActivator(LogicalKeyboardKey.space): _IncrementIntent(),
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        _IncrementIntent: CallbackAction<_IncrementIntent>((intent, context) {
          _activationKey.currentState?.activate('keyboard');
          return KeyEventResult.handled;
        }),
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleQuit,
        child: Container(
          color: const Color(0.05, 0.06, 0.1),
          padding: const EdgeInsets.all(2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 1,
            children: [
              const Text(
                'Framework primitives',
                style: TextStyle(
                  color: Color.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              RichText(
                text: TextSpan(
                  text: 'Count: ',
                  style: const TextStyle(color: Color.lightGray),
                  children: [
                    TextSpan(
                      text: '${_count.value}',
                      style: const TextStyle(
                        color: Color.yellow,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              _ActivationSurface(
                key: _activationKey,
                onActivate: _activate,
              ),
              Text('Last activation: $_lastActivation'),
              const Text(
                'Enter/Space/click increments. q quits.',
                style: TextStyle(color: Color.lightGray),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ActivationSurface extends StatefulWidget {
  const _ActivationSurface({required this.onActivate, super.key});

  final void Function(String source) onActivate;

  @override
  State<_ActivationSurface> createState() => _ActivationSurfaceState();
}

class _ActivationSurfaceState extends State<_ActivationSurface> {
  void activate(String source) => widget.onActivate(source);

  void _handlePointerDown(MouseEvent event) {
    if (event.button != MouseButton.left) return;
    activate(
      'pointer local ${event.localPosition.x},${event.localPosition.y}',
    );
  }

  @override
  Widget build(BuildContext context) => PointerListener(
    onPointerDown: _handlePointerDown,
    child: Container(
      width: 18,
      height: 1,
      color: const Color(0.2, 0.4, 0.8),
      child: const Text(
        'Activate',
        style: TextStyle(color: Color.white),
      ),
    ),
  );
}
```

The `GlobalKey` is a read-only application handle: the action calls the mounted activation state's public-to-the-library `activate(String)` method, while pointer input calls that same method after reading `localPosition`. The app State owns and disposes the notifier it creates.

- [ ] **Step 4: Run the primitives behavior and architecture-facing checks**

Run:

```bash
dart format example/framework_primitives.dart test/example/framework_primitives_test.dart
dart test test/example/framework_primitives_test.dart --concurrency=1
dart test test/widgets/shortcuts_actions_test.dart test/framework/global_key_contract_test.dart test/framework/pointer_hit_testing_test.dart test/widgets/rich_text_test.dart --concurrency=1
dart analyze --fatal-infos
```

Expected: all focused tests PASS and analysis reports `No issues found!`.

- [ ] **Step 5: Commit the primitives example slice**

```bash
git add example/framework_primitives.dart test/example/framework_primitives_test.dart
git commit -m "feat(examples): add framework primitives tour"
```

---

### Task 6: Synchronize Documentation, Catalogs, and Verified Test Evidence

**Files:**

- Modify: `README.md:165-192`
- Modify: `example/README.md:14-44`
- Modify: `skills/noir/SKILL.md:102-107`
- Modify: `skills/noir/references/state-and-animation.md:95-160`
- Modify after count is known: `TODO.md:37-46`

**Interfaces:**

- Consumes: the final example filename/control text, the Task 1 zone-reporting contract, the architecture catalog's ``dart run example/<file>.dart`` extraction rule, and the preliminary ordinary-suite count.
- Produces: one catalog entry per shipped Dart example, accurate controls/lifecycle guidance, and release evidence from the exact assembled tree.

- [ ] **Step 1: Add the new example and updated controls to package docs**

In `README.md`, replace the Inherited state item, add Framework primitives
immediately after it, and replace the Scroll box item with these exact entries:

```markdown
- [Inherited state](https://github.com/leoafarias/noir/blob/main/example/inherited_example.dart) — inherited dependencies
  and visible rebuild propagation when `t` switches palettes.
- [Framework primitives](https://github.com/leoafarias/noir/blob/main/example/framework_primitives.dart) —
  notifier ownership, semantic shortcuts/actions, a `GlobalKey`, rich text, and
  localized pointer input in one focused app.
- [Scroll box](https://github.com/leoafarias/noir/blob/main/example/scrollbox_demo.dart) — clipped keyboard/wheel scrolling and
  scrollbars.
```

In `example/README.md`, add exactly one catalog row:

```markdown
| `dart run example/framework_primitives.dart` | `ValueNotifier`, `Shortcuts`/`Actions`, `GlobalKey`, styled `TextSpan`s, and localized pointer activation. |
```

Update the Tips control copy to state:

```markdown
- Examples exit with `Ctrl+C` through the default terminal-session shutdown.
  The layout, Select, ScrollBox, and framework-primitives examples also accept
  `q` through widget-owned quit callbacks. The inherited example uses `t` to
  switch palettes.
```

- [ ] **Step 2: Update the Noir skill's runnable-reference list**

Replace the example filename paragraph in `skills/noir/SKILL.md` with:

```markdown
Inside this repo, `example/` has a runnable reference for every major feature
(`hello.dart`, `counter.dart`, `layout_basics.dart`, `layout_demo.dart`,
`focus_form.dart`, `select_demo.dart`, `scrollbox_demo.dart`,
`textarea_demo.dart`, `pulse_animation.dart`, `inherited_example.dart`,
`framework_primitives.dart`, `chat_demo.dart`, `widgets_tour.dart`) — read one
before inventing a pattern.
```

- [ ] **Step 3: Document animation containment and the dynamic inherited example**

After the `forward()`/`reverse()` Future paragraph in `skills/noir/references/state-and-animation.md`, add:

```markdown
Status listeners run from a stable snapshot. If one throws, Noir reports its
original error and stack trace to the Zone where that notification began,
continues to later listeners, and still completes a naturally finished run.
Ticker callbacks have the same per-frame containment, so one failing ticker
does not starve siblings or suppress the next requested frame.
```

Replace the final InheritedWidget paragraph with:

```markdown
Subclass noir's `InheritedWidget`, expose a static `of(context)` that calls
`context.dependOnInheritedWidgetOfExactType<T>()`, and implement
`updateShouldNotify`. See `example/inherited_example.dart`: press `t` to swap
the inherited ocean/forest palette and visibly rebuild both dependent text and
surface paint. See `example/framework_primitives.dart` for the complementary
`ValueNotifier` listener/ownership pattern.
```

- [ ] **Step 4: Format/check docs and prove the catalog is synchronized**

Run:

```bash
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ scripts/
dart test test/architecture/package_distribution_ownership_test.dart --concurrency=1
git diff --check
```

Expected: format check succeeds, the example-catalog test sees every `example/*.dart` entry exactly once, and diff check emits no output.

- [ ] **Step 5: Run the preliminary ordinary suite and capture its exact count**

Run:

```bash
dart test --concurrency=1
```

Expected: PASS. Record the final `+N` count printed by the test runner; do not infer it by adding test declarations because parameterized tests can change the total.

- [ ] **Step 6: Update only the verified ordinary-test count in the release ledger**

In `TODO.md`, replace `1239 ordinary tests` with the exact numeral printed by
Step 5. Leave the Conductor-terminal evidence wording unchanged until Task 7
actually performs the post-change real-terminal checks. Do not mark
publication, visibility, tag, release, or native limitations differently.

- [ ] **Step 7: Commit the synchronized documentation and evidence**

Run:

```bash
git diff --check
git add README.md example/README.md skills/noir/SKILL.md skills/noir/references/state-and-animation.md TODO.md
git commit -m "docs: synchronize example coverage evidence"
```

Expected: one documentation commit containing the catalog, controls, error contract, and automated evidence count from the assembled tree.

---

### Task 7: Real-Terminal Revalidation, Independent Review, and Final Gates

**Files:**

- Review: every path in `git diff --name-only 6ea7b36..HEAD`
- Modify only if review or verification exposes a concrete defect; include a focused regression test with any behavior fix.

**Interfaces:**

- Consumes: Tasks 1-6, the approved design contract, the repository's authorized command list, the user's explicit authorization for VS Code real-terminal interaction, and `origin/main` as the final diff base.
- Produces: an independently reviewed, interactively revalidated, fully green branch with no unresolved Critical/Important finding and no uncommitted edits.

- [ ] **Step 1: Inspect the assembled branch before review**

Run:

```bash
git status --short --branch
git log --oneline --decorate 6ea7b36..HEAD
git diff --stat 6ea7b36..HEAD
git diff --check 6ea7b36..HEAD
```

Expected: only the planned coherent commits follow `6ea7b36`, the diff contains no native/OpenTUI/generated artifact changes, and diff check emits no output.

- [ ] **Step 2: Revalidate the changed apps in the open VS Code terminal**

Read and follow the `computer-use` skill, then use the already-open VS Code terminal to perform these exact user-visible checks one process at a time:

1. `dart run example/select_demo.dart`: click `Cherry`, observe `You picked: cherry`, then press `q` and confirm shell return.
2. `dart run example/scrollbox_demo.dart`: wheel inside the list, observe a nonzero offset/new visible rows, then press `q` and confirm shell return.
3. `dart run example/inherited_example.dart`: observe ocean/white, press `t`, observe forest/yellow and `Theme: forest`, then use Ctrl+C and confirm status 130/clean terminal restoration.
4. `dart run example/pulse_animation.dart`: observe the value reach `1.00` and move downward, then use Ctrl+C and confirm clean terminal restoration.
5. `dart run example/framework_primitives.dart`: press Enter, press Space, click `Activate`, observe count `3` and a `pointer local ...` source, then press `q` and confirm shell return.

Do not use PTY scripts, raw-mode automation, process-kill probes, signals other than the explicit Ctrl+C interactions above, native builds, or upstream workflows. Record the observed controls and teardown results in `.context/final-example-validation.md`; `.context` stays gitignored.

- [ ] **Step 3: Record the post-change terminal evidence**

Replace the existing Conductor-terminal evidence item in `TODO.md` with this
wording after all five checks in Step 2 succeed:

```markdown
- [x] Authorized Conductor-terminal checks render every cataloged entrypoint.
      Post-change checks confirm Select click selection, ScrollBox wheel
      movement, the inherited `t` palette toggle, pulse completion/reversal,
      and framework-primitives keyboard/pointer activation; each changed path
      returns to a usable shell without a stack trace.
```

Then run and commit the evidence-only change:

```bash
git diff --check
git add TODO.md
git commit -m "docs: record repaired example validation"
```

- [ ] **Step 4: Obtain independent behavior and full-diff review**

Use the `requesting-code-review` workflow to dispatch a fresh reviewer with this exact brief:

```text
Review commits 6ea7b36..HEAD against
docs/superpowers/specs/2026-08-13-example-validation-fixes-design.md and
AGENTS.md. Inspect behavior and the full diff, emphasizing Zone/error-stack
semantics, re-entrant animation completion, ticker snapshot/frame scheduling,
mouse mode ownership, inherited dependency rebuilds, notifier disposal,
GlobalKey/Actions wiring, local pointer coordinates, public API boundaries,
and test quality. Run focused read-only checks as useful. Report findings by
Critical/Important/Minor with file:line evidence; explicitly say when no
Critical or Important findings remain.
```

Expected: a reviewer report with evidence. Do not treat praise or a summary as review completion unless it explicitly addresses unresolved Critical/Important findings.

- [ ] **Step 5: Resolve review findings with the same red/green discipline**

For each valid Critical or Important behavior finding:

1. Add the smallest focused regression assertion in the owning test file.
2. Run only that focused test and confirm the reported defect.
3. Patch the owning implementation/example.
4. Re-run its focused slice and strict analysis.
5. Commit as `fix(<scope>): <observable correction>`.

If a finding requests native, ABI, manifest, OpenTUI gitlink, release, tag,
publication, or manual workflow changes, record it as out of scope and do not
mutate those surfaces. If resolving a valid finding adds or removes tests, run
`dart test --concurrency=1`, replace the ordinary-test numeral in `TODO.md`
with that run's exact count, and include the ledger correction in the finding's
commit. Re-run independent review after every behavior or evidence change
until no Critical or Important finding remains.

- [ ] **Step 6: Run every final release gate on the reviewed tree**

Run each command separately so a failure is attributable:

```bash
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ scripts/
dart analyze --fatal-infos
dart test test/architecture/ --concurrency=1
dart test --concurrency=1
dart run scripts/fetch_opentui_binaries.dart --verify-only
dart pub publish --dry-run
git diff --check origin/main...HEAD
git diff --check
```

Expected:

- format exits 0;
- analysis prints `No issues found!`;
- architecture and ordinary suites PASS, with the ordinary count matching `TODO.md`;
- `native_manifest.json` and all six bundled binaries verify without changing them;
- publish dry-run reports 0 warnings;
- both diff checks emit no output.

- [ ] **Step 7: Audit final scope and worktree cleanliness**

Run:

```bash
git status --short --branch
git diff --name-status origin/main...HEAD
git log --oneline --decorate origin/main..HEAD
```

Expected: a clean worktree; only the approved spec, this plan, Dart animation/example/test changes, documentation, and `TODO.md` differ from `origin/main`; no `external/opentui`, native binary, manifest, generated binding, workflow, tag, or release mutation exists.

- [ ] **Step 8: Prepare the completion handoff**

Report:

- the observable animation containment fix;
- the mouse, inherited-theme, pulse, and framework-primitives example changes;
- the independent review result;
- the exact final ordinary-test count, analyzer issue count, publish warning count, and six-binary verification result;
- the five real-terminal interaction outcomes;
- the commit list and clean-worktree state;
- any remaining native-only limitation without claiming it was repaired.

Do not claim completion if any required gate is stale, skipped, or failing.
