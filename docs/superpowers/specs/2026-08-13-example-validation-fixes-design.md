# Noir example-validation fixes

## Context and selected approach

The release tree passes its existing gates, but the deep example review found
two observable defects and several places where the shipped examples do not
prove the behavior they advertise:

- an exception from an animation status listener can prevent later listeners,
  leave the run future incomplete, starve sibling tickers, and suppress the
  next frame request;
- the Select and ScrollBox entrypoints advertise mouse input without enabling
  terminal mouse reporting;
- the inherited-state example never changes its inherited value;
- the pulse example test stops before completion and reversal;
- pointer behavior and several public framework primitives are tested only in
  isolated widget suites, not through their example applications.

Three approaches were considered:

1. **Defects only:** repair animation dispatch and add the two missing
   `enableMouse()` calls. This is the smallest patch, but it leaves the example
   promises and review probes outside the shipped regression suite.
2. **Release-bounded repair (selected):** fix both defects, promote every
   demonstrated probe into the ordinary suite, make the inherited example
   visibly dynamic, strengthen the pulse test, and add one cohesive framework
   primitives example. This closes the findings without changing architecture
   or inventing a separate demo for every exported value type.
3. **Exhaustive example expansion:** add a runnable entrypoint for every public
   type. This would create artificial examples, duplicate unit coverage, and
   expand the alpha release surface without a user-facing need.

The selected approach preserves Noir's ownership boundaries and keeps the
work within Dart framework, example, test, and documentation files. It does
not touch `external/opentui`, native binaries, ABI, manifests, generated
bindings, release operations, or package compatibility shims.

## Observable behavior contract

### Animation error isolation

Animation notifications follow the error-isolation convention already
established by `ChangeNotifier`:

- Status listeners are invoked from a stable snapshot in registration order.
- If one status listener throws, its original error and stack trace are
  reported to the `Zone` current when status notification begins.
- A failing status listener does not prevent later status listeners from
  running.
- Reaching an endpoint completes that run's `Future<void>` even when a status
  listener fails.
- The controller still reaches the correct terminal value and status and is no
  longer animating after natural completion.

The ticker scheduler provides the same containment at the frame boundary:

- Every ticker in the active snapshot gets an opportunity to tick even when a
  sibling callback throws.
- Each ticker failure is reported with its original stack trace to the `Zone`
  current when `handleFrame` begins.
- If active tickers remain after the snapshot is processed, exactly one next
  frame request is made.
- Stopping or disposing a ticker during a callback retains the existing
  snapshot and lifecycle semantics.

No public signature changes. The compatibility change is limited to replacing
synchronous exception escape and scheduler starvation with zone reporting and
continued dispatch, matching the existing notifier policy and Flutter-style
animation listener behavior.

### Mouse-capable example entrypoints

`select_demo.dart` and `scrollbox_demo.dart` retain their widget trees and
keyboard behavior. Their real-terminal `main()` functions additionally call
`app.enableMouse()` exactly once after `runTuiApp` returns. Pointer movement
reporting remains disabled because these examples need click and wheel events,
not hover or drag movement.

Shipped tests prove both layers:

- the entrypoint source enables renderer-backed mouse reporting;
- injected left-click selects and confirms a Select option;
- an injected wheel event inside ScrollBox changes its offset;
- mouse selection and submission in the focus form continue to work.

### Dynamic inherited-state example

`ThemedApp` becomes stateful while preserving its existing default appearance
and constructor usability. It owns two named theme snapshots:

- ocean: the existing `Color(0.2, 0.4, 0.8)` surface and `Color.white` text;
- forest: a `Color(0.1, 0.5, 0.25)` surface and `Color.yellow` text.

The root is focusable. Pressing `t` toggles the active `ThemeData`, updates a
visible mode label, and causes dependent `ThemedText` and `_ThemeSurface`
widgets to rebuild through `updateShouldNotify`. Ctrl+C remains the ordinary
terminal-session exit; the example does not add a custom process-exit path.

