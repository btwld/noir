# Phase 0 — Blocker fixes + drift guardrails + CI

> **Status:** ✅ DONE
> **Cadence:** per-task review
> **Commit:** `d0adb38 feat(phase-0): blocker fixes drift guardrails and CI`

## Goal

Fix the P0 blocker semantics from the reference-implementation review and land the architectural fitness functions + CI workflow that prevent regression.

## References

- [`GOALS.md`](../GOALS.md) §2 (quality standard), §6 (drift guardrails)
- [`tasks/reference-implementation-plan.md`](./reference-implementation-plan.md) §3 (critical blocking issues)
- [`READ_HERE.md`](./READ_HERE.md) §10 (fitness functions)

## What landed

### P0 fixes

- [x] **P0.1** — missing `raw_keyboard_listener` export — confirmed absent (no export, no file)
- [x] **P0.2** — `ObjectKey` uses `identical()` not `==` — `lib/src/framework/key.dart:64-70` (also `identityHashCode` for `hashCode`)
- [x] **P0.3** — `InheritedElement.removeDependent` null-aspect bug —
      `lib/src/framework/element.dart` (`InheritedElement.removeDependent`)
      uses `containsKey` instead of the remove return value
- [x] **P0.4** — `TextInput.obscureText` stores raw text —
      `lib/src/widgets/input.dart` (`TextInput` contract and
      `_RenderTextInput.paint`); tests at
      `test/widgets/text_input_obscure_test.dart`
- [x] **P0.5** — `RenderParagraph` no longer owns a native `TextBuffer`;
      Phase 5 replaced it with `TextLayout` display-list operands, locked by
      `test/architecture/render_paragraph_text_layout_test.dart`.
- [x] **P0.7** — SDK floor `>=3.10.0` — `pubspec.yaml:7`; CI pins matched in `release.yml:25` and `ci.yml:21`

### Deferred

- ⏸ **P0.6** — scratch `Renderer` in clipped paint (`lib/src/core/buffer.dart`) — deferred to **Phase 4**, where display-list painting deletes the entire clipped scratch-renderer code path. Locally papering over it would be wasted work.

### Fitness functions landed

- [x] `test/architecture/no_buffer_in_rendering_test.dart` — render objects must not import `Buffer`. Allowlist starts at 8 files (all current importers); shrinks through Phase 4.
- [x] `test/architecture/public_api_test.dart` — `lib/noir.dart` exports only the curated symbol allowlist; no FFI types.
- [x] `test/architecture/native_lifecycle_test.dart` — every `RenderObject` subclass holding a native handle declares a `void detach()` override.

### CI workflow

- [x] `.github/workflows/ci.yml` — was configured at Phase 0 to run format,
      analysis, architecture, and the full suite on pushes/PRs. Repository
      workflow execution is now dormant unless explicitly re-enabled.

## Audit gate (all met)

- [x] `dart analyze --fatal-infos` clean.
- [x] `dart test` clean.
- [x] Three architecture fitness functions green.
- [x] CI workflow was configured for pushes/PRs at Phase 0; its current dormant
      execution policy is owned by `AGENTS.md`.
- [x] No semantic bug remains untested.
