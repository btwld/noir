# Read Here First

> Single entry point for any agent (or human) joining the OpenTUI Dart
> reference-implementation refactor. **Open this before doing anything else.**

## How to use this file

1. Read this file end-to-end.
2. Read [`GOALS.md`](../GOALS.md) in full — the durable standard.
3. Open the **currently active phase file** from §5 below.
4. Follow the workflow scope rule (§4), then use the sub-agent workflow (§7) and per-task workflow (§8) when it applies.

If you only have time for one paragraph: every phase starts with the compatibility drift audit and Phase Readiness Reviewer. Every non-trivial phase task is architect → executor → verifier → mechanical-checks → commit. Tiny documentation/comment fixes may use a lightweight edit → checks → commit path, but they still cannot introduce stale references. No backwards-compat shims. Fitness functions enforce; review verifies.

---

## 1. What we are building

OpenTUI Dart is a Flutter-like reactive UI framework for terminal applications, built on the OpenTUI native rendering library via Dart FFI. This refactor moves it from MVP/POC to a reference-quality library.

The architectural invariant (from [`GOALS.md`](../GOALS.md) §2):

> Widgets declare. Elements preserve identity. RenderObjects layout and record paint. Compositor talks to OpenTUI. Native owns FFI, memory, ABI, and binaries.

A change is reference-quality when it does not blur any line above.

---

## 2. Source-of-truth documents

| Doc | Role | When to read |
|---|---|---|
| [`GOALS.md`](../GOALS.md) | Durable standard — quality bar, process, drift guardrails, audit checklist | Always before any change |
| [`tasks/reference-implementation-plan.md`](./reference-implementation-plan.md) | Deep review + phased refactor plan (the "why") | For context on why a phase exists |
| [`tasks/READ_HERE.md`](./READ_HERE.md) | This file — orchestration entry point | First |
| [`tasks/phase-*.md`](.) | Per-phase checklist (the "what" and "track") | When working on that phase |
| [`AGENTS.md`](../AGENTS.md) / [`CLAUDE.md`](../CLAUDE.md) | Project context (`CLAUDE.md` links to `AGENTS.md`) | First-time orientation |
| [`tasks/plan.md`](./plan.md) | Separate parity/harness roadmap — runs in parallel, not part of this refactor | Only if working on parity scenes |

Notes under `.context/plans/` are workspace-local scratch history. They can explain why a prior decision happened, but they are not execution authority. If a `.context/plans/` file disagrees with this file, `GOALS.md`, or the active phase file, treat the `.context/plans/` file as stale and update or ignore it.

---

## 3. The hard rules

These supersede any softer guidance elsewhere. From [`GOALS.md`](../GOALS.md) §2/§6:

1. **No backwards-compat shims, deprecated aliases, or legacy barrels.** When an API shape changes, the old shape is **deleted**, not wrapped. Call sites migrate or the work is incomplete.
2. **Flutter-like semantic compatibility is still a goal.** The deliberate
   `GlobalKey` exception in [`GOALS.md`](../GOALS.md) §2 scopes it to one live
   binding (including across owners), owner-wide lookup, and same-parent keyed
   identity; cross-parent movement is unsupported. Backwards compatibility
   with earlier MVP API shapes is not.
3. **Agent context teaches the desired architecture, not preserved old decisions.** Stale references in docs, comments, plans, or `GOALS.md` are drift; fix them, don't annotate them.
4. **No code added against an obsolete contract once the new contract exists.** New shapes do not coexist with old shapes via shims.
5. **The temporary text-editing bridge was deleted in Phase 2B.** Do not reintroduce an internal mutable cursor model; use `TextEditingController` / `TextEditingValue`.
6. **OpenTUI is pinned and read-only for the active program.**
   `external/opentui` is a read-only Git submodule.
   The configured fork URL records provenance; it does not authorize changes to that repository.
   Initialize, inspect, and verify the pinned dependency, but do not edit or
   advance it, create or push OpenTUI refs, run OpenTUI workflows, rebuild or
   replace bundled libraries, or roll the native ABI/manifest. Native-only
   findings remain documented `read-only-upstream` limitations and do not
   block Noir-local PR closeout.

