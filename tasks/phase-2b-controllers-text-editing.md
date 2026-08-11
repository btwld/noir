# Phase 2B — TextEditingController + text editing values

> **Status:** ✅ DONE
> **Cadence:** per-task for primitives + deletion; per-phase for widget refactors
> **Audit trail:** workspace-scratch designs/reviews/audits (not retained)

## Goal

Replace the prior bespoke mutable cursor model with a Flutter-style controller/value/selection architecture built on the Phase 2A foundation primitives. The temporary bridge is deleted in this phase.

## References

- [`GOALS.md`](../GOALS.md) §2 (semantic correctness, Flutter-like semantics), §6 (no BC shim — the temporary bridge is deleted, not aliased)
- [`tasks/reference-implementation-plan.md`](./reference-implementation-plan.md) §15 Phase 2 (split rationale — 2A done, 2B is controllers + text editing)
- [`READ_HERE.md`](./READ_HERE.md) §3 (hard rules), §7–9 (sub-agent + per-task/per-phase workflows)
- Reference: Flutter `TextEditingController` / `TextEditingValue` / `TextSelection` / `TextRange` semantics.

## Design decisions

1. **Rendering highlight ranges are `TextHighlight`.** `lib/src/rendering/text_highlight.dart` defines a *styled range* (`start`, `end`, optional fg/bg) used by `RenderParagraph` for search-result highlighting and similar. It is **not** a cursor selection. The `TextSelection` name belongs to the editing layer for the Flutter-style `TextSelection extends TextRange`. Consumers, `lib/noir.dart`, and `public_api_test.dart` point at `TextHighlight`.
2. **`TextEditingValue` uses UTF-16 offsets, not grapheme offsets.** Matches Flutter exactly. Grapheme-aware navigation lives inside `TextEditingController` helper methods and inside widget key handlers. Aligns with Phase 5's coming `TextIndexMap` as the canonical UTF-16↔grapheme mapping. The old `(line, col)` grapheme model is replaced by `(text: String, selection: TextSelection)` where offsets index UTF-16.
3. **Widget migration is hybrid, not strict.** `TextInput` and `TextArea` accept an optional `controller` parameter. If absent, they create one internally and dispose it (Flutter pattern). The `onChanged` callback stays — it is a legitimate simple-case API, not a BC shim. If both `controller` and `value` are passed, that's an assertion failure at construction.

## Tasks (check off as they land)

Each row is one per-task architect → executor → verifier loop unless flagged otherwise.

### 2B.1 — Establish rendering `TextHighlight` naming *(per-task)*
- [x] Architect brief: workspace scratch (not retained)
- [x] Ensure `lib/src/rendering/text_highlight.dart` exposes `TextHighlight`
- [x] Update every consumer in `lib/`, `test/`, `example/`, `bin/`
- [x] Update `lib/noir.dart` export
- [x] Update `test/architecture/public_api_test.dart` allowlist
- [x] Verifier report: workspace scratch (not retained)
- [x] Gates green; commit `f683bee`

### 2B.2 — Add `TextRange` + editing `TextSelection` *(per-task; depends on 2B.1)*
- [x] Architect brief: workspace scratch (not retained)
- [x] `lib/src/foundation/text_range.dart` (new) — `start`, `end`, `isValid`, `isCollapsed`, `textBefore/Inside/After(text)`
- [x] `lib/src/foundation/text_selection.dart` (new) — editing version, `extends TextRange`, `baseOffset`, `extentOffset`, `affinity`
- [x] `test/foundation/text_range_test.dart`, `text_selection_test.dart` — semantic tests
- [x] Export from `lib/noir.dart`; allowlist update
- [x] Verifier report; gates green; commit `feat(phase-2b.2): add TextRange and TextSelection foundation`

### 2B.3 — Add `TextEditingValue` *(per-task; depends on 2B.2)*
- [x] Architect brief: workspace scratch (not retained)
- [x] `lib/src/foundation/text_editing_value.dart` (new) — immutable; `text`, `selection`, `composing`; `copyWith`; `==` / `hashCode`
- [x] `test/foundation/text_editing_value_test.dart` — equality, copyWith, composing range, empty
- [x] Export from `lib/noir.dart`; allowlist update
- [x] Verifier report; gates green; commit `feat(phase-2b.3): add TextEditingValue`

