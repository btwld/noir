# Reference Implementation Playbook

> The standard for evolving OpenTUI Dart from MVP to a reference-quality library.
>
> **Agent entry point:** [`tasks/READ_HERE.md`](tasks/READ_HERE.md) — orchestration workflow, sub-agent roles, fitness functions, and live phase status.
> **Companion docs:** [`tasks/reference-implementation-plan.md`](tasks/reference-implementation-plan.md) (deep review + phased plan), [`tasks/phase-*.md`](tasks/) (per-phase checklists agents tick off), and [`AGENTS.md`](AGENTS.md) / [`CLAUDE.md`](CLAUDE.md) (project context).

---

## 1. What This Is

This document defines what *reference-quality* means for this repo, the process to get there, and the guardrails that prevent drift between the goal and the implementation along the way.

It is the **durable** standard. [`tasks/reference-implementation-plan.md`](tasks/reference-implementation-plan.md) is the **current** refactor (the "why"); [`tasks/READ_HERE.md`](tasks/READ_HERE.md) is the **agent entry point** with the live phase status, sub-agent workflow, and per-phase checklists (the "how"); [`tasks/phase-*.md`](tasks/) are the per-phase trackers (the "what" agents check off as they go). Plans expire; this document does not.

Use it when:
- Starting any new feature, refactor, or widget.
- Reviewing a PR.
- Auditing whether the codebase still matches the standard.

If a section of this file no longer matches what we actually want, fix this file *first*, then change the code.

---

## 2. Quality Standard

### The invariant

> Widgets declare.
> Elements preserve identity.
> RenderObjects layout and record paint.
> Compositor talks to OpenTUI.
> Native layer owns FFI, memory, ABI, and binaries.

A change is reference-quality when it does not blur any line above.

### OpenTUI dependency boundary

`external/opentui` is a read-only Git submodule pinned by Noir.
The configured fork URL records provenance; it does not authorize changes to that repository.
Agents may initialize, read, and verify the pinned source and checked-in
artifacts, but must not edit or advance the submodule, create or push OpenTUI
branches or tags, run OpenTUI workflows, rebuild or replace the six bundled
libraries, or roll the native ABI, manifest hashes, or provenance URLs.

This is an ownership boundary as well as an authorization boundary. A finding
that can only be corrected by changing the pinned OpenTUI source or artifacts
is recorded as a visible `read-only-upstream` limitation. It does not block
Noir-local PR closeout and must not be described as fixed. Reversing this
boundary requires a separate, explicit dependency-strategy decision; ordinary
task authorization is insufficient.

### What "reference" means in practice

- **Semantically correct.** Behavior matches the Flutter reference for
  widget/element/state semantics and the OpenTUI reference (Go / React / core
  packages under `external/opentui/`) for rendering semantics. The intentional
  exception is `GlobalKey`: one key has at most one live binding (including
  across owners), acts as an owner-wide lookup handle, and preserves identity
  through same-parent keyed reconciliation, while moving a keyed subtree to a
  different parent is unsupported and rejected before the incoming child edge
  mutates. We do not invent any other semantics.
- **Layered cleanly.** Each layer earns its existence. No layer reaches across the contract above or below it. Render objects never import `Buffer`; widgets never call FFI directly; the compositor is the only path to OpenTUI in normal operation.
- **Resource-explicit.** Anything that owns native memory has an explicit `dispose()` and is disposed in the matching lifecycle hook (`detach`, `dispose`, `close`). Finalizers are safety nets, not the primary lifecycle.
- **Unicode-first.** No visual width, cursor movement, or selection logic uses `String.length` or `text[i]`. Grapheme clusters and cell width are first-class.
- **Tested for semantics.** Tests assert behavior the API promises, not just that the code path runs. Identity, equality, dependency tracking, dispose, and Unicode are covered, not implied.
- **Documented for semantics.** Public docs explain what the API guarantees, not "the value value." No filler docs.

### Non-negotiables

- No render-object paint method accepts `Buffer` once Phase 4 lands. New render objects use `PaintingContext`.
- No `String.length` or `text[i]` on visual-text paths.
- No native call inside `paint()`.
- No code added against an obsolete contract once the new contract exists. New
  shapes do not coexist with old shapes via shims; old shapes are deleted.

### Core-framework 1.0 boundary

Core-framework 1.0 covers the declarative Widget/Element/RenderObject lifecycle,
state, layout and paint recording, text, focus and input, inherited dependencies,
animation, bundled native loading, and the currently documented widgets and
low-level APIs. All remaining Noir-local correctness gates still apply;
documented limitations that require changes to the read-only OpenTUI dependency
do not block this repository’s PR closeout.