---

## 4. Workflow scope

Use the full architect → executor → verifier loop for:

- phase tasks in `tasks/phase-*.md`
- runtime behavior changes
- public API changes
- architecture boundary changes
- changes to fitness functions, allowlists, or baselines
- phase start, phase closeout, or final acceptance

Use the lightweight path for narrow documentation/comment/checklist cleanup that does not change scope, behavior, API, or architecture:

1. Edit the file directly.
2. Run the relevant checks. If durable docs or phase files changed, include at least `dart test test/architecture/`; if code or tests changed, run the §11 task gates and exact design-scoped semantic tests. The checkpoint and phase-close cadence in §11 still applies.
3. Commit with a professional message if the change is meant to land.

If a "small" edit uncovers a contradiction in `GOALS.md`, this file, the deep plan, or a phase file, stop treating it as lightweight and route the correction through the normal review loop.

No workflow path in this file authorizes a change to the pinned OpenTUI
dependency. Reversing the read-only boundary is a separate dependency-strategy
decision, not a phase-task implementation detail.

---

## 5. Current phase status

Edit this section as phases land. Active phase is **bold**.

- ✅ Phase 0 — [phase-0-blocker-fixes.md](./phase-0-blocker-fixes.md) — *blocker fixes, three fitness functions, CI workflow*
- ✅ Phase 1 — [phase-1-public-api-split.md](./phase-1-public-api-split.md) — *three-barrel public API split + closeout*
- ✅ Phase 2A — [phase-2a-foundation-listenables.md](./phase-2a-foundation-listenables.md) — *foundation primitives + five controller migrations*
- ✅ Phase 2B — [phase-2b-controllers-text-editing.md](./phase-2b-controllers-text-editing.md) — *TextEditingController + text editing values*
- ✅ Phase 3 — [phase-3-kernel-split.md](./phase-3-kernel-split.md) — *`TuiBinding`, `PipelineOwner`, `RenderView`, `InputDispatcher`*
- ✅ Phase 4 — [phase-4-display-list-painting.md](./phase-4-display-list-painting.md) — *`PaintingContext` / `TuiCanvas` / display list / compositor*
- ✅ Phase 5 — [phase-5-text-system.md](./phase-5-text-system.md) — *`TextSpan`, `RichText`, `TextLayout`, `TextIndexMap`*
- ✅ Phase 6 — [phase-6-input-semantics.md](./phase-6-input-semantics.md) — *`Shortcuts`, `Actions`, `Intent`, focus traversal*
- ✅ Phase 7 — [phase-7-hit-testing.md](./phase-7-hit-testing.md) — *render-tree hit testing*
- ✅ Phase 8 — [phase-8-native-assets.md](./phase-8-native-assets.md) — *`hook/build.dart`, `CodeAsset`, ABI validation*
- ✅ Final — [final-acceptance.md](./final-acceptance.md) — *`GOALS.md` §7 reference-quality gate*
- 🚧 **Phase 9 — [phase-9-post-v1-reference-review.md](./phase-9-post-v1-reference-review.md) — post-v1 whole-repository audit and improvement loop**

Phases 0-8 and Final Acceptance remain complete at their audited 2026-05-20
baseline. The reference-quality release commit is tagged
`reference-implementation-v1`. Phase 9 is active as of 2026-07-10 and audits
the substantially changed current tree from that stable foundation.

---

## 6. Compatibility drift audit (runs at every phase start)

Before any phase begins, grep `lib/`, `test/`, `example/`, `bin/` for: `compat`, `backward`, `deprecated`, `shim`, `legacy`, `TODO`, `FIXME`, `XXX`, `HACK`, `later`. Classify each hit:

- **Keep:** Flutter semantic-compat notes; terminal-capability notes; system/native diagnostics; comments that explicitly self-document as *"not a compatibility shim."*
- **Remove or refactor:** old MVP-API-compatibility wrappers; deprecated aliases; temporary shims without a named architectural reason; "fix later" comments without an owner and a date.

If a rule-violating piece of *context* (not just code) is found, update [`GOALS.md`](../GOALS.md) or [`tasks/reference-implementation-plan.md`](./reference-implementation-plan.md) **first**, then change the code.

