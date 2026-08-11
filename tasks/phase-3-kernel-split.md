# Phase 3 — Kernel split

> **Status:** ✅ DONE
> **Cadence:** per-phase review (recommend isolated git worktree — big mechanical change)
> **Depends on:** Phase 2B complete.

## Goal

Split `TuiApp`'s monolithic lifecycle ownership into a binding/owner/session graph that matches Flutter's `WidgetsBinding` / `SchedulerBinding` / `PipelineOwner` / `RenderView` structure. `TuiApp` becomes a thin convenience facade. **Old responsibilities are deleted, not retained as `TuiApp` forwarders.**

## References

- [`GOALS.md`](../GOALS.md) §2 (the invariant — *"compositor talks to OpenTUI"* — but the kernel split is the prerequisite for the compositor to *exist*)
- [`tasks/reference-implementation-plan.md`](./reference-implementation-plan.md) §15 Phase 3, §4.2 (TuiApp does too much), §4.4 (no PipelineOwner), §4.5 (no RenderView)
- [`READ_HERE.md`](./READ_HERE.md) §3 (hard rules — no `TuiApp` legacy forwarder)

## Surfaces to introduce

- `TuiBinding` — global coordinator, owns app lifecycle (replaces `TuiApp`'s ownership).
- `TerminalSession` — native renderer, terminal modes, resize, suspend/resume, cleanup.
- `SchedulerBinding` — frame timing, animation ticks, post-frame callbacks (replaces the microtask frame loop).
- `BuildOwner` — already exists; integrated into binding graph.
- `PipelineOwner` — layout, paint, compositing queues (currently absent; full-frame work).
- `RenderView` — root render object; owns terminal constraints and frame composition (currently `TuiApp._drawFrame()` searches descendants).
- `InputDispatcher` — multi-layer event dispatch that absorbs or replaces the current `InputManager` priority/subscription semantics; no second dispatch path survives.
- `runTuiApp` — top-level high-level entry point that runs a widget through `TuiBinding` and is exported from `lib/noir.dart`.

## Tasks (to be decomposed at architect time)

- [x] **Compatibility drift audit** — recorded to workspace scratch (not retained). Specifically inspect `lib/src/app/app.dart`, `lib/src/core/input.dart` (`InputManager`), `lib/src/core/renderer.dart`, signal-handling code.
- [x] **Architect a worktree strategy** — continue in this Conductor isolated git worktree per [`READ_HERE.md`](./READ_HERE.md) recommendation for big phases.
- [x] Decompose into per-task architect briefs (rough sequencing):
  - [x] 3.1 — `TerminalSession` extracted from `TuiApp`
  - [x] 3.2 — `SchedulerBinding` (FPS-aware, replaces microtask loop)
  - [x] 3.3 — `PipelineOwner` with `scheduleLayout` / `schedulePaint` / `flushLayout` / `flushPaint`
  - [x] 3.4 — `RenderView` as root render object
  - [x] 3.5 — `InputDispatcher` (multi-layer key + mouse + paste + capability dispatch, preserving current priority/consume semantics or replacing them in one step)
  - [x] 3.6 — `TuiBinding` ties it all together and introduces then exports `runTuiApp`
  - [x] 3.7 — `TuiApp` facade deletion/cleanup; old lifecycle-style methods are **deleted** or intentionally narrowed (no aliases)
  - [x] 3.8 — Integration test harness (`createTuiTestApp`): real `TuiBinding`, real `StdinInputDriver`, real `SchedulerBinding` frames, `mockInput.typeText` / `mockMouse.click` emitting ANSI bytes through the parser, and `captureFrame()` returning a `CapturedBuffer`.

## What landed

- 3.1 — `TerminalSession` now owns renderer creation/ownership, terminal setup/restore, stdin driver lifecycle, process signal subscriptions, resize handling, and mouse/Kitty renderer commands.
- 3.2 — `SchedulerBinding` now owns frame request coalescing, frame timestamps, pending-frame cancellation, target-FPS pacing, and the app-owned `TickerScheduler`.
- 3.3 — `PipelineOwner` now owns render-object layout/paint invalidation and flush boundaries; clean skipped-paint frames preserve existing pointer hit regions.
- 3.4 — `RenderView` is now the explicit app frame root and owns terminal constraints/root child composition. Binding frames and `TestElementHost` no longer use per-frame descendant render-object lookup; top-level render-object insertions bubble through `BuildOwner` to the root view.
- 3.5 — `InputDispatcher` now owns key, mouse, paste, and terminal capability dispatch, including priority ordering, consume semantics, and frame scheduling callbacks. `InputManager` remains the advanced binding/widget integration facade, while ordinary applications register app-level key, mouse, and paste handlers through `TuiApp`; stdin, terminal session startup, focus routing, pointer routing, and binding frame scheduling flow through the dispatcher. Capability/query responses are parsed as internal capability inputs instead of entering user key/mouse/paste streams.
- 3.6 — `TuiBinding` now owns the app lifecycle graph: scheduler, input manager/dispatcher, build owner, render view, terminal session, root mount/unmount, frame body, resize, capability commands, and disposal. Public `runTuiApp` constructs the binding, mounts the widget, and returns a private-constructor `TuiApp` lifecycle facade.
- 3.7 — `TuiApp` is now the narrowed final facade returned by `runTuiApp`: it owns app-priority key/mouse/paste registrations, terminal input-mode controls, headless state, and idempotent disposal. It exposes no public constructor, raw input/build-owner/renderer getters, root mounting, or resize seam; advanced tests and embedders use `TuiBinding` directly when those low-level capabilities are required.
- 3.8 — `createTuiTestApp` now provides an integration-tier harness over the source-private `runTuiAppForTesting`, with real `TuiBinding` frames, `StdinInputDriver` byte parsing, SGR mouse and Kitty CSI-u mocks, resize, signal cleanup, shutdown, and `CapturedBuffer` frame capture.

## Remaining work

- Phase 3 is closed. Continue with Phase 4 display-list painting.

## Hard-rule application

- The monolithic `TuiApp` lifecycle is **deleted**, not preserved alongside the new binding.
- `Element.findDescendantRenderObject(root)` lookup pattern is **deleted** — `RenderView` is the explicit root.
- Microtask frame loop is **deleted** — `SchedulerBinding` is the only path.
- The current `InputManager` subscription bus is **migrated into or replaced by** `InputDispatcher` — `InputManager` and `InputDispatcher` do not survive as parallel event paths.

## Audit gate

- [x] `runTuiApp(app)` works end-to-end.
- [x] `runTuiApp(app)` returns a narrowed `TuiApp` facade that mounts and disposes the app.
- [x] Headless mode still works.
- [x] Signal cleanup (SIGINT, SIGTERM) still works.
- [x] Resize correctly updates terminal constraints (and `MediaQuery` if landed by then).
- [x] Animation does not busy-loop (`SchedulerBinding` ticks only when there's a registered ticker).
- [x] App/event-loop tests use the integration harness (`createTuiTestApp`) to drive `runTuiAppForTesting` end-to-end and assert: signal cleanup, resize propagation, scheduler idle/ticker behavior, `RenderView` root layout, input dispatch ordering (parser → dispatcher → handler), headless mode, and binding shutdown.
- [x] Mouse SGR and Kitty CSI-u byte sequences round-trip through the parser to handlers via `mockMouse` / `mockInput`.
- [x] App/session `Renderer` creation goes through `TerminalSession`. The existing `Buffer` scratch-renderer path is not part of the app lifecycle and remains explicitly deferred to Phase 4.
- [x] `dart format` / `dart analyze --fatal-infos` / `dart test test/architecture/` / `dart test` all green.