Full OpenTUI-React component and hook parity is post-1.0 work, not a core-framework
1.0 gate. P9-032 and P9-033 activate only when retained, reproducible measurement
violates an explicit workload budget.

Full-root layout and paint recording on dirty frames and transient native-text
preparation during display-list encoding are accepted core 1.0 costs, not performance guarantees.

This boundary does not claim a completed release, pub.dev publication, a stable
version or tag, platform runtime acceptance, or resolution of the documented
read-only native dependency limitations.

---

## 3. Full Process

Every non-trivial change passes through these seven steps. Skip steps only when the change is *literally* trivial (typo, comment fix).

1. **Semantic brief.** One paragraph: what behavior does this guarantee, and to whom? Who calls it? What invariants hold before and after? What does it explicitly *not* do?
2. **Rules.** Bulleted list of invariants this change must preserve: layer boundaries, lifecycle contracts, anti-patterns it must not introduce.
3. **Traceability.** Where is the source of truth? Flutter doc/source link for widget/element semantics, OpenTUI Go/React/core path for rendering semantics, prior local pattern (`file:line`). If there is no reference, that itself is a decision — call it out.
4. **Design.** Which abstraction owns which concern? Is a new layer required, or does an existing one extend? What is the minimum public surface? Where does ownership end and delegation begin?
5. **Implementation.** Build to the design. If the design needs to change, update the design — don't drift the implementation off it silently.
6. **Tests.** Semantic regression tests for everything in steps 1–2. Goldens for any visual change. Lifecycle tests for any native ownership.
7. **Review.** Run the §5 checklist before requesting review.

At a phase boundary, run the phase-start compatibility drift audit and the
Phase Readiness Reviewer from [`tasks/READ_HERE.md`](tasks/READ_HERE.md)
before writing the first architect brief. The readiness review is a plan
quality gate: it checks that the active phase still matches this durable
standard, the code that just landed, and the cleanest executable path forward.

### Verification cadence

After the independent verifier is clean, every non-trivial task runs these
gates before its commit:

```sh
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/
dart analyze --fatal-infos
dart test test/architecture/
<the exact design-scoped semantic test commands named by the accepted design>
```

A coherent checkpoint is one or more verifier-clean task commits about to be
pushed, merged, or handed off together. Run the three serial partitions once
against that exact checkpoint HEAD, in addition to the task gates:

```sh
dart test --exclude-tags process-spawning --concurrency=1
dart test test/bin/health_check_test.dart --concurrency=1
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart test -r expanded test/parity/primitives_parity_test.dart --concurrency=1
```

At phase close and final acceptance, run the complete ordinary suite with
`dart test --exclude-tags process-spawning`. The signal-heavy process lifecycle
suite remains excluded unless the user authorizes that exact host-sensitive
operation. It is required only for a change to its wrapper/process-lifecycle
ownership, not for unrelated framework checkpoints. A user-authorized waiver
may create a clearly labeled, resumable checkpoint, but it cannot waive an
authorized task's own semantic proof or be rewritten as current evidence.

---

## 4. Project Template

Copy this into each PR description (or design doc) and fill it in.

```markdown
## Semantic brief
<one paragraph: what behavior, to whom>

## Reference sources
- Flutter: <link or "n/a — terminal-specific">
- OpenTUI: <external/opentui/... path or "n/a">
- Local:   <file:line or "new">

## Layer ownership
- Owns:    <layer + responsibility>
- Calls:   <allowed downstream layers>
- Exposes: <minimum public surface>

## Invariants preserved
- [ ] <invariant 1>
- [ ] <invariant 2>

## Test plan
- [ ] Semantic:  <what behavior asserted>
- [ ] Golden:    <which visual cases or "n/a">
- [ ] Lifecycle: <native dispose paths or "n/a">

## Acceptance gate
- [ ] All §5 checklist items green
- [ ] No new drift markers (see §6)
```

---

## 5. Review Checklist

Run before merge. Every box must be true or explicitly waived (with a reason recorded in the PR).

### Semantic correctness
- [ ] Behavior matches the cited reference.
- [ ] Identity / equality / key semantics correct where relevant.
- [ ] Dependency registration and removal correct for inherited widgets.
- [ ] `dispose` called in the right lifecycle hook.

### Layering
- [ ] No render object imports `lib/src/core/buffer.dart` (after Phase 4 lands; allowlisted during migration).
- [ ] No widget calls FFI directly.
- [ ] `lib/noir.dart` exports only public API.
- [ ] No layer-skipping shortcuts ("just this once").

