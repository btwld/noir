# Final Acceptance — Reference-quality gate

> **Status:** ✅ DONE
> **Cadence:** full user review
> **Depends on:** All Phases 0 → 8 complete.

## Goal

Run [`GOALS.md`](../GOALS.md) §7 in full + a final compatibility-drift sweep. Every box ticked or explicitly waived with a recorded reason.

## References

- [`GOALS.md`](../GOALS.md) §7 (the canonical final audit checklist)
- [`READ_HERE.md`](./READ_HERE.md) §6 (compat drift audit — runs one last time here)

## Final auditor brief

The final auditor is an `Explore` (read-only) agent. Inputs:

- [`GOALS.md`](../GOALS.md) §7 in full
- All phase files (`tasks/phase-*.md`) — every task box ticked, every audit gate met
- All phase audit reports (workspace scratch, not retained)
- Current code state (re-read; do not trust prior reports)

Output: final-acceptance audit report (workspace scratch, not retained) — every §7 item rated pass / waived (with reason) / fail.

## §7 checklist (mirrors `GOALS.md` §7 — keep in sync)

### Code
- [x] `dart analyze --fatal-infos` clean.
- [x] `dart test --exclude-tags process-spawning` clean.
- [x] All §6 mechanical guards green with **empty allowlists** (no buffer-import allowlist entries remaining; etc.).
- [x] All architecture fitness functions green, with `low_level_symbol_monotonic` baseline at its **terminal minimum** (advanced-tier surface shrunk to its final shape).
- [x] No `TODO` / `FIXME` in public API surface without an owner and a date.

### API
- [x] `lib/noir.dart` is curated, intentional, documented.
- [x] `lib/noir_low_level.dart` is documented as the advanced API tier.
- [x] `lib/noir_ffi.dart` is documented as ABI-unstable FFI surface.
- [x] Generated bindings are not part of the default import.

### Semantics
- [x] Identity (`ObjectKey`, `ValueKey`, `UniqueKey`) tested.
- [x] Inherited-widget dependency tracking tested (including null-aspect removal).
- [x] Unicode (emoji, CJK, combining marks, ZWJ) tested for cursor, selection, width.
- [x] Lifecycle: every native resource has a dispose test.

### Architecture
- [x] Render objects do not import `Buffer`.
- [x] Only the compositor imports `Buffer` in the normal paint path.
- [x] `PipelineOwner` owns layout / paint invalidation.
- [x] `RenderView` is the root render object.
- [x] `TuiBinding` owns app lifecycle; `TuiApp` is a facade.

### Distribution
- [x] Native assets ship via build hook (`hook/build.dart`).
- [x] ABI validation runs at startup with a clear error on mismatch.
- [x] `OPENTUI_LIBRARY_PATH` override works for development.

### Compatibility drift (one final sweep)
- [x] Grep `lib/`, `test/`, `example/`, `bin/` for `compat`, `backward`, `deprecated`, `shim`, `legacy`, `TODO`, `FIXME`, `XXX`, `HACK`, `later`.
- [x] Zero unresolved hits in the "remove or refactor" classification (per [`READ_HERE.md`](./READ_HERE.md) §6).
- [x] Grep for the deleted text-editing bridge class name returns zero (only in git history).
- [x] Grep for the deleted internals-barrel name returns only the two architecture tests that assert its absence.

## When green

This file is ✅ DONE. [`READ_HERE.md`](./READ_HERE.md) §5 records the v1 final
acceptance, and the release commit is tagged `reference-implementation-v1`.
That tagged v1 baseline was reference-quality at acceptance. Current-tree
acceptance after the substantial post-v1 changes is owned by active Phase 9;
the separate parity roadmap remains in `tasks/plan.md`.