Audit output: `.context/audits/compat-drift-<phase>.md`.

---

## 7. Sub-agent roles

If the Agent tool's `subagent_type` registry is unavailable (schema bug observed in some sessions), the orchestrator runs the same loop directly with Read/Edit/Grep/Bash. **The discipline matters, not the agent boundary.**

### Architect (`subagent_type: Plan`)
- **Read-only.**
- Produces a one-page design at `.context/designs/<task-slug>.md` using [`GOALS.md`](../GOALS.md) §4 template.
- **Discipline:** prefer *blast-radius warnings* over *hard exclusions*. Telling the executor "do not touch file X" can wall off necessary cleanup that the task itself created (e.g., stale comments after a barrel split). Mark files as "touch only if the task demands it; flag any change" instead.

### Executor (`subagent_type: general-purpose`)
- TDD discipline: failing test → fix → passing test.
- Updates fitness-function allowlists when migrating files across guardrails.
- **No opportunistic refactors outside the design's scope.**
- Skill hints: `test-driven-development`, `dart-flutter`, `verification-before-completion`.

### Verifier (`subagent_type: Explore`, read-only)
- Writes report to `.context/reviews/<task-slug>.md`.
- **Mandatory checks** (every task):
  - Diff matches the design (no scope creep).
  - Tests assert semantics, not just code paths.
  - All fitness functions pass.
  - No new drift markers (TODO/FIXME without owner+date; "fix later" comments).
  - **No backwards-compat shim was introduced** (per Hard Rule 1).
  - **No stale references survive** the change (per Hard Rule 3).
  - For native-resource changes: dispose in the right hook + a dispose test.

### Auditor (`subagent_type: Explore`, read-only, broader scope)
- Runs end-of-phase and once at final acceptance.
- Independent — does not trust executor or verifier reports; re-reads code.
- Reports trajectory of fitness functions (especially: `low_level_symbol_monotonic` baseline going *down*).
- Writes report to `.context/audits/phase-<n>.md`.

---

## 8. Per-task workflow

```
TASK
  │
  ├─ 1. Architect agent  →  .context/designs/<task-slug>.md   (gate: orchestrator approves)
  ├─ 2. Executor agent   →  code + tests (TDD; updates allowlists)
  ├─ 3. Verifier agent   →  .context/reviews/<task-slug>.md   (gate: report clean)
  ├─ 4. Mechanical checks (orchestrator):
  │      dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/
  │      dart analyze --fatal-infos
  │      dart test test/architecture/
  │      <exact design-scoped semantic test commands>
  └─ 5. Commit (orchestrator) — conventional commit referencing plan §
```

If verifier or mechanical checks fail: loop back to executor with the failure report. Do **not** advance to the next task with a known regression.

Before one or more verifier-clean task commits are pushed, merged, or handed
off together, run the three serial checkpoint partitions from §11 once against
that exact checkpoint HEAD. The complete ordinary suite from §11 belongs to
phase close and final acceptance, not every task commit.

---

## 9. Per-phase workflow

```
PHASE START
  │
  ├─ Compatibility drift audit (§6)
  ├─ Phase Readiness Reviewer → .context/audits/phase-readiness-<phase>-<YYYYMMDD>.md  (gate: clean)
  ├─ Run per-task workflow for every task in the phase's checklist
  ├─ Auditor agent  →  .context/audits/phase-<n>.md  (gate: clean)
  └─ Tag commit `phase-<n>-complete`
```

Tick off task boxes in the phase file as work lands. When all tasks are checked and the audit is clean, mark the phase ✅ DONE in §5 above and open the next phase file.

---

## 10. Fitness functions (continuous verification)

These tests are the repository-local fitness functions. The dormant
`.github/workflows/ci.yml` encodes them for future automation, but workflow
execution requires explicit re-enablement and authorization.