### Abstractions
- [ ] Every new abstraction has at least one non-trivial consumer, or a documented reason to exist.
- [ ] No pass-through wrappers that add no semantics.
- [ ] No "future-proofing" hooks without a current caller.

### Tests
- [ ] Semantic tests, not just smoke tests.
- [ ] Unicode coverage for any text path.
- [ ] Dispose tests for any native ownership.
- [ ] Golden + style/cursor sidecars for any visual change.

### Performance
- [ ] No FFI allocation inside `paint()` for steady-state frames.
- [ ] No new `O(tree)` work per frame without a documented reason.

### Drift risk
- [ ] If this starts or materially changes a phase, the compatibility drift
      audit and Phase Readiness Reviewer are clean.
- [ ] No widget written against a contract slated for removal.
- [ ] No "I'll fix the abstraction later" comment.
- [ ] No new backwards-compat shim, deprecated alias, or legacy wrapper
      introduced.
- [ ] No stale reference (path, symbol, doc) survives the change.
- [ ] No task treats an OpenTUI source, gitlink, ABI, workflow, or bundled
      artifact mutation as part of the active Noir program.
- [ ] No bypass of §6 guardrails.

---

## 6. Drift Guardrails

The rules that prevent the goal and the code from diverging while work is in flight.

### Principles

1. **One semantic rule, one owner.** If widget A and render object B both decide whether a cursor blinks, exactly one of them is wrong. Find the owner; the other delegates.
2. **No fake abstractions.** A layer that just forwards is noise. Either it owns something or it is deleted.
3. **No semantic change hidden inside a refactor.** Refactor PRs preserve behavior. Behavior changes are isolated PRs. Mixing them destroys review accuracy.
4. **No new widget on the old contract once the new contract exists.** New code targets the new contract or the work is wasted twice.
5. **Fitness functions enforce; review verifies.** If a rule can be a CI test, it is one.
6. **No backwards-compat shims for the MVP refactor.** When an API shape changes, the old shape is deleted, not wrapped. Flutter-like semantic compatibility is still a goal; backwards compatibility with earlier MVP API shapes is not.
7. **Pinned means read-only.** The OpenTUI fork URL is provenance, not an
   implementation lane. Native-only limitations stay visible without becoming
   prerequisites for the active Noir PR.

### Mechanical guards (CI)

- **Architectural test.** `no_buffer_in_rendering_test.dart` proves files under
  `lib/src/rendering/` do not import `lib/src/core/buffer.dart`. An allowlist
  exists during migration; entries are removed as files migrate. The
  allowlist is the explicit, shrinking drift budget.
- **Public-API test.** `public_api_test.dart` proves `lib/noir.dart` does not
  export FFI types (`OpenTuiBindings`, generated bindings, `ffi/*` types).
- **Public-member seam test.** `public_member_seams_test.dart` proves supported
  high/high+low/FFI signatures close over their selected imports, while the
  exact framework-owned lifecycle and native seams remain `@internal` or
  private, `TuiCanvas` stays non-constructible, and `TextBuffer` keeps its
  named-only empty-creation/logical-length and effect-only write contracts,
  validates supported scalar cells before FFI, exposes encoded native cell
  words without a decoder, states half-open selection, and enforces the exact
  18-method declaration-local raw outcome matrix. It also enforces the
  Buffer-family fixed-width ordered-body locks and whole-file masking ban
  (P9-079) and the direct-access attribute bounds-domain-store pin (P9-081).
- **Semantic public-API docs test.**
  `semantic_public_api_docs_test.dart` prevents the four known authored
  Dartdoc filler families from returning (including the type-level family
  added by the round-3 review); analyzer completeness and review still
  own documentation presence and meaning.
- **Lifecycle test.** `native_lifecycle_test.dart` proves every `RenderObject`
  that allocates a native handle has a `detach()` that disposes it.
- **Focus-manager lifecycle test.** `focus_manager_lifecycle_test.dart` proves
  `BuildOwner` disposes its `FocusManager`, and `FocusManager` cancels its owned
  key-input subscription.
- **Cursor-coordinate contract test.** `cursor_coordinate_contract_test.dart`
  proves the public zero-based terminal-cell cursor API performs the single
  required conversion to native one-based coordinates.
- **Barrel split test.** `internals_barrel_split_test.dart` proves the deleted
  internals barrel does not return and the public, low-level, and FFI barrels
  keep their documented mapping.
- **Low-level surface test.** `low_level_symbol_monotonic_test.dart` proves
  `lib/noir_low_level.dart`'s exported symbol count does not grow between
  phases. The baseline lives at
  `test/architecture/baselines/noir_low_level_symbols.txt` and shrinks as
  primitives move behind cleaner abstractions.
