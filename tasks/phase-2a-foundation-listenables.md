# Phase 2A — Foundation primitives + controller migration

> **Status:** ✅ DONE
> **Cadence:** per-task for primitives, per-phase for controller refactors
> **Commit:** `29dabba feat(phase-2a): add foundation listenables and migrate controllers`

## Goal

Add local foundation primitives (`Listenable`, `ChangeNotifier`, `ValueNotifier`, `Disposable`, `VoidCallback`) and migrate the five existing bespoke-listener controllers onto the shared primitive. **No legacy aliases retained.**

## References

- [`GOALS.md`](../GOALS.md) §2 (layered cleanly), §6 (principle 6 — no BC shims; no fake abstractions)
- [`tasks/reference-implementation-plan.md`](./reference-implementation-plan.md) §15 Phase 2 (split into 2A + 2B)
- [`READ_HERE.md`](./READ_HERE.md) §3 (hard rules)
- Reference patterns: Flutter `foundation` library (semantic match; **not depended on**); `package:listen` (reference only — not stable enough to anchor public API)

## What landed

### Foundation primitives (new `lib/src/foundation/`)

- [x] `lib/src/foundation/listenable.dart` — abstract `Listenable` (plus `ValueListenable<T>`), `Listenable.merge`, `VoidCallback` typedef.
- [x] `lib/src/foundation/change_notifier.dart` — default `ChangeNotifier` implementation (mutation-during-notification safe; idempotent dispose).
- [x] `lib/src/foundation/value_notifier.dart` — `ValueNotifier<T> extends ChangeNotifier implements ValueListenable<T>`.
- [x] `lib/src/foundation/disposable.dart` — `Disposable` abstract interface.
- [x] Exported from `lib/noir.dart`; public_api_test allowlist updated.

### Controllers migrated

- [x] `ScrollController` (`lib/src/widgets/scroll_box.dart`) — now `extends ChangeNotifier`.
- [x] `Animation` / `AnimationController` (`lib/src/animation/animation.dart`, `animation_controller.dart`) — value listeners use `ChangeNotifier`; status listeners remain a separate notifier.
- [x] `FocusNode` (`lib/src/framework/focus_manager.dart`) — adopts `ChangeNotifier`; focus event listener stays distinct from the change listener.
- [x] `ViewportController` (`lib/src/widgets/viewport.dart`) — adopts `ChangeNotifier`.
- [x] `CursorController` (`lib/src/core/cursor.dart`) — adopts `Disposable` (no listeners; just lifecycle).

### Public typedefs deleted (Hard Rule 1)

- [x] `AnimationListener` — deleted; callers use `VoidCallback` from foundation.
- [x] `FocusChangeListener` — deleted.
- [x] `ScrollListener` — deleted.

### Tests

- [x] `test/foundation/change_notifier_test.dart` — add/remove listeners, duplicate listeners, mutation-during-notification, dispose idempotence.
- [x] `test/foundation/value_notifier_test.dart` — equality semantics, `Listenable.merge` including `removeListener` correctness.

## Audit gate (all met)

- [x] All five controllers use the shared primitive; no controller defines its own `notifyListeners`.
- [x] `low_level_symbol_monotonic` baseline updated to reflect any methods now hidden behind `ChangeNotifier`.
- [x] `dart format` / `dart analyze --fatal-infos` / `dart test` all green.
- [x] `dart test` — 282 passing / 2 skipped (up from 269 with the new foundation suite).

## Verifier catches worth remembering

The Phase 2A verifier found a real `ChangeNotifier` semantic mismatch in the first executor pass (concurrent-modification during notification not handled correctly) — fixed and re-reviewed PASS. Auditor also flagged an architecture test reading `.context/` state and a test helper preserving the deleted `parseAnsiBytes` shape; both fixed before commit.

> Lesson: the loop catches what review-only would miss; the auditor catches what executor + verifier both miss. Worth the cycles.
