# Noir quality standard

This document is the durable standard for Noir. Current release work and
evidence live in [`tasks/release-readiness.md`](tasks/release-readiness.md).

## Architectural invariant

> Widgets declare. Elements preserve identity. RenderObjects layout and record
> paint. The compositor talks to OpenTUI. The native layer owns FFI, memory,
> ABI, and binaries.

A change is reference-quality only when it preserves that boundary.

## Core-framework 1.0 scope

Core 1.0 covers:

- Widget, Element, State, and RenderObject lifecycle and reconciliation.
- Integer-cell layout, display-list painting, text, focus, and input.
- Inherited dependencies, animation, and application lifecycle.
- The documented high-level, low-level, and guarded raw FFI package surfaces.
- Bundled native loading for the supported desktop targets.

Full OpenTUI-React component or hook parity is post-1.0. Full-root layout and
paint recording on dirty frames and grapheme-run encoding during display-list
composition are accepted initial costs, not performance guarantees.
Optimization work begins only after retained, reproducible measurement breaks
an explicit workload budget.

## Quality requirements

- Semantics follow Flutter where Noir intentionally mirrors Flutter and the
  pinned OpenTUI React/core sources where rendering or input behavior is
  concerned.
- Native ownership is explicit. Every native resource has a deterministic,
  idempotent cleanup path; finalizers are fallback protection only.
- Visual text logic is grapheme- and cell-aware. It does not index display
  text with `String.length` or `text[i]`.
- Public validation works in release mode. Assertions are not the only guard
  for externally supplied values.
- Public value objects snapshot mutable inputs when mutation would break
  equality, hashing, layout, or invalidation.
- Tests assert promised results, ordering, and cleanup—not merely that a call
  returns.
- Documentation examples compile against the current API and state limitations
  without promises the implementation does not keep.
- No stale branch, commit, pull-request, tag, package-publication, or phase
  history is presented as current repository state.

## Dependency boundary

`external/opentui` and the six checked-in native libraries are read-only under
ordinary Noir work. Verification is allowed; edits, rebuilds, artifact
replacement, gitlink movement, ABI changes, and provenance changes require a
separate explicit dependency-strategy decision.

The pinned native implementation has a known exact-cursor restoration
limitation on an observed macOS/iTerm path. Noir must still perform
exception-safe best-effort cleanup and keep the limitation visible; it must not
duplicate native ownership with an ANSI save-slot workaround.

## Release gates

### Alpha

An alpha may ship when:

- all documented alpha blockers are closed by focused regression tests;
- format, strict analysis, architecture tests, and the ordinary suite pass;
- native artifacts match the checked-in manifest;
- the publish archive has no warnings and contains only intentional files;
- workflows are immutable-reference pinned and pass static linting;
- README, changelog, version, platform floor, and install instructions agree;
- unresolved native or stable-quality risks are explicit.

An alpha is an API and integration preview. It does not promise production
stability or full platform acceptance.

### Beta

A beta additionally requires closure of correctness findings designated for
beta, current candidate testing on supported Linux, macOS, and Windows
targets, and an explicit decision on any native artifact provenance issue.

### Stable

Stable 1.0 additionally requires closure or deliberate API disposition of
stable-contract findings, beta soak evidence, analysis of the exact publish
archive in a clean consumer, and an explicit decision on the pinned native
terminal-restoration limitation.

Passing tests alone does not advance the release level. The release-readiness
record must link the evidence and list every accepted residual risk.

## Verification principles

- Fitness functions enforce mechanical boundaries; review verifies semantics.
- Tests are added before production fixes for behavior changes.
- A failure path must preserve the primary error while attempting all cleanup.
- No backwards-compatibility shim is added during prerelease cleanup.
- A release, tag, publication, manually dispatched workflow, or native artifact
  change is a separate authorized operation. Automatic push/pull-request CI is
  ordinary verification.