- **Stale internals reference test.** `no_stale_internals_refs_test.dart`
  proves files under `lib/`, `test/`, `example/`, `bin/`, `GOALS.md`, and
  `tasks/*.md` do not mention the deleted internals-barrel name outside the
  architecture tests that assert its absence.
- **Kernel ownership tests.** `app_kernel_ownership_test.dart`,
  `scheduler_ownership_test.dart`, `pipeline_ownership_test.dart`,
  `render_view_ownership_test.dart`, `tui_binding_ownership_test.dart`,
  `render_paragraph_text_layout_test.dart`,
  `input_dispatcher_ownership_test.dart`,
  `input_semantics_ownership_test.dart`, and `integration_harness_test.dart`
  lock the `TuiBinding` / `TerminalSession` / `SchedulerBinding` /
  `PipelineOwner` / `RenderView` / text layout / semantic input /
  `InputDispatcher` split and keep the integration harness on the real parser
  path.
- **Pointer hit-testing test.** `pointer_hit_testing_ownership_test.dart`
  keeps pointer dispatch on render-tree hit testing and guards against the old
  region-manager routing path returning.
- **Render-layout ownership test.** `render_layout_ownership_test.dart` proves
  parent render objects call `child.layout(...)`; they never bypass layout
  ownership by invoking a child's `performBoxLayout(...)` override directly.
- **Render-object attachment ownership test.**
  `render_object_attachment_ownership_test.dart` proves pipeline scheduling
  validates existing ownership, subtree detach removes dirty ownership,
  render-edge removal recursively detaches, root publication follows
  successful attachment, and the package-internal single-child transition
  keeps one authoritative generic edge, enforces zero-or-one cardinality,
  remains non-virtual, and stays outside supported barrels. P9-062 keeps the
  parent getter-only, exposes one cached live unmodifiable view of the private
  ordered child store, and confines generic render-edge mutation to
  `object.dart`. P9-063 also keeps committed BuildOwner detach classification,
  lifecycle publication, and original-error rethrow ordered, with committed
  Flex metadata cleanup paired to its exact removed edge.
- **Geometry extent ownership test.**
  `geometry_extent_ownership_test.dart` keeps the private ScrollBox viewport
  extent guard ahead of equality and storage so layout cannot publish a
  negative controller extent.
- **Native asset ownership test.** `native_assets_ownership_test.dart` keeps
  bundled loading on Dart native assets, preserves `OPENTUI_LIBRARY_PATH` only
  as the exact development override, and guards against reintroducing the
  deleted multi-location native library locator. It also enforces the
  source-level package landing boundary and durable bundled-only
  native-document contract.
- **Package distribution ownership test.**
  `package_distribution_ownership_test.dart` keeps the retained analyzer-only
  source consumer, the public version/changelog, the pinned OpenTUI notice,
  manifest-derived desktop targets, and `.pubignore` source-inclusion intent
  coherent. It also keeps consumer installation and examples, honest known
  limitations, synchronous owning `TuiApp` lifecycle, supported high/low/FFI
  tier roles, and shipped documentation references aligned with package source.
  It does not prove final barrel type closure, an exact staged archive,
  publication, legal conclusion, target runtime behavior, or completion of
  remaining correctness gates.
- **CI workflow ownership test.** `ci_workflow_ownership_test.dart` proves CI
  runs feature work once through the PR event, cancels superseded runs, retains
  native assets, recursive submodules, process-spawning isolation, Go parity
  setup, the 30m/35m safety envelope, and full rendering coverage on Linux,
  macOS, and Windows.
- **Release workflow ownership test.** `release_workflow_ownership_test.dart`
  proves release validates the `native_manifest.json` artifact it uploads and
  downloads, smoke-tests bundled CLI loading on all three desktop operating
  systems, never cancels tag releases, and does not duplicate CI suites or
  restore deleted checksum or stripped-binary paths.
- **Publish workflow ownership test.** `publish_workflow_ownership_test.dart`
  keeps all dormant workflows on directly committed native assets without Git
  LFS setup and requires the repository-controlled pub.dev preflight to reject
  a pushed tag that is not exactly `v` plus the single plain
  `pubspec.yaml` version before any publish dry-run can start.
- **Unicode guard.** `unicode_guard_test.dart` proves there is no known
  code-unit indexing on the visual-text paths in its checked file list,
  spanning widgets, rendering, painting, the core text/buffer files, and
  the text-editing controller. Manual review of `.length` continues until a
  lint exists.