| File | Asserts |
|---|---|
| `test/architecture/no_buffer_in_rendering_test.dart` | No render object imports `lib/src/core/buffer.dart`. Allowlist shrinks toward zero through Phase 4. |
| `test/architecture/public_api_test.dart` | `lib/noir.dart` exports only the curated symbol allowlist; no FFI. |
| `test/architecture/public_member_seams_test.dart` | Supported high/high+low/FFI signatures close over their selected imports; exact framework-owned seams stay internal/private; `TuiCanvas` remains the eight-method non-constructible paint vocabulary; `TextBuffer` retains named-only empty creation/logical length and effect-only writes, validates supported scalar cells before FFI, exposes encoded native cell words without a decoder, states half-open selection, and enforces the exact 18-method declaration-local raw outcome matrix, plus the Buffer-family fixed-width ordered-body locks, whole-file masking ban, and direct-access attribute pin. |
| `test/architecture/semantic_public_api_docs_test.dart` *(Phase 9, P9-037)* | The four known authored Dartdoc filler families remain absent; analyzer completeness and semantic review still own presence and meaning. |
| `test/architecture/native_lifecycle_test.dart` | Every `RenderObject` with a native handle declares a `detach()` that disposes it. |
| `test/architecture/focus_manager_lifecycle_test.dart` | `BuildOwner` disposes `FocusManager`, which cancels its owned key-input subscription. |
| `test/architecture/cursor_coordinate_contract_test.dart` | The zero-based cursor API converts exactly once to native one-based coordinates. |
| `test/architecture/internals_barrel_split_test.dart` | Three-barrel split intact; the deleted internals barrel cannot return. |
| `test/architecture/low_level_symbol_monotonic_test.dart` | Advanced-tier surface monotonically shrinks. Baseline: `test/architecture/baselines/noir_low_level_symbols.txt`. |
| `test/architecture/no_stale_internals_refs_test.dart` | No file mentions the deleted internals-barrel name outside the two architecture tests that assert its absence. |
| `test/architecture/app_kernel_ownership_test.dart` | App/session renderer creation and lifecycle ownership stay in the app kernel. |
| `test/architecture/scheduler_ownership_test.dart` | Frame scheduling stays in `SchedulerBinding`; app code does not reintroduce ad-hoc frame loops. |
| `test/architecture/pipeline_ownership_test.dart` | Layout and paint flushing stay behind `PipelineOwner`. |
| `test/architecture/render_view_ownership_test.dart` | `RenderView` remains the app frame root and paint is routed through display-list surfaces. |
| `test/architecture/render_paragraph_text_layout_test.dart` | `RenderParagraph` records `TextLayout` display-list operands instead of owning native `TextBuffer`. |
| `test/architecture/tui_binding_ownership_test.dart` | `TuiBinding` owns the lifecycle graph and `TuiApp` remains only a narrowed facade. |
| `test/architecture/input_dispatcher_ownership_test.dart` | `InputDispatcher` remains the single priority/consume dispatch owner and stays below semantic input routing. |
| `test/architecture/input_semantics_ownership_test.dart` | Built-in widgets consume semantic input APIs and keep raw key parsing out of widget/framework behavior. |
| `test/architecture/pointer_hit_testing_ownership_test.dart` | Pointer dispatch stays on render-tree hit testing, and the old region-manager routing path cannot return. |
| `test/architecture/render_layout_ownership_test.dart` | Parents use `child.layout(...)` instead of calling child layout overrides directly. |
| `test/architecture/render_object_attachment_ownership_test.dart` *(Phase 9, P9-014/P9-057/P9-062/P9-063)* | Scheduling validates existing pipeline ownership; recursive detach clears former-owner work; root and element lifecycle ordering remains failure-atomic; the internal single-child transition keeps one authoritative generic edge, enforces zero-or-one cardinality, stays non-virtual, and remains outside supported barrels; the generic edge has a getter-only parent, one cached live unmodifiable view over one private ordered child store, and `object.dart`-only mutation ownership; and committed BuildOwner detach classification/publication/rethrow ordering plus exact-edge Flex metadata cleanup remain coherent after scheduling errors. |
| `test/architecture/geometry_extent_ownership_test.dart` *(Phase 9, P9-016)* | The private ScrollBox viewport extent rejects negative values before equality or storage; mounted behavior proves its production caller supplies normalized zero extents. |
| `test/architecture/native_assets_ownership_test.dart` | Bundled loading stays on Dart native assets, `OPENTUI_LIBRARY_PATH` remains only the exact development override, the deleted multi-location native library locator cannot return, and the source-level package landing boundary plus durable bundled-only native-document contract remain enforced. |
| `test/architecture/package_distribution_ownership_test.dart` *(Phase 9, P9-036/P9-068/P9-070/P9-073)* | The retained analyzer-only source consumer, public version/changelog, pinned OpenTUI notice, manifest-derived desktop targets, and `.pubignore` source-inclusion intent stay coherent; consumer installation and examples, honest known limitations, synchronous owning `TuiApp` lifecycle, supported high/low/FFI tier roles, and shipped documentation references stay aligned with package source; this does not prove final barrel type closure, an exact archive, publication, legal conclusion, target runtime behavior, or completion of remaining correctness gates. |
| `test/architecture/integration_harness_test.dart` | `createTuiTestApp` keeps integration input on the real ANSI parser path and keeps test-only binding seams out of the public barrel. |
| `test/architecture/ci_workflow_ownership_test.dart` | CI runs feature work once, cancels superseded runs, and preserves native/submodule setup, process isolation, the 30m/35m Go parity envelope, and cross-platform rendering coverage. |
| `test/architecture/release_workflow_ownership_test.dart` | Release preserves tag-safe execution and validates the uploaded/downloaded `native_manifest.json` artifact through three-OS health and bundled-CLI smoke without duplicating CI suites or restoring deleted paths. |
| `test/architecture/publish_workflow_ownership_test.dart` *(Phase 9, P9-072)* | Dormant workflow checkouts stay free of obsolete Git LFS ownership, and pub.dev preflight rejects a pushed tag that is not exactly `v` plus the single plain `pubspec.yaml` version before any publish dry-run. |
| `test/architecture/unicode_guard_test.dart` *(Phase 5)* | No known code-unit indexing patterns on visual-text paths; `.length` drift remains a manual review item per `GOALS.md` until a lint exists. |
| `test/architecture/global_key_internal_api_test.dart` *(Phase 9, P9-006/P9-008/P9-058/P9-059)* | `GlobalKey` lifecycle registration (`register`/`unregister`) and placement validation are `@internal` `BuildOwner` wiring, not public app API; one live binding (including across owners), owner-wide lookup, and same-parent keyed identity remain; unsupported cross-parent/cross-owner placement fails before incoming-edge mutation; inactive retake/activation/forced-detach/reservation machinery cannot return; residual handles unregister during terminal teardown; and the old public `registerElement`/`unregisterElement`/`updateWidgetBinding`/`updateStateBinding` shape stays deleted. Also asserts `State.attach`/`updateWidget`/`detach` are `@internal` framework wiring, not public app API (P9-008). |
| `test/architecture/element_depth_buckets_test.dart` *(Phase 9, P9-034/P9-061/P9-063)* | Dirty build ordering stays on owner-maintained depth buckets; Element parent/depth writes remain owner-controlled; inactive membership uses object identity; each built-in child owner exposes one identity-stable live read-only view over one private child store without base mutable or parallel child state; and every built-in deactivation call stays paired with committed-state private-store cleanup in its own `finally`. |
| `test/architecture/mouse_scroll_contract_test.dart` *(Phase 9, P9-013)* | Mouse wheel input retains one direction/magnitude payload without reviving the removed scalar or axis compatibility surface. |
| `test/architecture/parity_roadmap_test.dart` *(Phase 9, P9-041/P9-060)* | The parity roadmap uses current workflow/harness seams, preserves exact wire recipes, and keeps three core conditions separate from optional P9-039. |
| `test/architecture/positive_max_lines_test.dart` *(Phase 9, P9-025)* | Paragraph and widget `maxLines` stays positive-or-null and is validated before equality, storage, or other render updates. |
| `test/architecture/text_editing_ownership_test.dart` *(Phase 9, P9-024/P9-031)* | Editor widgets share one controller/listener/selection owner, expose no second repaint owner, and retain cursor-sidecar golden coverage; TextArea layout dimensions flow through one passive State-lifetime render-owned pair without Element traversal, callbacks/listeners, partial zero-axis consumption, or public constructor/barrel drift. |

