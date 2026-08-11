# Phase 7 — Render-tree hit testing

> **Status:** ✅ DONE
> **Cadence:** per-phase review (M)
> **Depends on:** Phase 4 (display-list painting) complete — `RenderObject.hitTest` is the natural extension point.

## Goal

Replace region-based pointer routing (rectangular regions registered with `PointerManager`) with render-tree hit testing. Pointer events carry local coordinates; overlapping targets resolve by paint order; widgets like `Select` no longer walk the element tree manually to compute click positions. **Region-based routing is deleted, not kept as a fallback.**

## References

- [`GOALS.md`](../GOALS.md) §2 / §6 (layer ownership and no compatibility shims)
- [`tasks/reference-implementation-plan.md`](./reference-implementation-plan.md) §10.4 (pointer routing MVP-only)

## Surfaces to introduce

```dart
final class HitTestResult {
  final List<HitTestEntry> path = [];
}

final class HitTestEntry {
  final HitTestTarget target;
  final Offset localPosition;
}

abstract interface class HitTestTarget {
  void handleEvent(MouseEvent event, HitTestEntry entry);
}

final class PointerRouter {
  // routes events through the render-tree hit-test result
}
```

## Tasks (to be decomposed at architect time)

- [x] **Compatibility drift audit** — recorded to workspace scratch (not retained). Specifically inspect: `lib/src/framework/pointer_manager.dart`, `lib/src/widgets/pointer_listener.dart`, `lib/src/widgets/select.dart` (manual element-tree walk for click-to-row), `lib/src/widgets/scroll_box.dart` (wheel handling).
- [x] 7.1 — `HitTestResult`, `HitTestEntry`, `HitTestTarget`, `PointerRouter`.
- [x] 7.2 — `RenderObject.hitTest(HitTestResult, Offset position)` extension.
- [x] 7.3 — Refactor `PointerListener` widget to use render-tree hit testing.
- [x] 7.4 — Refactor `Select` to consume hit-test results (no element-tree walk).
- [x] 7.5 — Refactor `ScrollBox` wheel events to use local hit-test coordinates.
- [x] 7.6 — Native OpenTUI hit grid becomes an optional optimization detail of the new hit tester, not the primary path.
- [x] 7.7 — Delete or rewrite region-contract tests that call `PointerHandle.updateRegion`; replace them with render-tree hit-test coverage.
- [x] 7.8 — Add an architecture guard proving the old primary path cannot return: no paint-time `updateRegion`, no rectangular fallback as pointer dispatch owner, and no `Select` element-tree click walk.
- [x] 7.9 — Update low-level API exports and the low-level symbol baseline so removed region primitives do not survive as a compatibility surface. `Renderer.addToHitGrid` / `checkHit` may remain only as native/debug primitives outside pointer dispatch ownership.

## Hard-rule application

- Region-based pointer routing is **deleted**, not kept as a fallback.
- The element-tree walk in `Select` is **deleted**.
- Native hit-grid usage is not a pointer dispatch path. If retained, it is an optional native/debug primitive and not used as a fallback for widget pointer routing.

## Audit gate

- [x] Overlapping pointer targets route correctly (topmost / last-painted wins).
- [x] Pointer events provide `localPosition`; tested.
- [x] `Select` no longer walks the element tree manually.
- [x] `ScrollBox` receives wheel events only when hit.
- [x] Mouse SGR sequences via integration-harness `mockMouse` drive `PointerRouter` and resolve to the topmost render-tree target end-to-end.
- [x] Architecture guard rejects `PointerHandle.updateRegion`, paint-time pointer region registration, and `Select` click-time `Element` / `RenderObjectElement` walks.
- [x] Low-level pointer region symbols removed or intentionally narrowed; the `noir_low_level` baseline does not preserve deleted region APIs.
- [x] `dart format` / `dart analyze --fatal-infos` / `dart test test/architecture/` / `dart test` all green.

## What landed

- `PointerRouter` replaces region registration as the single widget pointer
  dispatch owner under `BuildOwner`; `PointerManager`, `PointerHandle`, and
  paint-time `updateRegion` routing were deleted.
- `HitTestResult`, `HitTestEntry`, and `HitTestTarget` live in the render
  layer; `RenderBox.hitTest` walks children in reverse paint order and
  `RenderScrollBox` applies viewport clipping plus scroll translation.
- `MouseEvent.localPosition` exposes target-local pointer coordinates while
  `x` / `y` remain absolute parser coordinates.
- `PointerListener` implements `HitTestTarget`; `Select` maps clicks from
  `localPosition`; and `ScrollBox` receives wheel events only through render
  hit testing.
- Region-contract tests were replaced by render-tree hit-test tests covering
  zero-size misses, local coordinates, topmost wins, consumption, and
  `mockMouse` SGR integration. Architecture guards now reject the deleted
  region routing contract.