### 2B.4 — Add `TextEditingController` *(per-task; depends on 2B.3)*
- [x] Architect brief: workspace scratch (not retained)
- [x] `lib/src/foundation/text_editing_controller.dart` (new) — `extends ValueNotifier<TextEditingValue>`; `text` getter/setter, `selection` getter/setter, `clear()`, grapheme-aware helper methods (delete prev/next grapheme, move cursor by grapheme)
- [x] `test/foundation/text_editing_controller_test.dart` — listener semantics, programmatic `text=` / `selection=` updates, `clear()`, dispose idempotence, grapheme-aware helpers
- [x] Export from `lib/noir.dart`; allowlist update
- [x] Verifier report; gates green; commit `feat(phase-2b.4): add TextEditingController`

### Mid-phase verification gate (between 2B.4 and 2B.5)
- [x] `dart test test/foundation/` passes — controller + value primitives sound on their own.
- [x] `low_level_symbol_monotonic` baseline did **not** grow (foundation primitives export from `lib/noir.dart`, not `lib/noir_low_level.dart`).
- [x] `public_api_test` allowlist contains the new foundation symbols only.

### 2B.5 — Migrate `TextInput` to controller-driven *(per-phase; depends on 2B.4)*
- [x] Architect brief: workspace scratch (not retained)
- [x] `lib/src/widgets/input.dart` refactor: add optional `controller` param (auto-create + dispose if absent); preserve `onChanged`; assert that `controller` and `value` are not both provided
- [x] Wire keyboard events through `TextEditingController` operations
- [x] Tests: programmatic `controller.text =` repaints field; user input updates controller; `onChanged` fires once per editing transaction; `obscureText` masks rendering only (controller value remains raw); paste applies as one transaction; selection survives rebuild
- [x] Verifier report; gates green; commit `feat(phase-2b.5): migrate TextInput to controller-driven`

### 2B.6 — Migrate `TextArea` to controller-driven *(per-phase; can parallel with 2B.5 if no shared edits)*
- [x] Architect brief: workspace scratch (not retained)
- [x] `lib/src/widgets/text_area.dart` refactor: same shape as 2B.5, multi-line
- [x] Tests: same shape as 2B.5 plus selection across multi-cell graphemes; multi-line paste; cursor at edited position after submit
- [x] Verifier report; gates green; commit `feat(phase-2b.6): migrate TextArea to controller-driven`

### 2B.7 — Delete legacy text-editing bridge *(per-task; depends on 2B.5 + 2B.6)*
- [x] Architect brief: workspace scratch (not retained)
- [x] Delete the bridge file
- [x] Remove the export from `lib/noir.dart`
- [x] Update `test/architecture/public_api_test.dart` allowlist
- [x] Verify no remaining importers across `lib/`, `test/`, `example/`, `bin/`
- [x] Verifier report; gates green; commit `feat(phase-2b.7): delete text-editing bridge`

## Audit gate

- [x] All 7 sub-tasks landed; all task boxes ticked.
- [x] Grep for the deleted bridge class name in `lib/`, `test/`, `example/`, and `bin/` returns zero hits outside of git history.
- [x] `lib/noir.dart` export list contains `TextRange`, `TextSelection` (editing), `TextEditingValue`, `TextEditingController`; no longer contains the deleted bridge or any rendering selection alias.
- [x] `TextHighlight` is the rendering type; cross-references in goldens/tests updated.
- [x] Controller listener fires once per editing transaction (not per char).
- [x] Selection survives rebuild.
- [x] `obscureText` masks rendering only; controller value remains raw.
- [x] Paste applies as one transaction.
- [x] `dart format` / `dart analyze --fatal-infos` / `dart test test/architecture/` / `dart test` all green.

## Compatibility drift audit (phase-start, before 2B.1 work)

- [x] Grep `lib/`, `test/`, `example/`, `bin/` for `compat`, `backward`, `deprecated`, `shim`, `legacy`, `TODO`, `FIXME`, `XXX`, `HACK`, `later`.
- [x] Classify each hit per [`READ_HERE.md`](./READ_HERE.md) §6.
- [x] Record results to workspace scratch (not retained).
- [x] Specifically inspect the text-editing surface (the deleted bridge file, `lib/src/widgets/input.dart`, `lib/src/widgets/text_area.dart`) and rendering highlight docs for any wording that the phase will obsolete.