When a phase shrinks an allowlist or a baseline, that's a real deliverable — log it in the phase file's "what landed" section.

---

## 11. Verification commands

After the independent verifier is clean, these gates must be green before each
non-trivial task commit:

```bash
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/
dart analyze --fatal-infos
dart test test/architecture/
<the exact design-scoped semantic test commands named by the accepted design>
```

A coherent checkpoint is one or more verifier-clean task commits about to be
pushed, merged, or handed off together. Run these once against that exact
checkpoint HEAD, in addition to the task gates:

```bash
dart test --exclude-tags process-spawning --concurrency=1
dart test test/bin/health_check_test.dart --concurrency=1
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart test -r expanded test/parity/primitives_parity_test.dart --concurrency=1
```

The tagged wrapper/process-lifecycle suite deliberately exercises signals,
process groups, forced termination, and cleanup races. Run it only when the
user authorizes that exact host-sensitive operation and the active task changes
that ownership; it is not an unrelated framework checkpoint gate.

At phase close and final acceptance, run the complete ordinary suite:

```bash
dart test --exclude-tags process-spawning
```

A user-authorized waiver may create a clearly labeled resumable checkpoint,
but cannot replace an authorized task's own semantic proof. Historical
evidence does not replace a required current command.

---

## 12. Audit trail