The regression test starts from the existing ocean colors, sends the parsed
`t` key through `createTuiTestApp`, and verifies both foreground and background
cells change to the forest colors. This tests the actual example rather than a
separate synthetic inherited widget.

### Complete pulse behavior

The pulse example remains unchanged. Its example test advances deterministic
scheduler timestamps far enough to prove all of the following:

- initial value `0.00`;
- midpoint `0.50`;
- completed endpoint `1.00`;
- reverse movement back to `0.50`.

### Framework primitives example

Add `example/framework_primitives.dart` as one focused advanced high-level
example rather than a checklist of unrelated entrypoints. It demonstrates:

- `ValueNotifier<int>` as the `ChangeNotifier`-based external state owner;
- listener registration, widget repaint, and deterministic disposal;
- a custom `Intent` wired through `Shortcuts` and `Actions`;
- a `GlobalKey` used by the semantic action to address the stateful activation
  surface;
- `RichText` and child `TextSpan` styling;
- `PointerListener` using `MouseEvent.localPosition`;
- real-terminal mouse enablement and explicit `TuiApp` cleanup before `q`
  exits.

Enter or Space invokes the semantic action, a left-click invokes the same
activation path, and each activation increments the notifier and reports its
source. The example test proves initial rendering and span styling, keyboard
activation, pointer activation, notifier-driven rebuilds, and one clean quit
callback.

`TerminalCapabilities` is not forced into this high-level example: runtime
detection is an advanced `Renderer` extension owned by
`package:noir/noir_low_level.dart` and is already exercised by the supported
low-level package-consumer fixture and architecture checks. A contrived value
snapshot in a high-level widget would not add behavioral evidence.

## Files and ownership

Expected production and example files:

- `lib/src/animation/animation_controller.dart`
- `lib/src/animation/ticker.dart`
- `lib/src/animation/animation.dart` (contract documentation only, if needed)
- `example/select_demo.dart`
- `example/scrollbox_demo.dart`
- `example/inherited_example.dart`
- `example/framework_primitives.dart`

Expected tests:

- a focused animation listener/scheduler isolation test under `test/animation/`;
- promoted pointer and inherited-state cases under `test/example/`;
- the strengthened pulse test;
- a focused framework-primitives example test.

Documentation and release evidence that must stay synchronized:

- `example/README.md`
- `README.md`
- `skills/noir/SKILL.md`
- `skills/noir/references/state-and-animation.md`
- `TODO.md`, with the final ordinary-test count from the verified tree.

No widget may call FFI. All pointer behavior remains in `PointerListener`, all
animation scheduling remains in the animation layer, and examples use only
supported package barrels.

## Test-first acceptance criteria

Each behavior change begins with a focused test that is observed failing for
the intended reason before production code changes.

The change is acceptable only when:

1. A throwing status listener is zone-reported, later listeners run, and the
   run future completes.
2. A throwing ticker callback is zone-reported, a sibling ticker advances, and
   the scheduler requests another frame while work remains.
3. Select and ScrollBox entrypoint tests fail without and pass with mouse
   enablement; their pointer interaction tests pass.
4. The actual inherited example changes dependent foreground and background
   paint after `t`.
5. The pulse example reaches its endpoint and reverses under deterministic
   timestamps.
6. The primitives example exercises keyboard and pointer activation through
   the same notifier-backed state transition and disposes all owners.
7. Existing example, animation, input, lifecycle, and architecture tests remain
   green.
8. Format, strict analysis, architecture tests, the full ordinary suite,
   binary verification, publish dry-run, and `git diff --check` all succeed on
   the final tree.
9. An independent reviewer reports no unresolved Critical or Important
   behavior or diff finding.

There are no open design decisions. Tagging, publishing, native builds,
artifact changes, and manual workflow operations remain outside this change.