- **GlobalKey internal-API guard.** `global_key_internal_api_test.dart` proves
  `GlobalKey` lifecycle registration and placement validation are `@internal`
  framework wiring owned by `BuildOwner`, not public app API. It keeps
  `GlobalKey` scoped to one live binding, owner-wide lookup, and same-parent
  keyed identity, proves unsupported cross-parent/cross-owner placement is
  rejected at the incoming edge, and prevents inactive retake, activation,
  forced detach, reservation machinery, or the old public
  `registerElement`/`unregisterElement`/`updateWidgetBinding`/
  `updateStateBinding` shape cannot return. It also proves `State.attach`/
  `updateWidget`/`detach` are `@internal` framework wiring (called only by
  `StatefulElement`), not public app API.
- **Element depth and child-ownership guard.**
  `element_depth_buckets_test.dart` keeps dirty build ordering on
  owner-maintained depth buckets, keeps Element parent/depth writes
  owner-controlled, uses identity for inactive membership, and requires each
  built-in child owner to expose one identity-stable live read-only view over
  one private child store without a base mutable list or parallel scalar/list
  state. P9-063 additionally requires every built-in deactivation caller to
  pair its call with committed-state removal from its private child store in
  the same `finally`.
- **Mouse-scroll contract guard.** `mouse_scroll_contract_test.dart` keeps one
  direction/magnitude wheel payload and prevents the removed scalar or axis
  compatibility surface from returning.
- **Parity-roadmap guard.** `parity_roadmap_test.dart` keeps roadmap workflow,
  harness seams, and wire recipes current, with three core completion
  conditions separate from optional P9-039.
- **Positive max-lines guard.** `positive_max_lines_test.dart` keeps paragraph
  and widget `maxLines` positive-or-null and validates before equality,
  storage, or other render updates.
- **Text-editing ownership guard.** `text_editing_ownership_test.dart` keeps
  one controller/listener/selection owner, prevents a second repaint owner,
  retains cursor-sidecar golden coverage, and keeps `TextArea` viewport
  dimensions on one passive State-lifetime holder published by completed
  render layout. It prevents Element traversal, callback/listener ownership,
  partial zero-axis consumption, and public constructor/barrel drift from
  returning on that path.

### Soft guards (review)

- Open `GOALS.md` before opening the PR.
- Open the §4 template and fill it in.
- If you cannot fill in §1 (semantic brief), the change is not ready.

---

## 7. Final Audit

Run before declaring "this is reference-quality."

### Code
- [ ] `dart analyze --fatal-infos` clean.
- [ ] `dart test --exclude-tags process-spawning` clean.
- [ ] All §6 mechanical guards green with empty allowlists.
- [ ] All architecture fitness functions green, with the `low_level_symbol_monotonic` baseline at its terminal minimum.
- [ ] No `TODO` / `FIXME` in public API surface without an owner and a date.

### API
- [ ] `lib/noir.dart` is curated, intentional, documented.
- [ ] `lib/noir_low_level.dart` is documented as the advanced API tier.
- [ ] `lib/noir_ffi.dart` is documented as ABI-unstable FFI surface.
- [ ] Generated bindings are not part of the default import.

### Semantics
- [ ] Identity (`ObjectKey`, `ValueKey`, `UniqueKey`) tested.
- [ ] Inherited-widget dependency tracking tested (including null-aspect removal).
- [ ] Unicode (emoji, CJK, combining marks, ZWJ) tested for cursor, selection, width.
- [ ] Lifecycle: every native resource has a dispose test.

### Architecture
- [ ] Render objects do not import `Buffer`.
- [ ] Only the compositor imports `Buffer` in the normal paint path.
- [ ] `PipelineOwner` owns layout/paint invalidation.
- [ ] `RenderView` is the root render object.
- [ ] `TuiBinding` owns app lifecycle; `TuiApp` is a facade.

### Distribution
- [ ] Native assets ship via build hook (`hook/build.dart`).
- [ ] ABI validation runs at startup with a clear error on mismatch.
- [ ] `OPENTUI_LIBRARY_PATH` override works for development.

If any box is unchecked, this is not yet reference-quality. Say so, fix it, audit again.

---

## 8. Compact Version

> Widgets declare. Elements preserve identity. RenderObjects layout and record paint. Compositor talks to OpenTUI. Native owns FFI, memory, ABI, binaries.
>
> For every change: brief → rules → traceability → design → implementation → tests → review.
>
> One semantic rule, one owner. No fake abstractions. No semantic change hidden inside a refactor. No new widget on the old contract.
>
> Fitness functions enforce; review verifies. Reference-quality means clean layers, explicit lifecycles, Unicode-correct, tested for semantics, documented for guarantees.