Per-task and per-phase outputs live under `.context/` (gitignored — workspace-only):

- `.context/designs/<task-slug>.md` — architect outputs
- `.context/reviews/<task-slug>.md` — verifier outputs
- `.context/audits/phase-<n>.md` — per-phase auditor outputs
- `.context/audits/phase-readiness-<phase>-<YYYYMMDD>.md` — pre-phase readiness review outputs
- `.context/audits/compat-drift-<phase>.md` — phase-start drift audits
- `.context/audits/conformance-<scope>-<date>.md` — Standards Conformance Auditor outputs (see below)

These are working files; commits reference them in messages but they don't ship with the repo.

### Phase Readiness Reviewer (pre-phase reviewer)

Runs after the compatibility drift audit and before the first architect brief for a phase. It verifies the active phase plan is still correct, current, executable, and the cleanest approach given the durable goal and the code that just landed.

- **Prompt + invocation notes:** [`tasks/agents/phase-readiness-reviewer.md`](./agents/phase-readiness-reviewer.md)
- **When to run:** start of every phase; whenever durable docs or the active phase file change before implementation.
- **Constraint:** read-only — flags blockers and simplification opportunities; fixes route through the per-task workflow.

### Standards Conformance Auditor (the auditor's auditor)

Distinct from the per-phase Auditor described in §7. The Standards Conformance Auditor verifies that the **durable docs themselves** ([`GOALS.md`](../GOALS.md), [`AGENTS.md`](../AGENTS.md), this file, the deep plan, every phase file) are internally consistent and agree with the code on disk.

- **Prompt + invocation notes:** [`tasks/agents/standards-conformance-auditor.md`](./agents/standards-conformance-auditor.md)
- **When to run:** end of every phase (after the per-phase Auditor reports clean); before any commit that crosses a phase boundary; whenever a durable doc is edited; before final acceptance.
- **Constraint:** read-only — flags drift, does not fix it. Follow-ups route through the per-task workflow.

---

## 13. When to update which file

| If you… | Update… |
|---|---|
| land a task within a phase | tick its box in the phase file |
| land a phase | mark it ✅ DONE here in §5 and add a brief "what landed" section in the phase file |
| change the durable standard or the hard rules | edit [`GOALS.md`](../GOALS.md) **first**, then update this file |
| change the refactor's scope or sequencing | edit [`tasks/reference-implementation-plan.md`](./reference-implementation-plan.md) and the phase files |
| discover a new drift vector | add a fitness function under `test/architecture/`, then add it to §10 here |

> *"If a section of this file no longer matches what we actually want, fix this file first, then change the code."* — [`GOALS.md`](../GOALS.md) §1
