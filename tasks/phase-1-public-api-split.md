# Phase 1 — Three-barrel public API split + closeout

> **Status:** ✅ DONE
> **Cadence:** per-task review (architect → executor → verifier loop completed end-to-end)
> **Commit:** `2f30fd6 feat(phase-1): split public API barrels and closeout`

## Goal

Split the public API into three intentional tiers — application/widget,
advanced companion, and ABI-unstable FFI — and lock the shape with
architectural tests. No backwards-compat shim retained for the prior single
internals barrel.

## Final P9-038 descendant

P9-038 superseded the initial Phase 1 inventory. `lib/noir.dart` is the
supported pre-1.0 application/widget API; `lib/noir_low_level.dart` is the
advanced hosting, renderer/buffer, and supported custom-rendering companion;
and `lib/noir_ffi.dart` is the ABI-unstable raw FFI tier. Concrete Element
implementations remain framework-owned, and the advanced companion may shrink
before 1.0 rather than carrying a stability promise.

## References

- [`GOALS.md`](../GOALS.md) §2 (clean layering), §6 (no fake abstractions, fitness-function enforcement)
- [`tasks/reference-implementation-plan.md`](./reference-implementation-plan.md) §15 Phase 1, §13.2 (rationale for FFI separation)
- [`READ_HERE.md`](./READ_HERE.md) §3 (hard rules — no BC)
- Architect brief (audit trail): workspace scratch (not retained)
- Verifier report (audit trail): workspace scratch (not retained)

## What landed

### Three-barrel structure

- [x] `lib/noir.dart` — high-level public widget/app API (curated, no raw FFI). Untouched in this phase.
- [x] `lib/noir_low_level.dart` — advanced framework/core companion for renderer, buffer, lifecycle-owner, and render-object protocols. Most apps should not need it.
- [x] `lib/noir_ffi.dart` — ABI-unstable raw FFI (OpenTuiBindings, native loading errors, ABI contract, raw handle types). Doc comment establishes "Unstable. ABI breaks on bump."
- [x] Prior internals barrel — **deleted** (no shim retained).

### Closeout (same session)

- [x] Stale references to the deleted internals barrel cleared from `lib/noir.dart` (lines 6, 31) — pointers now correctly target `noir_low_level.dart`.
- [x] Stale reference cleared from `GOALS.md` §7 — now references all three barrels.
- [x] `example/hello.dart` converted to **high-level-only** — imports only `package:noir/noir.dart`. The FFI-heavy demo content was already in `example/bindings_validation.dart` (the intentionally low-level example).
- [x] `parseAnsiBytes` backwards-compat wrapper **deleted** per the no-BC rule. (Discovered during the closeout grep for `compat`/`shim`/etc.)

### Fitness functions landed

- [x] `test/architecture/internals_barrel_split_test.dart` — 6 sub-tests asserting the deleted internals barrel is absent; both new barrels carry the exact symbol mapping; layer exclusivity (low-level rejects `src/ffi/`; ffi rejects everything except `src/ffi/`); both barrels carry tier doc comments.
- [x] `test/architecture/low_level_symbol_monotonic_test.dart` — `noir_low_level.dart`'s exported symbol count must not grow between phases. Baseline at `test/architecture/baselines/noir_low_level_symbols.txt` shrinks as Phases 3/4/5 hide primitives.
- [x] `test/architecture/no_stale_internals_refs_test.dart` — no file mentions the deleted internals-barrel name outside the two architecture tests that assert its absence.

### Test/architecture lock

- [x] `test/architecture/public_api_test.dart` widened (lines 215-217) to reject re-exports of `noir_low_level.dart` and `noir_ffi.dart` from `lib/noir.dart`. All prior assertions remain intact.

## Audit gate (all met)

- [x] `dart format` clean (145 files, 0 changed).
- [x] `dart analyze --fatal-infos` clean.
- [x] `dart test test/architecture/` — 9 passing (3 prior Phase-0 + 6 new from internals_barrel_split).
- [x] `dart test` — 269 passing / 2 skipped (no regression from Phase 0 baseline at the time).
- [x] `low_level_symbol_monotonic` baseline file checked in.
- [x] `example/hello.dart` imports only `package:noir/noir.dart`.
- [x] No deleted internals-barrel reference survives outside intentional architecture-test name-checks.

## Lessons fed forward

- **Architect briefs over-constrained "do not touch file X" can wall off necessary cleanup.** The original Phase 1 brief told the executor not to touch `lib/noir.dart`; the verifier caught two stale comments inside that file that the split itself had orphaned. Now in [`READ_HERE.md`](./READ_HERE.md) §7: prefer blast-radius warnings.
- **The verifier earns its existence.** Caught the stale comments the executor's brief had silenced. Also caught `parseAnsiBytes` BC residue in the compat-drift sweep. Loop discipline matters.
