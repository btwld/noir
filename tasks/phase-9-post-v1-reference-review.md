# Phase 9 — Post-v1 reference review

> **Status:** 🚧 ACTIVE
> **Cadence:** per-finding review with repeated whole-repository audit rounds
> **Depends on:** completed Final Acceptance, tagged
> `reference-implementation-v1`, and the clean Phase 9 compatibility-drift
> audit.

> **Evidence note (2026-08-03):** Per-task design/proof/review/audit artifacts
> written under the workspace-scratch `.context/` directory were never
> committed and are not retained. The durable evidence for the claims in this
> file is the committed code, the committed test suite, and the referenced
> commit hashes. Process-narrative details that cited only scratch artifacts
> (RED/GREEN transcripts, mutation counts, verifier reports) are historical
> claims that can no longer be independently re-checked.

## Goal

Re-audit the current repository from fresh evidence, including every current
tree difference from `reference-implementation-v1` and every later change on
the current branch. Turn each verified actionable finding into a reviewable
task, implement it through the mandatory
architect → test-driven executor → independent verifier → mechanical checks →
commit loop, and repeat the audit until a clean independent pass finds no
remaining actionable issue.

The historical v1 acceptance remains valid for the commit it audited. This
phase tests whether the substantially changed current tree is still the
simplest correct reference implementation.

As of 2026-07-31, this phase closes the Noir-owned work against the existing
pinned dependency tuple. `external/opentui`, its gitlink, the six bundled
artifacts, and their ABI/manifest are read-only. Native-only findings stay
visible as limitations but are not an implementation or merge gate for this
PR.

## References

- [`GOALS.md`](../GOALS.md) §§2–7 — architecture, quality standard, process,
  drift guardrails, and final audit.
- [`READ_HERE.md`](./READ_HERE.md) §§3–13 — hard rules, agent roles, task loop,
  mechanical gates, and audit trail.
- [`reference-implementation-plan.md`](./reference-implementation-plan.md) —
  historical deep review and the reasons behind Phases 0–8.
- [`final-acceptance.md`](./final-acceptance.md) — the v1 acceptance baseline;
  evidence to re-verify, not a substitute for current-state review.
- [`plan.md`](./plan.md) — separate parity/harness roadmap whose open
  obligations must be reconciled without duplicating their ownership here.
- Local reference implementations under `external/opentui/packages/{go,react,core}`
  and Flutter semantics where the framework intentionally follows Flutter.
- Phase-start drift report: workspace-scratch notes (not retained).

## Invariants and scope

The core invariant remains unchanged:

> Widgets declare. Elements preserve identity. RenderObjects layout and record
> paint. Compositor talks to OpenTUI. Native owns FFI, memory, ABI, and
> binaries.

- No backwards-compatibility shims, deprecated aliases, stale contracts, or
  obsolete barrels.
- No native calls in render-object paint, code-unit indexing on visual-text
  paths, duplicated lifecycle/dispatch/scheduling ownership, or semantic
  changes hidden inside simplification work.
- Prefer deletion and existing ownership patterns over speculative
  abstractions. A simplification must preserve behavior and prove that with
  tests, unchanged contract evidence, and a subtractive or equivalent diff.
- Audit the full current implementation, the v1-to-current tree comparison,
  and current branch history from the shared merge base. The v1 tag is not an
  ancestor of current HEAD, so no report may describe the tree comparison as
  “commits since v1.” Recent files receive extra scrutiny but are not the
  boundary of the review.
- Use blast-radius warnings in designs rather than hard file exclusions.
- `tasks/plan.md` remains the owner of parity/harness work. Phase 9 links its
  evidence and status instead of copying its tasks.
- `external/opentui` remains pinned and read-only. Its configured fork URL is
  provenance, not authorization to edit the fork, move the gitlink, rebuild
  artifacts, run workflows, or roll the ABI/manifest. A finding that requires
  one of those changes is `read-only-upstream`, remains truthfully documented,
  and does not block Noir-local closeout.

## Phase-start gates

- [x] Compatibility drift audit exists and has zero remove-or-refactor hits.
- [x] Documented workspace setup completed: `dart pub get` and
      `git submodule update --init external/opentui`.
- [x] Starting mechanical baseline is green: format, fatal analysis,
      architecture tests, and full tests.
- [x] Phase Readiness Reviewer reports PASS after independently reviewing this
      tracker against the current tree.

Before the final readiness box is checked, only narrowly scoped corrections
required by the readiness or standards-conformance reports may run, and they
still use the full per-finding review loop below. Round 1 audit-axis execution
and runtime or public-API implementation cannot start until readiness reports
PASS.

## Audit rounds and coverage ledger

Round 1 must inspect the full current implementation, the complete tree-to-tree
diff between `reference-implementation-v1` and the audited HEAD, and the
current branch history from their merge base. Later rounds re-read changed
neighborhoods and then re-run every axis against the new HEAD. Each audit
report records files and symbols inspected, reference sources, commands and
tests run, gaps found, and each gap's disposition. Every report also records the
literal audited HEAD, v1 endpoint, merge base, whether v1 is an ancestor, and
the exact tree-comparison command. “No obvious issue” is not completion
evidence.

| Axis | Minimum evidence | Round 1 | Clean re-audit |
| --- | --- | --- | --- |
| Core semantics and architecture | Flutter/local contract citations, ownership and data-flow inspection, semantic tests, relevant fitness functions | [x] | [x] |
| Native resources and lifecycle | allocation/owner/dispose map, failure paths, ABI/assets evidence, lifecycle and distribution tests | [x] | [x] |
| Unicode and text | grapheme/UTF-16/cell mapping review; cursor, selection, width, emoji, CJK, combining, and ZWJ evidence | [x] | [x] |
| Rendering, layout, and input | OpenTUI Go/React/core comparison, constraint/hit/focus/scheduling paths, semantics, goldens, and ordinary hermetic integration | [x] | [x] |
| API, docs, tests, and performance | barrel/API audit, guarantee-focused docs, missing-test map, and measured hot-path/FFI/tree-work evidence | [x] | [x] |
| Simplification and normalization | caller/consumer evidence for duplication, pass-through layers, inconsistent ownership/naming, or removable complexity | [x] | [x] |
| Post-v1 patch manager and tools | CLI/git boundary, error and cancellation paths, state transitions, large-view goldens, and tool-specific tests | [x] | [x] |
| Existing parity-plan obligations | every open checkbox and completion rule in `tasks/plan.md`, available parity gates, and exact evidence for any external symbol blocker | [x] | [x] |

Audit reports were workspace-scratch notes (not retained). A
coverage box is checked only when its report contains the required evidence
and every candidate finding has a ledger disposition.

Terminal captures are supplemental, separately authorized evidence owned by
P9-039; they are not required to check a core coverage box.

## Finding ledger

Severity:

- **P0:** safety, data, resource, or architecture blocker.
- **P1:** incorrect public or runtime semantics.
- **P2:** verified maintainability, test, documentation, or performance defect.
- **P3:** small evidence-backed normalization.

Status progression:

`registered → candidate → verified/rejected → designed → red/structural-fail → green/structural-pass → verifier-clean → checks-clean → committed`

`registered` records a finding accepted directly from a mandatory audit gate
before any design, RED, or production change.

For behavior findings, `red` and `green` mean a semantic test failed for the
expected reason and then passed. For documentation, process, or other
structural findings, `structural-fail` and `structural-pass` are the equivalent
mandatory before/after proof states. A finding must use one evidence path; it
cannot silently skip both.

### Validation-policy transition

On 2026-07-23 the user lifted the temporary blanket prohibition on Dart tests.
The current `AGENTS.md` authorizes ordinary unit, widget, golden,
architecture, package-consumer, and hermetic integration tests. References in
the designed-row acceptance summaries below to the temporary policy or
“policy-blocked” RED/GREEN work describe the policy at those design
checkpoints; they no longer block ordinary repository-local execution.

Host-sensitive diagnostics remain approval-gated: leak/sanitizer/resource
exhaustion probes, deliberate native crashes or fatal signals, and real
terminal/PTY/ConPTY/raw-mode/visual sessions. OpenTUI source, gitlink, ABI,
artifact, manifest, and workflow mutations are outside this program rather
than awaiting ordinary task authorization.

Rejected candidates require counter-evidence. A `read-only-upstream`
disposition requires exact evidence that the accepted correction cannot be
completed against the pinned dependency. An actionable repository-local
finding cannot be deferred under that label.

A genuinely external parity dependency already owned by `tasks/plan.md` does
not enter the Phase 9 ledger only when pinned audit evidence proves that no
repository-local correction is available, current documented behavior and
Noir-local Phase 9 gates remain satisfied, and the parity roadmap explicitly
retains the item. The limitation must remain visible and cannot be called
fixed.

### Active program disposition

The finding status records execution progress; the disposition below records
whether unfinished work is part of core Phase 9 closeout and why it can or
cannot execute now:

- `required-local`: actionable with authorized repository-local checks;
- `required-dependency-blocked`: required correctness awaiting a named
  predecessor;
- `read-only-upstream`: accepted correction requires a prohibited change to
  the pinned OpenTUI source/artifact contract; visible but nonblocking;
- `optional-restricted`: useful evidence requiring exact authorization, not a
  core completion requirement;
- `optional-performance`: deferred until measurement justifies the machinery;
  and
- `optional-maintenance`: version or tooling upkeep with no demonstrated
  correctness, compatibility, or security failure.

Read-only, restricted, or optional never means passed, waived, or implemented.
Required Noir-local rows continue to block closeout. Read-only upstream
limitations remain explicit without becoming a fork/native implementation
lane.

| ID | Disposition | Core closeout | Exact current reason |
| --- | --- | --- | --- |
| P9-005 | read-only-upstream | does not block | P9-005D is verifier-clean and landed; only P9-005N remains read-only upstream for the native guarded-operation/status contract and artifact remainder. |
| P9-018 | read-only-upstream | does not block | Raw scissor push in the pinned ABI swallows allocation failure, so Noir cannot prove the accepted failure-atomic command-complete contract without a native change. |
| P9-020 | read-only-upstream | does not block | The pinned ABI does not expose the accepted exact width oracle; a second Dart approximation would not prove renderer equality. |
| P9-021 | read-only-upstream | does not block | The accepted packed-grapheme ownership/storage contract requires native source and artifact changes. |
| P9-022 | read-only-upstream | does not block | Exact native-cell selection mapping depends on unavailable P9-020/P9-021 packed-span semantics. |
| P9-023 | read-only-upstream | does not block | Exact terminal-cell preferred-column behavior depends on unavailable P9-020 width semantics. |
| P9-027 | read-only-upstream | does not block | P9-027A raw Git identity/transport is landed; only P9-027B Unicode-friendly exact-terminal-cell presentation depends on P9-020, so the reversible ASCII-safe presentation remains. |
| P9-032 | optional-performance | does not block | No current measurement justifies dirty-root retained-paint machinery. |
| P9-033 | optional-performance | does not block | No current measurement justifies the proposed three-budget native-text cache. |
| P9-039 | optional-restricted | does not block | PTY/ConPTY/real-terminal evidence remains an unimplemented, separately authorized `tasks/plan.md` project. |
| P9-040 | optional-restricted | does not block | Remote release-candidate evidence activates only with operator/workflow authorization. |
| P9-071 | optional-maintenance | does not block | Compatible upgrades exist, but no correctness, compatibility, or security failure currently justifies dependency churn. |
| P9-085 | read-only-upstream | does not block | Pinned native setup moves the main-screen cursor before alternate-screen entry, so the observed shutdown returns to row 1/column 1 instead of the launch cursor and overwrites main-screen content. |
| P9-086 | required-local | blocks | `TerminalSession` calls `Renderer.setupTerminal()` before `StdinInputDriver.start()`, leaving native capability replies able to race input acquisition; the mechanism is directly observed in the raw bindings example, while high-level corruption was not reproduced. |

P9-024R, P9-025R, P9-028R, and P9-034R are resolved dispositions recorded
below; they do not reopen or overstate the committed slices. Any new
clean-sheet runtime finding receives its own normal ledger row and full
workflow; this disposition table does not claim its implementation.

P9-002 proves exception-safe cleanup ownership and best-effort terminal
restoration, not exact terminal byte ordering, main-screen content, or
launch-cursor restoration. P9-085 owns that newly observed exact semantic
qualification without rewriting the historical P9-002 task.

P9-086 is a distinct Noir-local input/query-order defect, not P9-039 evidence
work or P9-085 native cursor restoration. The raw bindings example directly
demonstrated the terminal-line-discipline mechanism: native capability replies
arrived while stdin remained canonical and echoing, became visible on screen,
and disappeared in the external no-echo control. The high-level captures were
clean and high-level corruption was not reproduced. That qualified result does
not close the source-level race: the current high-level session still arms
native setup before starting its input driver.

#### Resolved residuals

| ID | Resolution | Direct counter-evidence | Artifacts / closeout |
| --- | --- | --- | --- |
| P9-024R | rejected as a production defect; proportionate persistent counter-evidence added | One private State composed from the production focus/text-editing owner mixins proves the three discriminating raw-notification/hook/owner-build tuples: invalid focus `(1,1,1)`, focused text plus nested repair `(2,1,1)`, and same-controller parent text update `(2,1,1)` unchanged after an explicit build-scope flush. | focused `+50`, architecture `+108`, ordinary checkpoint `+922 ~2`, health `+1`, primitive parity `+2`, format 291/0, fatal analysis and diff hygiene pass; independent verifier and tracker-closeout review PASS |
| P9-025R | split: painted-output proof added; redundant invalid-update Cartesian matrix rejected | `BufferCapture` proves the final `abcde...` row; suppressing only `_paintEllipsis(...)` changes it to `abcdefgh`. Existing constructor, assertion-disabled creation/update, and direct-setter tests exercise zero and negative values across the sole unconditional validator and both distinct widget update implementations, so the omitted sign/prior-state permutations cross no additional production rule or branch. | focused `+11`, counter-evidence `+5`, active-map `+7`, architecture `+108`, ordinary checkpoint `+923 ~2`, health `+1`, primitive parity `+2`, format 291/0, fatal analysis and diff hygiene pass; no production, fixture, dedicated architecture guard, golden, native, or restricted-operation change |
| P9-028R | rejected as a production defect; direct persistent counter-evidence added | A non-`async` repository fixture proves direct synchronous throws are deferred and caught after replacement has cleared old state; one combined binding case proves identical repositories do not reload and accepted staging uses only the distinct replacement. Loaded-view characterization proves one in-flight refresh, last-good state after failure, stable-ID state across retry, and inert success/error completions after disposal. | focused `+39`, preservation `+23`, architecture `+108`, ordinary checkpoint `+926 ~2`, health `+1`, primitive parity `+2`, format 292/0, fatal analysis and diff hygiene pass; production remains byte-identical; full Cartesian outcome expansion and new async machinery were rejected; independent verifier PASS |
| P9-034R | rejected as a residual production defect; proportionate proof-only closeout complete | One equality-equal/identity-distinct Element test jointly discriminates the maintained depth map, dirty reservations, inactive membership, preflight cycle detection, and deactivate depth publication. One real generic `MultiChildRenderObjectElement` update through a `StatelessElement` proves a detach error raised before render mutation preserves both trees and a disarmed retry finalizes once. The existing architecture guard now enforces all three identity collections, bounded no-parent-walk/no-sort scheduling, and sole internal owner access to raw parent/depth writers. Root/depth behavior was already closed; P9-059 owns the superseded GlobalKey path; timing benchmarks remain optional; the distinct post-commit defect was subsequently closed by committed P9-063. | ten mutation REDs; focused `+38`; preservation `+31`; architecture `+107`; ordinary checkpoint `+926 ~2`; health `+1`; primitive parity `+2`; format 291/0, fatal analysis, production-scope, and diff hygiene pass; independent verifier PASS; production remains byte-identical and no benchmark, corruption seam, Cartesian path matrix, native action, terminal operation, deliberate crash, leak probe, or other restricted operation was added |

### Round 2 clean-sheet disposition summary

All three Round 2 reports audit exact clean HEAD/upstream
`990b24cd1ed2656cdfc4b39b660370b4d83cb34e` with pinned OpenTUI submodule
`ddbc9edf81a1fa89961135ab0481df15054ed4b0`. Together they cover all eight
axes, record every observation as actionable, rejected, optional, or blocked,
and preserve the recent ownership design. A checked Round 2 coverage cell
means the audit/disposition work ran; it does not claim that the resulting
required-local rows are implemented.

Reports and consolidation:

- Round audit reports were workspace-scratch notes (not retained).

The independent readiness result is PASS-WITH-CORRECTIONS. This amendment
incorporates its exact disposition map, A/B ownership boundaries, package/docs
partition, partial-order dependency correction, optional-maintenance
classification, and parity Task 2 supersession. P9-027A subsequently landed
the accepted raw-byte identity/transport slice and its compilable ASCII-safe
intermediate presentation. P9-027B remains downstream of the read-only P9-020
limitation.

### Round 1 disposition summary

All eight reports audit the pinned HEAD
`5041844d74ed1a9f2211cbb3ad9782a8ae0e6ae1` against v1 endpoint
`2da49c57533b0b91abd16602e87b5493bdb1c253`, with shared merge base
`fc0302e983a1abed681334fb4346d1ba61cb35c1` and an explicit non-ancestry result.

The eight Round 1 reports contain 67 unique candidate dispositions: 53
verified local findings, one roadmap-owned external dependency, and 13
rejected candidates. Overlapping descriptions consolidate those Round 1
candidates into 42 executable tasks (P9-002 through P9-043) below without
dropping any independent red test. These are Round-1-only historical counts:
P9-001's phase-start durable-context correction and the later withdrawn
native follow-up are not added to or subtracted from the
67-candidate, 53-verified, one-roadmap-dependency, 13-rejected, or 42-task
totals. `ADTP-004` is partitioned between P9-006 and P9-008; `ADTP-006` is
partitioned between P9-015 and P9-032. Both source findings close only after
both destination rows commit.

Reports:

- Round audit reports were workspace-scratch notes (not retained).

`P9-PO-005` remains solely under `tasks/plan.md` Task 3: the pinned native
source and all six artifacts omit exactly `textBufferConcat`,
`textBufferResize`, and `textBufferGetCapacity`; no local semantic replacement
exists, current primitive parity is green, and the roadmap explicitly permits
the shim to remain narrowly pending while that literal gate is red. If any of
those facts changes upstream, reopen Task 3 under `tasks/plan.md` and record
any resulting Noir-local work as a normal finding in this ledger.

| ID | Round / axis | Finding and `file:line` evidence | Severity | Contract / reference | Reproduction or structural proof | Blast radius | Status | Acceptance proof | Artifacts / commit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| P9-001 | Round 1 / API, docs, tests, and performance | Durable fitness inventories, current barrel names, roadmap ownership, linked instructions, and Phase 9 closeout evidence drifted from the current tree. | P2 | `GOALS.md` §§6–7; `READ_HERE.md` §§2, 10, 13 | workspace-scratch notes (not retained) | Durable Markdown, Phase 9 reports, and `CLAUDE.md` link only; no runtime/test-source change | committed | Spec and quality reviews passed; final readiness and conformance PASS; format/analyze/61 architecture/559 full tests passed | `6ebfb75` |
| P9-002 | Round 1 / native lifecycle | App/terminal acquisition and teardown can skip terminal restoration and owned-resource disposal after construction, mount, unmount, stop, or close exceptions (audited baseline `5041844`: `lib/src/app/tui_binding.dart:20-36,235-254`; `lib/src/app/terminal_session.dart:108-124,203-224`). | P0 | Explicit lifecycle ownership; native report NL-001 | Failure-injection map in NL-001 | App binding/session, lifecycle tests | committed | Focused red `+29 -8`; verifier-loop red `+37 -1`; green `+38`; independent verifier PASS; format 247/0, fatal analysis, 61 architecture tests, and full `+569 ~2` suite pass | `3f0a38f` |
| P9-003 | Round 1 / patch manager | Untracked discovery eagerly reads full files and follows/omits symlinks, so it is unbounded and previews bytes different from Git's staged link blob (audited baseline `5041844`: `lib/src/tools/patch_manager/git_repository.dart:169-183,276`). | P0 | Lossless bounded Git/filesystem boundary; PM-001, PM-004 | Large/sparse and real symlink probes in patch-manager report | Git repository/models/UI tests | committed | Initial RED `+6 -4`; verifier-loop RED `+0 -1`; focused green `+61`; independent verifier PASS; format 247/0, fatal analysis, 61 architecture tests, full `+583 ~2`, probe, and diff hygiene pass | `225380c` |
| P9-004 | Round 1 / native lifecycle | Startup probes only a TextBuffer/error subset instead of the complete guarded native surface (audited baseline `5041844`: `lib/src/ffi/abi.dart:95-221`; `native_symbols.dart:8-188`). | P1 | Complete startup ABI validation; NL-002 | Fake libraries missing renderer/buffer/cursor/terminal symbols | FFI ABI inventory, binary integrity tests | committed | RED `+0 -1` on the missing inventory/lookup seam; focused green `+33`; related FFI/lifecycle/hook green `+20`; independent verifier PASS; format 247/0, fatal analysis, six-artifact verification, protected-path no-diff, architecture `+64`, and full `+597 ~2` pass | `a79d048` |
| P9-005 | Round 1 / native lifecycle | Native errors are never populated/read and fallible Zig exports swallow failures (`external/opentui/packages/core/src/zig/lib.zig:18-35,201-203`; `lib/src/ffi/bindings.dart:21-34`). | P1 | Loud fallible native contract; NL-003 | Induced native-operation failures | Historical: native fork, bindings, generated surface, six artifacts/hashes. 2026-07-29 local scope: Dart dimension/API truth only; retained native design is read-only. | designed | Historical accepted contract: the independently accepted amended v2 design replaces the failed global error channel with one-call status/result wrappers for thirteen guarded native operations, adds guarded scissor push plus raw infallible pop, rejects non-positive renderer extents before unsigned conversion, and defines an exact 60-name ABI-3 resolver inventory without depending on withdrawn P9-044–P9-048 fixtures. At that checkpoint execution awaited authority to publish a reachable native source commit and six coherent artifacts/hashes plus actual Linux/Windows proof; no RED, implementation, artifact build, or completion was claimed. **2026-07-29 disposition:** P9-005D is required Noir-local work: reject non-positive renderer create/resize dimensions before unsigned FFI conversion and correct the unsupported `WidthMethod.grapheme(2)` claim. The one-call status-wrapper, guarded-scissor, ABI-3, six-artifact, and platform-proof remainder is P9-005N, a visible `read-only-upstream` limitation rather than an execution plan. No native source, artifact, manifest, workflow, or ABI change is authorized or claimed. **2026-07-31 local completion:** P9-005D is verifier-clean and landed: one internal Dart validator rejects non-positive renderer create/resize dimensions before unsigned FFI conversion, invalid resize preserves cached buffer state, and `WidthMethod` exposes exactly `wcwidth(0)` and `unicode(1)`. P9-005N remains a visible `read-only-upstream` limitation; its native guarded-operation/status contract, artifact work, and platform proof are not fixed or claimed. RED `+12 -3`, focused `+28`, architecture `+141`, format `283/0`, fatal analysis, verifier PASS, and protected diff clean. | native/rendering reports |
| P9-006 | Round 1 / core and API | `GlobalKey` lacked owner-wide uniqueness and exposed lifecycle registration to apps (`key.dart:76-129`; `element.dart:382-399,732-811`). | P1 | Owner-wide GlobalKey lookup/uniqueness; CORE-001; ADTP-004 key portion | Duplicate placement and lifecycle-binding gaps | BuildOwner/key/Element registry, API fixtures | committed | Owner-owned registry, read-only lookup, duplicate-key detection, inactive teardown, and internal registration remain current. The commit also introduced document-order-only cross-parent reclaim; P9-059 explicitly supersedes and removes that partial movement contract without reopening the registry/internal-API work. ADTP-004 fully closes only when P9-008 (State portion) also commits. | `278eea3`; superseded movement partition: P9-059 |
| P9-007 | Round 1 / core | Inherited dependents rebuild stale before `didChangeDependencies`, then rebuild again (`element.dart:444-451`; `test/inherited_widget_test.dart:39-50`). | P1 | Flutter inherited notification order; CORE-002 | Existing test locks wrong order | InheritedElement/build scheduling/tests | committed | Red: corrected-order test showed stale build before the callback; green: exactly one `didChangeDependencies` then one build with the new value (dedup proven, single rebuild per change). Deferred `State.didChangeDependencies` via a flag + `notify-before-child-rebuild` + `clearDirty` dedup; P9-006 liveness guards unchanged and passing. Independent verifier CLEAN; format 249/0, fatal analysis, 66 architecture, full `+606 ~2` pass. | `c6bdb94` |
| P9-008 | Round 1 / core and API | State detaches before `dispose`, silently drops post-dispose `setState` in release, and exposes framework wiring (`element.dart:356-362`; `widget.dart:93-131`). | P1 | Flutter State lifecycle; CORE-003, CORE-009; ADTP-004 state portion | Mounted/context and post-dispose tests in core report | State/StatefulElement, mixins, public API tests | committed | Red: dispose saw `mounted==false`/null context; `setState` after dispose gave `AssertionError` (silent in release); wiring not `@internal`. Green: dispose runs attached (`mounted==true`, readable context, once, bottom-up) then detaches; `setState` throws `StateError` in all modes without invoking the callback; `attach`/`updateWidget`/`detach` `@internal`. Independent verifier CLEAN (Flutter line-by-line unmount match; no regressing callers). ADTP-004 now fully closed (with P9-006). format 249/0, fatal analysis, 67 architecture, full `+608 ~2` pass. | `982198e` |
| P9-009 | Round 1 / focus | A queued autofocus request can target a disposed/replaced/detached node (`widgets/focus.dart:140-156`; `focus_manager.dart:194-200`). | P1 | Focus lifecycle ownership; CORE-004 | Unmount-before-microtask scenario | Focus widget/manager tests | committed | Red: owned and supplied nodes each threw an unhandled `StateError` from the queued microtask after unmount; green: guarded closure (mounted + node-identity + autofocus + `isAttached`) skips cleanly and a still-mounted Focus still autofocuses. Orchestrator review (7-line guard, low blast radius); format 250/0, fatal analysis, 67 architecture, full `+611 ~2` pass. | `9ff04e2` |
| P9-010 | Round 1 / focus | `unfocus()` can immediately select the same node again (`focus_manager.dart:617-667`). | P1 | Explicit Flutter-shaped unfocus disposition; RLI-006 | First/only node source trace | FocusManager/traversal/listener tests | committed | Red: 7 tests failed — first/middle/single unfocus reselected the node or jumped to a sibling, scope case left a leaf focused, listener saw false→true→false churn. Green: Flutter `scope` disposition — focus moves to the nearest enclosing focusable scope (clears at the synthetic root), never the node/sibling; Tab still reaches the first child; one true→false notification. Orchestrator review (single-method change, 7 semantic tests); format 251/0, fatal analysis, 67 architecture, full `+618 ~2` pass. | `ac1a396` |
| P9-011 | Round 1 / animation | Partial animation consumes full duration and cancellation/restart futures report success (`animation_controller.dart:86-152,195-207`). | P1 | Flutter animation run contract; CORE-005, CORE-006 | Partial-distance and stop/restart gaps | AnimationController/tests/docs | committed | Implementation commit `4b69b99` scales run duration by remaining distance, gives every run-ending path one completion owner, and guards listener-started replacement runs from stale ticks. Historical RED/GREEN and verifier-loop proofs passed; focused current-tree re-verification at `028010c` passed `+15`. Exact-HEAD `8876203` review is PASS with production and semantic-test blobs unchanged; under the temporary `AGENTS.md` local-validation policy, exact-HEAD tests were not run, while format checked 253 files with 0 changes and fatal analysis reported no issues. This does not claim Phase 9 closeout. | `4b69b99` |
| P9-012 | Round 1 / foundation | One throwing ChangeNotifier listener prevents later listeners from running (`change_notifier.dart:28-36`). | P2 | Observer isolation/reporting; CORE-007 | Throwing-middle-listener gap | Foundation error hook/notifier/tests | committed | Final-shape RED passed six existing tests and failed all three new semantics because the first throw truncated each snapshot. GREEN reports each original `Object` and stack immediately through the notification-entry Zone while preserving order, mutation, duplicate-removal, and nested notification behavior: focused `+9`, foundation `+34`, architecture `+70`. Independent verifier reproduced RED and returned PASS; format/fatal analysis/diff checks and safe checkpoint `+637 ~2`, health `+1`, primitives parity `+2` are green. | `66aa3e9` |
| P9-013 | Round 1 / animation lifecycle | Disposed provider-created tickers remain retained until State disposal (`animation/ticker.dart:111-157`). | P2 | Ticker/provider ownership; CORE-008 | Repeated create/dispose gap | Ticker/provider/controller tests | committed | Baseline RED passed two lifecycle controls and failed three exact retention assertions. GREEN adds one private, cleared-before-call disposal callback after scheduler removal and terminal state, removes the exact provider ticker once, and drains teardown from a snapshot without changing public or single-provider behavior: focused `+5`, animation `+15`, scheduler/integration `+17`, architecture `+70`. Independent verifier reconstructed RED and returned PASS; format/fatal analysis/diff checks and safe checkpoint `+637 ~2`, health `+1`, primitives parity `+2` are green. | `cabbc94` |
| P9-014 | Round 1 / rendering | Dropped/unmounted render objects retain a live PipelineOwner and can schedule ghost work (`rendering/object.dart:238-244,297-300`; `element.dart:498-503`). | P1 | Recursive attach/detach ownership; RLI-002 | Drop/unmount/mutate trace | RenderObject/PipelineOwner/Element tests | committed | Recursive, failure-atomic subtree attachment now validates exact PipelineOwner ownership, removes detached nodes from former dirty queues, recursively detaches removed edges, publishes roots only after attachment, and restores GlobalKey and multi-child lifecycle ordering. The one package-internal single-child transition is `@internal`, non-exported, constrained, and non-virtual. Final focused `+50`, architecture `+76`, broader rendering/framework `+101`, independent verifier PASS, format/fatal analysis/diff checks, and safe checkpoint `+686 ~2`, health `+1`, primitives parity `+2` are green. | `1476246` |
| P9-015 | Round 1 / rendering and performance | Mutable render setters do not invalidate the correct phase; blanket Element layout invalidation masks the defect (`rendering/flex.dart:73-105`; `element.dart:506-512`). | P1 | Render property owns invalidation; RLI-005; ADTP-006 invalidation portion | Direct attached mutation schedules nothing | All render setters, Element, pipeline tests | committed | Every render configuration mutation now owns exact layout/paint/no-work invalidation, Element no longer adds blanket layout work, TextArea retains immutable line snapshots, and ScrollBox listeners reconcile across nested/adopted attachment, replacement, rejected detach, partial detach, and post-commit callback errors. P9-016 validation remains before equality/storage/invalidation; an explicit assertions-disabled probe locks rejected-assignment state/queue/callback atomicity. Predecessor RED was direct `+3 -10`, Element `+3 -2`, and attachment `+16 -3`; independent verification PASS; final focused `+101`, architecture `+79`, affected regression `+212`, release `+1`, format/fatal-analysis/diff checks, and safe checkpoint `+731 ~2`, health `+1`, parity `+2` are green. P9-032 remains the dirty-flush scaling owner. | `c66688a` |
| P9-016 | Round 1 / geometry | Box constraints/extents accept negative and non-normalized values despite the public contract (`render/geometry.dart:23-52`; `rendering/box.dart:40-50`). | P1 | Normalized terminal-cell constraints; RLI-008 | Negative/tight and min-greater-than-max examples | Geometry, widgets, layout tests | committed | Const geometry now diagnoses negative/non-normalized construction, transforms preserve normalized ranges, and render/layout/controller boundaries reject invalid values before storage, adoption, notification, or size mutation in all modes. Zero remains valid through direct/headless RenderView, ScrollBox, Select, and TerminalSession evidence; positive native dimensions remain P9-005. Dart's const evaluator cannot inspect fields of a passed geometry object in another const constructor, so nested widget values retain const APIs while geometry owns early diagnostics and render storage owns unconditional valid-super probes. Initial RED was `+1 -9` plus the missing inspection surface; final focused verifier-loop `+16`, regression `+87`, architecture `+77`, independent PASS, format/fatal analysis/diff checks, and safe checkpoint `+700 ~2`, health `+1`, primitives parity `+2` are green. | `5f25af5` |
| P9-017 | Round 1 / flex layout | Flex independently rounds shares beyond available cells, can exceed parent max, and collapses tight flex under unbounded main constraints (`rendering/flex.dart:133-147,210-280`). | P1 | Exact bounded integer allocation and unbounded diagnostic; RLI-003, RLI-004 | Odd-width and ScrollBox+Expanded examples | RenderFlex/Flex widgets/goldens | committed | RenderFlex now uses exact overflow-safe `BigInt` largest-remainder quotas and alignment slots, constrains both final axes while retaining explicit child overflow, and rejects unsatisfiable unbounded flex before child layout while permitting loose/min shrink-wrap. Spacing is non-nullable integer cells; public/direct spacing and flex values validate before mutation, adoption, or invalidation in assertions-enabled and disabled modes. Initial RED was `+3 -13`; final focused `+74`, ownership/invalidation `+42`, architecture `+79`, format/fatal-analysis/diff checks, and safe checkpoint `+768 ~2`, health `+1`, parity `+2` are green. Independent review found and closed one empty-golden proof defect, then accepted exact colored allocation sidecars and the intentional `layout_basics` right-border restoration. No memory-leak/sanitizer/resource-exhaustion probe, deliberate crash/fatal-signal/process-kill test, real-terminal/PTY/iTerm automation, native rebuild/ABI fault injection, artifact/release operation, or GitHub workflow operation was run. | `c9f429d` |
| P9-018 | Round 1 / display-list clipping | `drawBox` bypasses wrapper clipping, so decorated ScrollBox children can paint outside the viewport (`painting/tui_canvas.dart:307-388`; `core/buffer.dart:514-655`). | P1 | OpenTUI scissor semantics; RLI-001 | Oversized decorated-child trace | Display list, compositor/buffer, ScrollBox goldens | designed | Historical accepted contract: the independently accepted design makes destination clipping command-complete through one compositor-owned, root/view-shared non-reentrant native-scissor scope; balances push/body/pop on every path; covers all six command families; and preserves source-crop/Unicode ownership. At that checkpoint ordinary implementation awaited the accepted P9-005 thirteen-operation ABI-3 contract landing as a reachable native commit with six coherent artifacts and platform proof; terminal visual evidence remained separately authorization-gated. **2026-07-29 disposition:** the accepted design remains technically valid, but the pinned raw `bufferPushScissorRect` swallows allocation failure. A Noir-only normal-case binding cannot prove balanced failure atomicity, and duplicating OpenTUI box semantics in Dart is not an equivalent fix. This is a documented `read-only-upstream` limitation. | rendering/native reports |
| P9-019 | Round 1 / input | ANSI parsing erases horizontal wheel direction and ScrollBox axis semantics (`core/stdin_input_driver.dart:812-847`; `core/input.dart:465-502`). | P1 | OpenTUI four-direction mouse contract; RLI-007 | SGR 66/67 collapse to same scalar | MouseEvent/parser/ScrollBox tests | committed | The no-shim `MouseScroll` direction/magnitude contract preserves exact SGR 64–67/modifier/button decoding and OpenTUI branch precedence through parser, router, and public API. ScrollBox applies Shift axis rotation and consumes matching-axis events only when the offset changes, so mismatched and clamped events bubble unchanged. Final focused `+124`, architecture `+76`, independent verifier PASS, format/fatal analysis/diff checks, and safe checkpoint `+686 ~2`, health `+1`, primitives parity `+2` are green. | `cf41aa3` |
| P9-020 | Round 1 / Unicode | Dart's first-rune approximate width table disagrees with OpenTUI for VS16, modifiers, controls, combining, and other clusters (`core/grapheme_metrics.dart:24-67`). | P1 | One OpenTUI-compatible cell-width oracle; UT-002 | Shared stress matrix in Unicode report | Width service, TextIndexMap, layout/editors | designed | Historical accepted contract: the independently accepted design requires an explicit immutable `WidthMethod` with no default/inference, one generated Unicode-16/`zg` oracle and whole-input validation, and a staged P9-020A native boundary plus P9-020B Dart routing. P9-020A and accepted P9-021N formed one ABI-4 roll after P9-005/P9-018; reachable native source/artifact authority and platform proof blocked execution at that checkpoint. **2026-07-29 disposition:** the exact renderer-compatible width contract still requires a native surface/artifact change that the read-only dependency boundary excludes. A second Dart approximation would not prove equality and must not masquerade as completion. The limitation and affected consumer semantics remain documented. | Unicode report |
| P9-021 | Round 1 / Unicode paint | Whole graphemes are passed to scalar-cell APIs and clipped by UTF-16 substring, losing cluster tails and continuations (`core/buffer.dart:256-272,569-596`; `painting/tui_canvas.dart:390-433`). | P1 | Packed grapheme/cell clipping; UT-001, UT-006 | Combining/VS16/modifier/flag/ZWJ/CJK structural losses | Buffer/compositor/editors/Select/paragraph, goldens | designed | Historical accepted contract: the independently accepted native prerequisite defines exact 1–65,535-cell ID-only packed spans, finite overflow storage, occurrence-correct ownership, failure-atomic staging, guarded frame-buffer draw, and safe snapshot boundaries in the combined ABI-4 roll. The accepted Dart design routes whole UTF-8, rejects scalar misuse, and admits/drops complete source and destination clusters under P9-018's one scissor. At that checkpoint P9-005/P9-018 had to land first; P9-020A and P9-021N would then land together as one reviewed ABI-4 native/artifact unit, followed by P9-020B and finally the rebased P9-021 Dart routing. Terminal visuals remained separately authorization-gated. **2026-07-29 disposition:** the finite-overflow, occurrence-correct, failure-atomic packed-storage contract requires native source and artifact changes. Dart routing alone cannot establish it against the pinned ABI-2 tuple, so this remains a documented `read-only-upstream` limitation. | Unicode report |
| P9-022 | Round 1 / Unicode selection | Source selection mapping advances runes but native TextBuffer expects cell indices (`widgets/text_layout.dart:44-66,245-262`; `core/text_buffer.dart:138-142`). | P1 | Native cell-stream selection; UT-003 | CJK/combining offset counterexamples | TextLayout/compositor/TextBuffer/tests | designed | Historical accepted contract: the independently accepted design derives one immutable native-cell map and styled stream plan from globally segmented source, maps every selected EGC to its complete packed span, defines CRLF/LF and soft-wrap affinity semantics, matches pinned four-case native nullable-color behavior, and proves crop/global style equivalence and following-cell preservation. At that checkpoint ordinary execution awaited landed P9-020/P9-021N/P9-021 semantics. **2026-07-29 disposition:** the exact mapping still depends on unavailable P9-020/P9-021 native-cell and packed-span semantics. It remains a downstream `read-only-upstream` limitation, not a partial Dart approximation. | Unicode report |
| P9-023 | Round 1 / text editing | Consecutive vertical caret moves lose the preferred column after a short line (`text_editing_controller.dart:104-114`). | P1 | Flutter vertical caret run; UT-004 | `abcdef / x / abcdef` example | Controller/connection/intents/tests | designed | Historical accepted contract: the independently accepted design gives the controller one method-explicit terminal-cell goal across clamping and reversal, uses CRLF-atomic logical-line records and failure-atomic P9-020 validation, resets on actual value changes while preserving ignored/no-op actions, and requires cursor-sidecar plus isolated terminal proof. P9-024 was landed; ordinary implementation still awaited P9-020's terminal-cell oracle, while terminal visual proof remained separately authorization-gated. **2026-07-29 disposition:** the accepted behavior still preserves an exact terminal-cell goal; implementing it with the known approximate width helper would lock incorrect semantics. It remains downstream of the read-only P9-020 limitation. | Unicode report |
| P9-024 | Round 1 / text editing | Owned/external editors repair invalid active selections inconsistently and focused programmatic text changes leave invalid selection (`text_area.dart:145-161`; `text_editing_owner_mixin.dart:63-87`). | P1 | One active-selection owner; UT-005 | Multiline autofocus/programmatic update cases | Editing owner/Input/Area cursor goldens | committed | One owner: `TextEditingOwnerStateMixin` repairs focused unusable selection to UTF-16 document end for owned and external controllers; widgets no longer seed selection; connection rejects unusable state before mutation with no shim. Same-State A→B→A controller swap, already-focused replacement, external notification/callback counts, and focused design selection matrices green. Direct persistent P9-024R counter-evidence later rejected the suspected duplicate hook/rebuild defect through the three discriminating shared-mixin hook and owner-State build tuples without a production change. Ordinary serial partitions/architecture clean. No restricted operation was run. | `09ecde8`; Unicode report |
| P9-025 | Round 1 / text API | `maxLines <= 0` is accepted and treated as unlimited (`widgets/text.dart:82-103`; `rendering/paragraph.dart:239-244`). | P1 | Flutter maxLines validity; UT-007 | Zero/negative behavior | Text/RenderParagraph/tests/docs | committed | Positive-or-null contract: const asserts on Text/Text.rich/RichText; unconditional `_validatedMaxLines` on RenderParagraph constructor/setter; `_maxLinesLimit` is null-or-positive only; widget updates validate maxLines first. Assertion-disabled creation paths, soft-wrap interaction, and selection+maxLines paint command forwarding covered. Focused + architecture + serial partitions green. P9-025R later added the missing final-buffer ellipsis proof; its proposed full invalid-update Cartesian expansion was rejected as redundant because existing tests cover both invalid partitions and every distinct validation, creation, and widget-update owner. No restricted operation was run. | `60781b5`; Unicode report |
| P9-026 | Round 1 / patch manager | Hunk staging silently includes mode metadata while valid zero-hunk tracked changes cannot be staged (`patch_generator.dart:50-55`; `models.dart:159-165`). | P1 | Explicit content versus whole-file staging units; PM-002, PM-003 | Real Git mode/content and empty-deletion probes | Patch models/generator/repository/UI/tests | committed | Exactly two immutable request types now separate content from whole-file staging. Content requests own canonical side headers plus selected hunks and never smuggle file metadata; whole-file targets truthfully cover mode-only, lifecycle, binary, untracked, rename, and type-change states through immutable `GitPath` identities and the sole literal-NUL pathspec encoder. The repository returns typed unchanged-versus-refresh-required outcomes for every check/mutation/exception phase; one total diagnostic owner contains hostile objects. Controller and UI state are target-typed, whole-only files have direct previews and truthful stage/skip controls, and uncertain mutation locks both staging paths until a successful explicit refresh while skip/quit/refresh remain available. Opaque Git openers remain a verbatim, non-authoritative patch envelope; decoded side paths are corroborated against authoritative raw identities. P9-029's retired workflow remains deleted and P9-028's generation ownership remains unchanged. Authentic slice and verifier-loop REDs, real-Git edge matrices, pointer/lock behavior, and buffer/style/cursor golden comparison pass. Independent readiness, final implementation re-review, and Standards Conformance audit PASS. Focused `+164`, architecture `+132`, ordinary checkpoint `+1069 ~2`, health `+1`, primitive parity `+2`, manifest/six-binary verification, format `301/0`, fatal analysis, deletion/boundary searches, and diff hygiene pass. Production/test changes are 24 files, 3,780 insertions/807 deletions before this tracker amendment. No compatibility shim, alternate identity/decoder/pathspec encoder, terminal/PTY session, process-lifecycle suite, native/artifact mutation, release action, or other restricted operation ran. | patch-manager report |
| P9-027 | Round 1 / patch manager paths | Git octal/ambiguous paths and UTF-16 truncation corrupt valid file identity/presentation (`diff_parser.dart:253-361`; `display_models.dart:337-340`). | P1 | Lossless Git identity then terminal-safe display; PM-005 | Real UTF-8/` b/` and surrogate-boundary probes | Parser/models/display/controller tests | designed | P9-027A is complete: Git command output/input is byte-only; immutable `GitPath` is the sole identity; one raw-`-z` plus patch envelope owns exact paths and metadata; structural headers only corroborate; non-UTF8 payloads are contained per file; stable IDs use raw identity; invalid-UTF8 paths bypass filesystem preview; untracked staging uses literal NUL pathspec stdin; and every current UI caller explicitly derives reversible printable-ASCII presentation. A verifier-found real Git `T` record/two-block defect returned through architect/readiness/RED and now uses fixed ordinal grouping with exact mode/side checks, publishing one non-content-stageable type-change file. Focused `+117`, targeted verifier `+9`, architecture `+132`, ordinary checkpoint `+1022 ~2`, health `+1`, primitive parity `+2`, manifest/six-binary verification, format `301/0`, fatal analysis, structural deletion/boundary searches, and diff hygiene pass; independent implementation and tracker reviews PASS. Landed P9-026 consumes this identity/transport without another decoder or pathspec encoder and preserves P9-029's deletions. **2026-07-29 disposition:** P9-027B alone remains downstream of the read-only P9-020 limitation for Unicode-friendly exact-cell presentation, so the safe reversible ASCII presentation remains; terminal evidence stays authorization-gated. | patch-manager report |
| P9-028 | Round 1 / patch manager state | Initial/retry loads can overlap and stale completions overwrite newer state (`patch_manager_app.dart:53-83,638-667`). | P1 | Generation-ordered async State; PM-006 | Reverse-order controlled futures | PatchManagerApp/view tests | committed | Last-started-wins generation + repository identity; load-again/retry status before I/O; stale success/failure suppressed both orders; dispose/replacement revoke; message screen shows owner status. Focused generation matrix includes A-B-C and replacement cases. P9-028R later rejected a residual production defect and closed the proof gap with a true synchronous replacement throw, identical/distinct repository rebinding plus replacement-only staging, and compact loaded-refresh single-flight/last-good/retry/disposal characterization. The redundant Cartesian outcome matrix was not added. Ordinary serial partitions green. No restricted iTerm work. | `7bb1a07`; patch-manager report |
| P9-029 | Round 1 / simplification | Removed approval/index-preview workflow still adds state, dead APIs/tests, and a Git process (`git_repository.dart:47-66`; `review_controller.dart:5-19,40-44,96-110,166-206`). | P2 | Delete unreachable workflow; SIM-001 | Production caller counts and `c4b3def` history | Patch-manager models/controller/UI/tests/goldens | committed | `loadWorkspace()` now returns the sole visible `DiffSet` after exactly the tracked and untracked discovery commands. The cached-shortstat process/parser, snapshot/index models, approval state/transitions, silent refresh branch, hunk-only adapters, dead section toggles, and unread presentation data are deleted without aliases; early discovery errors retain their exact prefixes/messages, while shortstat-only failure intentionally disappears. Live staged/skipped/failed state, direct hunk/file staging, P9-028 generation and loaded-refresh ownership, and all six byte-identical goldens remain. Authentic RED was `+2 -2`; focused preservation is `+84`; architecture is `+129`; ordinary checkpoint is `+986 ~2`; health is `+1`; primitive parity is `+2`; format 298/0, fatal analysis, structural deletion/no-shim searches, and diff hygiene pass. Production is 36 insertions/249 deletions (net `-213`) against `990b24c`, with no successor contract or new abstraction. Independent readiness and implementation reviews PASS. P9-027A and the later P9-026 staging-unit implementation preserve this smaller model without restoring deleted state, commands, tests, or copy. No restricted operation ran. | simplification report |
| P9-030 | Round 1 / simplification | Four typed single-child RenderBoxes duplicate child ownership/visit/paint already owned by RenderProxyBox (`rendering/{constrained_box,padding,positioned_box,decorated_box,proxy_box}.dart`). | P2 | One authoritative single-child owner; SIM-002 | Clone and co-change evidence plus P9-057 callback split reproduction | Six render owners and lifecycle/layout/golden/architecture tests | committed | The duplication finding landed through P9-057's smaller one-store solution: the existing `RenderObjectWithSingleChild` derives its child from the generic edge across all six owners, with no extra typed-owner mixin/file. Six `_child` shadows, duplicate traversal/default paint, and caller-supplied-current mutation are gone; typed member surfaces and layout/goldens remain stable. The older `TypedRenderBoxChildOwner` design was superseded, not implemented. Independent architect and verifier PASS; authorized checkpoint, format, fatal analysis, architecture, and diff hygiene pass. | simplification and clean-sheet framework reports |
| P9-031 | Round 1 / TextArea normalization | TextArea traverses Elements on every edit to rediscover render metrics (`widgets/text_area.dart:167-194,209-223`). | P2 | Passive render-owned metrics; SIM-003, RLI-009 | Sole widget-State descendant search | TextArea State/leaf/render/viewport tests | committed | Exact-HEAD readiness/design PASS at `d31e112`. Structural RED was `+5 -1`, while all `+13` semantic characterization tests passed against untouched production. TextArea now owns exactly one final private State-lifetime metrics holder, forwards that identity through the private leaf into a final nullable `RenderTextArea` field, and passively publishes only after successful `size =`; State consumes the latest completed pair only when both axes are positive and otherwise uses the whole `(widget.width ?? 80, widget.height)` fallback pair. The supported public constructor and barrels are unchanged. The initial verifier found that the source guard could false-pass a fresh-per-build holder; the ten-line correction locks exactly one construction plus exact State-to-leaf forwarding, and final independent verification PASS. Focused guard/controller is `+19`, design-scoped TextArea semantics/goldens are `+45`, serial direct-constructor coverage is `+38`, architecture is `+143`, format is `301/0`, final ordinary serial checkpoint is `+1102 ~2`, health is `+1`, primitive parity is `+2`, and fatal analysis, diff hygiene, and protected-path checks pass. An initial default-parallel direct-constructor run encountered an unexpected native bus error after `+35`; the decisive serial rerun passed `+38`, and the retained failure was not a deliberate or restricted crash probe. No controller, selection, paint, pointer, Unicode-width, native, FFI, workflow, restricted-operation, or public-API change was made or claimed. | workspace-scratch notes (not retained) |
| P9-032 | Round 1 / pipeline performance | Dirty queues still flush root-to-leaf layout/paint for one dirty leaf (`rendering/object.dart:98-133,283-295`). | P2 | Dirty-root/subtree work; ADTP-006 scaling portion | Deterministic O(tree) control flow | PipelineOwner/RenderObject/display-list tests/benchmarks | designed | Independently accepted design makes every parent-to-child layout dependency explicit, caches relayout boundaries/constraints, and flushes shallow dirty roots. Owner-scoped retained Dart layers bound render paint/recording work while the compositor truthfully replays the complete visible scene; frame-bound operands are scrubbed on every exit, failures schedule one real retry, and scene order publishes only after successful commit. This optional-performance design must not execute unless current measurements justify its machinery; any future execution also requires exact-descendant re-audit and independent specification re-review. | API/performance report |
| P9-033 | Round 1 / compositor performance | Every repainted text layout creates/writes/finalizes/draws/destroys native TextBuffer; source clips call FFI per grapheme (`painting/tui_canvas.dart:364-433,472-505`). | P2 | Compositor-owned prepared native text; ADTP-007 | Deterministic allocation/call counts | Compositor/TextBuffer/cache lifecycle/tests | designed | Independently accepted design gives `OpenTuiCompositor` sole ownership of an identity-keyed, three-budget LRU of prepared native text; immutable commands/layers remain Dart-only and caller-owned TextBuffers are excluded. One commit session shares destination bounds across all retained layers, source crops use one guarded draw, per-operand failures and terminal disposal diagnostics preserve exact ownership, and counters lock allocation/FFI/disposal budgets. This optional-performance design must not execute unless current measurements justify the cache; any future execution also awaits its native/Unicode/rendering predecessors and exact-descendant re-review. | API/performance report |
| P9-034 | Round 1 / build performance | Dirty-element sorting recomputes depth by walking ancestors, quadratic on a dirty chain (`framework/owner.dart:119-149,179-186`). | P2 | Maintained depth/buckets; failure-atomic deactivation; ADTP-008 | Sum-of-depths proof | Element mount/deactivation/BuildOwner tests/benchmark | committed | Maintained depths + dirty buckets; `BuildOwner.deactivateChild` is the sole deactivate owner (preflight→old-parent-readable render detach→publish→inactive); SingleChild/MultiChild/Flex callers do not pre-drop render edges; SingleChild `removeRenderObjectChild` uses `setChild(null)`. E2e rejection is driven via real Element widget updates (`_updateChild(null)`, type-swap, MultiChild leftover `_deactivateChild`, Flex multi-child) after subtree poison — not direct `BuildOwner.deactivateChild` — and asserts both Element parent/active/children and render parent edges unchanged; success null/remove paths also use Element updates. Parent-read scale is 0 vs 55/5050/500500. P9-059 later removes the unused general different-parent path, retains the specialized failure-atomic deactivate transition, and owns the superseded GlobalKey matrix. P9-034R rejected a residual production defect and closes only the proportionate proof gap: one equality-overriding Element matrix, one pre-mutation generic multi-child/Stateless path, and a sole-writer/identity architecture guard. Root/depth behavior was already closed, benchmark timing remains optional, P9-059 owns GlobalKey/reparent scope, and the distinct post-commit detach defect was subsequently closed by committed P9-063. No restricted operation was run. | `d577edc`; scale-proof `42da63f`; API/performance report e2e real-path `5c93504`; sole-owner deactivate `982066e`. |
| P9-035 | Round 1 / package landing and durable docs | The root README addressed source-checkout readers, referenced excluded surfaces, and current durable native guidance still claimed behavior removed by `72657aa`. | P2 | Source-level package landing plus bundled-only durable native-document truth; ADTP-001, NL-004 | Source-level package-landing and durable-doc drift proof | README, Phase 8/deep-plan native sections, existing native-assets architecture guard | committed | Authentic focused RED was `+0 -2`; final focused GREEN is `+2`. Quick Start is package-consumer-facing, checkout-only root sections are deleted, bundled-only failure/provenance/override truth is current, and each owning durable slice records the historical download/source-build work superseded by `72657aa`. Verifier mutations prove first-delimiter ownership, local supersession, complete Phase 8 heading order, wrapping-insensitive history, and no extra download/source-build history. Final specification, implementation, and Standards Conformance reviews PASS. Final gates are native-assets `+11`, program `+7`, architecture `+112`, ordinary checkpoint `+938 ~2`, health `+1`, primitive parity `+2`, format 291/0, fatal analysis, protected scope, and diff hygiene clean. Archive, publication, consumer-compilation, workflow, and release evidence was not run and remains deferred. | workspace-scratch notes (not retained) |
| P9-036 | Round 1 / bundled skill | Published skill/test examples use unavailable helpers, invalid signatures, and false unchanged-Flutter claims (`skills/noir/references/testing.md`; `widgets.md`; `state-and-animation.md`). | P2 | Executable audience-specific skill docs; ADTP-002 | Concrete compile mismatches in API report | Skill references and example docs | committed | P9-036A is committed with structural RED, mutation, analyzer, and independent verifier evidence; shipped skill/reference/example guidance separates consumers from source-checkout helpers, matches current signatures and Tab/capture/inspector semantics, and rejects false Flutter parity. P9-036B rebased the final lifecycle/API wording against committed P9-038: `runTuiApp` returns the owning `TuiApp` synchronously, headless owns no renderer, the supported high/low/FFI tiers are explicit, concrete Elements and the recorder/display-list/compositor backend remain framework-owned, and the stale chat ticker workaround is deleted. P9-036B evidence is RED `+29 -3`, focused `+32`, chat/ticker `+6`, architecture `+157`, format `306/0`, fatal analysis and dartdoc clean, ordinary `+1118 ~2`, health `+1`, primitive parity `+2`, six binaries verified, protected scope/diff hygiene clean, and independent verifier PASS. No runtime framework, API/export, dependency, native, workflow, or P9-037 declaration-doc change landed. The former compiler/archive mechanism remains superseded. | (mechanism superseded) |
| P9-037 | Round 1 / API docs | At least 262 exported comments are mechanical filler rather than contracts (`lib/` exact filler scans). | P2 | `GOALS.md` meaningful public docs; ADTP-003 | 121 “value,” 28 “runs,” 113 “creates” hits | Exported high/low/FFI docs and guard | committed | Exact-HEAD inventory `99 / 21 / 107 = 227` across 39 authored library files is now `0 / 0 / 0`. Every selected filler line has one unique evidence-led replacement; the final library diff is 227 Dartdoc removals and 235 Dartdoc additions with zero changed non-Dartdoc line. The zero-baseline architecture guard, exact **168 high / 43 low companion / 15 FFI** namespace, borrowed-renderer/headless split, animation-status orientation, and UTF-16 half-open highlight contract are independently verified. Focused guard `+1`, public API/member/distribution `+27`, semantic preservation `+184`, architecture `+158`, ordinary checkpoint `+1119 ~2`, health `+1`, primitive parity `+2`, format `307/0`, fatal analysis, dartdoc `0/0`, six-binary verification, protected scope, and diff hygiene pass; independent implementation verifier PASS with a bijective 227-key attestation. The terminal `committed` value describes this task's part of the single combined P9-037/P9-074 commit landed at `4ed3eba` from the final exact-tree gates; it does not claim Phase 9 acceptance, publication, platform certification, or resolution of read-only upstream limitations. | workspace-scratch notes (not retained) |
| P9-038 | Round 1 / public API | High-level barrel exposes low-level owners and TuiBinding exposes advanced/unexported types (`lib/noir.dart`; `app/tui_binding.dart:20-35,67-82,138-148`). | P2 | Use-case-curated high/low/FFI tiers; ADTP-005 | Consumer/symbol inventory | Barrels, binding facade, API locks/docs | committed | Exact-HEAD v3 readiness passed at base `20be184`. Authentic structural REDs were `+5 -5`, `+1 -6`, `+1 -3`, and `+1 -8`. The landed surface is exactly **168 high / 43 low companion / 15 FFI**: ordinary apps receive a private-constructor `TuiApp` facade; advanced hosting/custom rendering use the companion tier; semantic color/style values are FFI-free with private marshalling; `TuiCanvas` is the exact eight-method non-constructible paint vocabulary; and Element, display-list/compositor, raw owner, and native allocation machinery stay hidden/internal. The independent correction loop closed all seven review findings with complete FFI and custom-render consumers, effective inherited-member/top-level-variable/alias closure, exact constructor/facade guards, app-priority cancellation/disposal behavior, portable path sets, and assertion-disabled zero-paint proof. Final checks: architecture `+154`, source consumer `+4`, focused semantics `+106`, format `306/0`, fatal analysis and dartdoc clean, ordinary checkpoint `+1115 ~2`, health `+1`, primitive parity `+2`, six binaries verified, independent final review PASS, protected scope and diff hygiene clean. No native, gitlink, ABI, artifact, manifest, generated binding, workflow, terminal/PTY, release, or publication mutation ran. | API report |
| P9-039 | Round 1 / test infrastructure | No PTY, ANSI-byte renderer snapshot, or multi-frame cursor proof exists (`test/helpers/README.md:105-112`). | P2 | Real terminal lifecycle/output evidence; ADTP-009 | Explicit documented test gap | Test harness, CI platforms, terminal docs | designed | Independently accepted design freezes a stable packed-cell codec, deterministic HTML/ANSI multi-frame protocol, Unix PTY lifecycle, and Windows ConPTY lifecycle with exact deadlines, dimensions, sentinels, suspend/resume, ETX, drain, and teardown contracts. This optional/restricted project remains unimplemented and outside core Phase 9 closeout; it may start only with exact authorization after its semantic predecessors settle. | API report |
| P9-040 | Round 1 / distribution evidence | No retained literal-HEAD low/high-level consumer run exists for Linux, macOS, and Windows. | P2 | Phase 9 optional release evidence; NL-005 | Workflow text only | Remote consumer-smoke evidence and closeout docs | designed | Independently accepted design retains the existing CI owner and stages classified archives into exact high/low package consumers on Linux, macOS, and Windows, with literal final-HEAD SHA equality, run identity, diagnostic artifacts, and two-candidate closeout rules. This optional release-candidate evidence remains final-last and requires explicit workflow/operator authorization, available runners/default branch, and a final publish candidate. | native report |
| P9-041 | Round 1 / parity roadmap | Task 1/2 recipes and mandatory skill names drifted from current imports, seams, geometry, types, test presets, and workflow (`tasks/plan.md:3,84-492`). | P2 | `tasks/plan.md` remains sole parity owner; PO-001, PO-002, PO-006 | Unknown W1, skipped snapshot command, compile analysis | Parity roadmap only | committed | Historical accepted contract and evidence: plan recipes were corrected for implementability at roadmap-only scope—READ_HERE workflow; BufferCapture; complete `captureWidgetSceneSnapshot` → `_snapshotFromCapturedBuffer` CapturedBuffer→JSON path used by W1–W3 only (S1–S3 keep the low-level Buffer serializer); integer spacing; four nullable color maps; exact-three symbol gate over **all six** packaged artifacts under `native/{macos,linux,windows}/{arm64,x64}/`; three core completion conditions; opaque-black Go W clears; and centered W2/W3. P9-035's package-landing boundary landed. Task 1 committed at `817c82c` with authentic RED, an exact tight-root geometry amendment, independent implementation and conformance PASS, combined S/W parity, and serial checkpoint evidence. Task 2 committed at `3cc34fc`: the sole unique selection-paint proof moved to BufferCapture matchers, the unused serializer/test/preset/GoldenTester surface was deleted, and the parity-roadmap fitness test prevents the fifth representation from returning. Its authentic RED, independent readiness and implementation PASS, focused `+15`, retirement `+4`, architecture `+138`, ordinary `+1076 ~2`, health `+1`, primitive parity `+2`, format/fatal-analysis, and no-golden-change evidence are green. At that checkpoint Task 3 still awaited the P9-020/P9-021 native/artifact contract and its all-six-artifact symbol gate; optional Task 4 was P9-039 and did not block it. The residual medium recipe gaps remained explicit: Task 4 was high-level relative to the accepted P9-039 contract, and `parity_roadmap_test` was a targeted structural guard. **2026-07-29 disposition:** the read-only dependency decision retains Task 3's exact-three fail-fast shim because all six pinned artifacts lack the symbols, and the roadmap completion rule permits that pending upstream-triggered cleanup. Optional Task 4/P9-039 remains visibly unimplemented and nonblocking. P9-041 is administratively closed without a submodule change, fork branch, workflow run, ABI/artifact roll, or false shim-retirement claim. | `tasks/plan.md`; `817c82c`; `3cc34fc` |
| P9-042 | Round 1 / parity tool | `exec go run` bypasses the wrapper's EXIT trap and leaves its temp directory behind (`scripts/run_go_snapshot.sh:69-73,105`). | P2 | Reaped subprocess and deterministic cleanup; PO-003 | Shell replacement semantics | Go snapshot wrapper/tests | committed | Darwin broad `+22`, combined `+54`, direct S1/S2/S3, literal `+679 ~2`, and mechanical gates pass; Colima Linux wrapper `+52` and combined `+54` pass; exact-SHA Ubuntu job `86920919777` passes `+54` in 08:20; independent final verifier PASS | Consolidation design; parity report; `0ab4f13`; Actions run `29280671575` |
| P9-043 | Round 1 / parity shim | Test shim defines ten no-op exports although only three are missing, masking seven real native symbols (`tools/parity/go_snapshot/textbuffer_stubs.c:3-38`). | P2 | Exact temporary test seam only; PO-004 | Cross-artifact symbol inventory | Go parity shim/wrapper/structural guard | committed | Exact-three fail-fast seam; anchored empty-environment symbol preflight; lifecycle `+8`, anchored `+42`, complete wrapper/primitives `+96`, direct S1/S2/S3 PASS, macOS/Linux lifecycle `+8`, literal full suite `+721`, mechanical gates, and independent implementation plus lifecycle/transport PASS | Consolidation design and amendments; parity report; RED/GREEN proofs; final reviews; `28977f3` |
| P9-049 | CI recovery | Windows workflow guards depended on LF checkout text, test-only Git decoding used the host code page, symlink tests compared constructor input rather than the stored target, and the complete 96-test parity suite exceeded its obsolete CI bound. | P0 | Workflow/test portability and bounded diagnostic execution | Exact-HEAD remote failures: CI Windows `87220641672`, release Windows `87223610729`, CI parity `87220658858`; same-HEAD release parity passed all 96 in job `87220653294` | CI/release workflow guards, patch-manager Git tests, one wrapper cold-start deadline, workflows | committed | Workflow ownership RED `-2`, then GREEN `+3`; patch-manager Git `+17`; focused wrapper `+1` in 27 seconds; independent verifier PASS. Format, fatal analysis, and architecture gates are green. The operator explicitly waived the literal local gate on 2026-07-15 after two attempts hit pre-existing native instability and one complete retry reached `+717 ~2 -4` only on pre-existing P9-043 timeouts. First exact-SHA Windows jobs `87326196860` and `87326168337` exposed Git-for-Windows staged-link slash canonicalization; the independently accepted test-only amendment keeps preview assertions exact against `Link.target()`. Final exact-SHA remote acceptance remains mandatory. | `95887e2`; `0a6b22f` |
| P9-050 | Process-efficiency spot check | Feature pushes duplicated PR CI for the same SHA, superseded runs were not cancelled, release repeated CI's ordinary/parity suites, one combined wrapper test repeated three named scenarios, and every task reran literal default `dart test`. | P2 | One verification owner per concern; artifact-specific release; focused task proof plus serial checkpoint partitions | Workflow-guard RED `+2 -4`; three verifier-loop mutation REDs; duplicate helper call at former lines 3287/3505; retained P9-049 job timings and topology | CI/release workflows and guards, one duplicate wrapper test, durable cadence/tracker docs | committed | Workflow guards GREEN `+6`; both workflows parse with `yq`; retained INT/TERM/timeout cases pass `+3` in 01:39; independent implementation rereview and standards-conformance audit PASS; format `252 files (0 changed)`, fatal analysis, and architecture `+70` pass. Checkpoint safe `+629 ~2` and health `+1` pass at `75a60ae`; two parity attempts exposed three unchanged timing cases, then the 2026-07-18 reliability correction (`2f266fe`) restored local checks-clean with two consecutive 97-test parity partitions (`+97` in 22:26 and 22:22). Both commits are ancestors of the audited HEAD. This committed local correction does not claim a current remote workflow run; future authorized release evidence belongs to P9-040. | RED/GREEN and checkpoint proofs; independent review and conformance audit; `75a60ae`; RED/GREEN parity-reliability proofs; `2f266fe` |
| P9-051 | Clean-sheet drift review / rendering ownership | `RenderProxyBox.child=` and `RenderView.setChild` dropped the current edge and published the typed child before validating a replacement, so a foreign child rejection corrupted the previously valid tree (`rendering/proxy_box.dart:22-32`; `rendering/render_view.dart:35-49`). | P1 | One atomic owner for single-child preflight and publication; RLI-002 | Concrete attached-owner rejection tests preserve typed/generic edges, pipeline owners, dirty queues, and visual-update counts; already-represented publication schedules exactly once | RenderProxyBox, RenderView, shared transition, single-child tests | committed | Baseline RED failed both concrete rejection cases; verifier-loop RED exposed missing already-represented layout work. GREEN `+42`; independent verifier PASS after two correction loops. Format 285/0, fatal analysis, architecture `+93`, ordinary checkpoint, health `+1`, primitive parity `+2`, and diff hygiene pass. P9-057 later removed the parallel typed publication state entirely, so an identical authoritative edge is now a true no-op while this entry-preflight guarantee remains. No deliberate crash/signal/process-kill test, PTY/iTerm automation, native rebuild, publication/release, or workflow operation ran. | clean-sheet review |
| P9-052 | Clean-sheet drift review / rendering identity | `PipelineOwner` dirty queues and `RenderFlex` child metadata used value-equality collections, so distinct render nodes that override `==` could collapse queued work or overwrite each other's flex data (`rendering/object.dart:60-61`; `rendering/flex.dart:53-54`). | P1 | Render-tree membership and per-child data use object identity | Equal-valued distinct RenderBoxes retain independent pending work and exact 1:2 Flex allocation | PipelineOwner and RenderFlex collections; behavior tests | committed | Both baseline behavior tests RED; GREEN focused `+72`; independent verifier reproduced RED and returned PASS. Format 286/0, fatal analysis, architecture `+93`, ordinary `+858 ~2`, and health `+1` pass. Primitive parity first hit the unchanged wrapper's watchdog-anchor rejection, left no survivor/temp owner, then passed `+2` on a clean retry. No deliberate crash/signal/process-kill test, PTY/iTerm automation, native rebuild, publication/release, or workflow operation ran. | clean-sheet review |
| P9-053 | Clean-sheet drift review / retained render identity | `MultiChildRenderObjectElement` dropped and re-adopted every retained render subtree on every update, while direct child removal and parent guards mixed identity validation with value-equality mutation/comparison (`framework/element.dart:985-1004`; `rendering/object.dart:277-303`; `rendering/flex.dart:103-116`). | P1 | Retained multi-child updates distinguish insert/move/remove; every render edge uses object identity | Compatible updates and keyed reorders preserve attach/detach counts; mixed add/remove touches only changed identities; Flex metadata refreshes; equal children/parents cannot corrupt ownership | RenderObject child order/removal, Element/root/Flex edge guards, semantic tests | committed | Baseline lifecycle/identity RED `+7 -5`; verifier-loop RED reproduced an equal-valued foreign parent silently claiming retention. Final GREEN `+16` and related `+28`; independent verifier PASS. Format 286/0, fatal analysis, architecture `+93`, ordinary `+867 ~2`, health `+1`, primitive parity `+2`, and diff hygiene pass. No deliberate crash/signal/process-kill test, leak/sanitizer probe, PTY/iTerm automation, native rebuild, publication/release, or workflow operation ran. | clean-sheet review |
| P9-054 | Clean-sheet drift review / Element reconciliation | The multi-child updater searched forward for any `Widget.canUpdate` match, so unkeyed children of different types could move State and RenderObject identity across slots during a reorder (`framework/element.dart:934-955` at audited HEAD `9d8ca06`). | P1 | Compatible unkeyed prefix/suffix is positional; only keyed unmatched-middle children may move | Unkeyed cross-type swaps replace both slots; duplicate sibling keys reject before mutation; keyed swaps and one-point prefix/suffix edits retain Element/State/RenderObject identity without attachment churn | `MultiChildRenderObjectElement` reconciliation and focused lifecycle/identity tests | committed | Independent architect APPROVE; baseline RED `+14 -3`; GREEN focused `+17`; incompatible equal-key cleanup probe `+1`; neighboring lifecycle/render tests `+38`; independent verifier PASS. Architecture `+100`, ordinary checkpoint `+880 ~2`, health `+1`, primitive parity `+2`, format, fatal analysis, and diff hygiene pass. No leak/sanitizer/resource-exhaustion probe, deliberate crash/signal/process-kill test, PTY/iTerm automation, native rebuild/artifact mutation/publication/release, ABI fault injection, or workflow operation ran. | workspace-scratch notes (not retained) |
| P9-055 | Clean-sheet drift review / framework identity | Element dependency maps, inherited dependent membership, FocusNode child membership, focus attachment lookup, and several focus comparisons used value equality, so distinct supported nodes that override `==` could collapse or alias (`framework/element.dart:61-62,177,247,554`; `framework/focus_manager.dart:119-399`; `widgets/focus.dart:128`; `widgets/focus_node_owner_mixin.dart:65` at audited HEAD `9d8ca06`). | P1 | Framework-tree ownership and membership use exact object identity; widget-key reconciliation keeps declared semantic equality | Equality-equal distinct inherited/focus nodes register, notify, remove, replace, focus, detach, and traverse independently | Element/InheritedElement dependency state, FocusNode/FocusManager membership, Focus widget node replacement, focused semantic tests | committed | Independent architect APPROVE; baseline RED `+0 -4`; GREEN focused `+4`; related inherited/focus tests `+25`; independent key/State/reconciliation controls `+30`; verifier PASS after one analyzer-hygiene correction. Architecture `+100`, ordinary checkpoint `+884 ~2`, health `+1`, primitive parity `+2`, format, fatal analysis, and diff hygiene pass. Semantic key equality is unchanged. No leak/sanitizer/resource-exhaustion probe, deliberate crash/signal/process-kill test, PTY/iTerm automation, native rebuild/artifact mutation/publication/release, ABI fault injection, or workflow operation ran. | workspace-scratch notes (not retained) |
| P9-056 | Clean-sheet drift review / app resize atomicity | `TerminalSession.resize` published `_width` and `_height` before calling the fallible renderer and treated an unchanged size as applied, so renderer failure exposed incoherent geometry and same-size requests invalidated buffers/scheduled frames (`app/terminal_session.dart:204-212` at audited HEAD `9d8ca06`). | P1 | Last successfully applied positive geometry is published as one pair; scheduling follows only an applied change | Disposed-renderer failure preserves the old pair and schedules nothing; invalid/same-size requests are true no-ops; a changed positive request applies and schedules | TerminalSession resize ordering/contract and TuiBinding scheduling behavior tests | committed | Independent architect APPROVE; baseline RED `+18 -4`; GREEN focused `+22`; related binding/event-loop/buffer tests `+20`; independent verifier PASS. Architecture `+100`, ordinary checkpoint `+888 ~2`, health `+1`, primitive parity `+2`, format, fatal analysis, and diff hygiene pass. The failure tests use only Renderer’s ordinary Dart disposed-state guard. No leak/sanitizer/resource-exhaustion probe, native fault injection, deliberate crash/signal/process-kill test, PTY/iTerm automation, native rebuild/artifact mutation/publication/release, ABI fault injection, or workflow operation ran. | workspace-scratch notes (not retained) |
| P9-057 | Clean-sheet drift review / single-child ownership | A throwing visual-update callback could leave a concrete `_child` field naming the removed child while the generic edge was empty or named the replacement (`rendering/object.dart`; six single-child owners at audited HEAD `d5cdc2f`). | P1 | One authoritative generic zero-or-one edge; scheduling errors surface only after coherent structural publication | Attached replace/remove/insert callback failures; direct adopt/drop cardinality; typed diagnostics; constructor/subclass hooks; unchanged layout and goldens | Shared single-child transition, six owners, Element removal, architecture guard, focused behavior/preservation tests | committed | Independent architect APPROVE superseded the stale P9-030 typed-owner design. Baseline callback/ownership RED `+1 -4`; final single-child `+18`, focused lifecycle/invalidation `+70`, preservation/goldens `+31`, architecture `+102`, format 287/0, fatal analysis, authorized ordinary/health/primitive-parity checkpoint, and diff hygiene pass. Independent verifier PASS after one analyzer-hygiene correction. Production plus the Element edit is net `-104` lines with no new owner type, barrel symbol, shim, or multi-child semantic change. No restricted operation ran. | workspace-scratch notes (not retained) |
| P9-058 | Clean-sheet drift review / framework lifecycle | A later child lifecycle failure left already-mounted siblings unreachable, and throwing unmount hooks truncated sibling, parent, inactive-tree, and owner cleanup (`framework/element.dart:69-88,887-895`; `framework/owner.dart:449-486` at audited HEAD `b87a882`). | P1 | Fresh-child mount containment; exhaustive at-most-once permanent teardown; first error and stack remain primary | Authentic later-child `State.build` failure plus throwing sibling/finalize/root-edge hooks | Element mount/unmount variants, BuildOwner finalization/disposal, GlobalKey and scheduler callback teardown | committed | Independent architect APPROVE; authentic baseline RED `+3 -6`. Verifier-loop RED `+4 -3` caught premature deactivate publication, skipped root detach after a committed child-edge callback failure, and a retained scheduler callback. Final tracked behavior/guard `+11`, independent decisive proof `+13`, preservation `+52`, architecture `+103`, format 288/0, fatal analysis, and diff hygiene pass; independent verifier PASS. Fresh-child mount failure preserves the exact primary object/stack, built-in teardown attempts every independent cleanup once, residual GlobalKey handles unregister, and owner teardown releases only its scheduler callback edge. No restricted operation ran. | clean-sheet framework report |
| P9-059 | Clean-sheet drift review / GlobalKey scope | P9-006 left cross-parent State preservation dependent on traversal order and public docs promised unrelated-subtree moves (`framework/key.dart`; `framework/element.dart`; `framework/owner.dart` at audited HEAD `f3523dc`). | P1 | One live binding (including across owners), owner-wide lookup, and same-parent keyed identity; cross-parent placement unsupported at the incoming edge | Both traversal orders, nested hosts, cross-owner placement, direct key rebind, duplicate placement, same-parent identity, and teardown controls | GlobalKey docs/registry, Element child owners, inactive teardown, depth/reparent tests, architecture guard | committed | Independent architect APPROVE selected the smaller lookup/same-parent contract. Baseline RED `+49 -10` plus cross-owner `+0 -1`; verifier-loop mutation RED proved the first architecture guard false-passed. Final focused contract `+55`, related preservation `+84`, architecture `+105`, format 288/0, fatal analysis, diff hygiene, ordinary checkpoint `+912 ~2`, health `+1`, and primitive parity `+2` pass; independent verifier PASS. Inactive retake, Element activation, and general reparent machinery are deleted; deterministic incoming-edge validation, direct-root registration defense, deferred teardown, and same-parent identity remain. P9-059 closes the GlobalKey partition of P9-034R. No restricted operation ran. | workspace-scratch notes (not retained) |
| P9-060 | Clean-sheet drift review / active-program ownership | The active tracker mixed retired blanket-policy wording, required restricted process/terminal/release evidence for core closeout, understated landed local proof, and left unfinished work without one explicit core disposition. | P2 | One active owner; locally actionable correctness blocks; optional/restricted evidence does not masquerade as core acceptance | Architecture guard over dispositions, gates, roadmap ownership, and P9-050 proof | Phase 9 tracker, deep plan, parity roadmap, durable entry point, continuation handoff | committed | Structural RED `+1 -5`; verifier-loop RED exposed a stale roadmap guard, incomplete durable inventories, and one analyzer info. Final focused guards `+10`, architecture `+100`, ordinary `+874 ~2`, health `+1`, primitive parity `+2`, six-artifact manifest verification, format, fatal analysis, and diff hygiene pass. Independent implementation and Standards Conformance reviews PASS; Phase Readiness reports PASS-WITH-FOLLOWUPS that are registered for later tasks. Native/Unicode blockers remain explicit; no restricted operation is claimed. | workspace-scratch notes (not retained) |
| P9-061 | Clean-sheet drift review / Element child ownership | `Element.children` remained a public mutable base store beside `_ElementBase._child`, `SingleChildRenderObjectElement._child`, `MultiChildRenderObjectElement._childElements`, and `FlexibleElement._child`, so supported low-level mutation bypassed tree ownership and built-ins manually synchronized parallel truth (`framework/element.dart`; `widgets/flexible.dart` at audited HEAD `d05acbe`). | P2 | One private final child store per built-in cardinality owner; one identity-stable live ordered unmodifiable inspection view; no base mutable store, sync path, or production mutation seam | Retained views across component/single/multi/Flexible updates; full mutation-route rejection; keyed reorder and insertion/removal identity; ordinary and throwing teardown; structural rejection of parallel stores | Element owners, test-only custom Element fixtures, depth architecture guard, durable fitness inventory | committed | Independent architect SPLIT/APPROVE Slice A. Baseline behavior RED was `+1 -5` and structural RED `+3 -2`; an independent verifier-loop mutation then proved the first guard false-passed and the corrected per-owner guard rejected it at `+4 -1`. Final independent review PASS; focused behavior/lifecycle/identity `+69`, architecture `+107`, format 289/0, fatal analysis, diff hygiene, ordinary checkpoint `+920 ~2`, health `+1`, and primitive parity `+2` pass. The four owners now retain one private final list plus one stable live unmodifiable view; production is net `+7` lines with no new manager, mixin, mutation seam, barrel symbol, render-layer change, or compatibility surface. Render edge encapsulation remains separate P9-062. No restricted operation ran. | workspace-scratch notes (not retained) |
| P9-062 | Clean-sheet drift review / render-edge encapsulation | `RenderObject.parent` remains publicly writable and `RenderObject.children` exposes the mutable authoritative ordered edge, so callers can bypass the checked adopt/drop/move and single-child transition owners (`rendering/object.dart` at exact HEAD `c506ba5`). | P2 | One private parent store; one private ordered child store; readable parent getter; one cached identity-stable live unmodifiable child view; `object.dart` remains the sole render-edge writer | Retained child view across supported adopt/move/drop; exactly three representative rejected mutation capabilities; reachable lifecycle-invalid fixtures; structural sole-store/sole-writer proof | `RenderObject` representation; existing render attachment guard; focused render lifecycle/identity tests; durable fitness inventory | committed | Registered `required-local / blocks` and `designed` before RED. The retained-view behavior passed while exactly replacement/add/reversing-sort failed at `+6 -3`; the existing attachment guard failed at `+8 -1` on the public representation. The representation-only GREEN uses one `dart:collection` import, `_parent`, `_children`, a parent getter, one cached `UnmodifiableListView`, and mechanical same-library reads/writes. Reachable invalid states now use supported adopt/attach/detach operations; two artificial corruption tests are deleted without a seam. Focused preservation is `+89`; the affected guard is `+9`. Public-setter, mutable-backing, non-final shadow-store, and direct-backing-exposure verifier mutations failed at `+0 -1`, `+0 -3`, `+0 -1`, and `+0 -1`, then restored exactly. Production is 36 additions/28 deletions (64 raw changed lines), net `+5` non-comment lines. Full architecture is `+110`; ordinary checkpoint `+936 ~2`; health `+1`; primitive parity `+2`; format 290/0 plus 2/0, fatal analysis, and diff hygiene pass. No algorithm, lifecycle, external reader, API name/type, export, second store, abstraction, compatibility setter, corruption seam, or restricted operation was added. Exact-HEAD architecture and independent implementation reviews PASS. | workspace-scratch notes (not retained) |
| P9-063 | P9-034R clean-sheet audit / committed detach scheduling | `RenderObject._dropChild` removes and detaches the render edge before `markNeedsLayout`; if the visual-update callback then throws, `BuildOwner.deactivateChild` treats the error as pre-commit and neither it nor the caller-owned Element list publishes matching deactivation, leaving a split Element/render tree. | P1 | A committed render-edge outcome and the matching Element ownership publication must remain coherent even when scheduling reports an error; preserve P9-057's intentional error visibility without inventing rollback semantics. | A dedicated RED probe test gives `+0 -1`: expected `victim.parent == null`, actual `MultiChildRenderObjectElement`, while the render child already has `parent == null` and the Element remains in the multi-child view. | `BuildOwner.deactivateChild`; component/single/multi/Flexible Element child stores; generic `RenderObject.dropChild`; P9-057 single-child transition; `RenderFlex.remove` metadata ordering | committed | `BuildOwner` now defers only an error whose captured old render edge is provably absent, completes the existing parent/depth/deactivate/inactive publication, and rethrows the same object and stack. Component, single, generic-multi, and Flexible owners publish only their own committed child-list removal in `finally`; the two single-render branches use one method-local removal function; and `RenderFlex.remove` cleans identity metadata only after its exact captured edge commits. Authentic four-branch RED was `+7 -4`; the three original verifier-loop mutations and the independent-review empty-`finally` amendment mutation each gave `+0 -1`. Final checks are focused `+71`, affected architecture `+13`, full architecture `+109`, ordinary checkpoint `+933 ~2`, health `+1`, primitive parity `+2`, format 291/0, fatal analysis, and diff hygiene pass. Production changes are exactly the four authorized files at 70 additions/18 deletions (88 changed lines, net `+52`), with no cross-owner abstraction, type, API/export, rollback, compatibility seam, harness, Cartesian matrix, State-deactivate handling, P9-062 change, or restricted operation. Independent implementation re-review PASS; the original architect approved the consolidation amendment. | workspace-scratch notes (not retained) |
| P9-064 | Round 2 / framework lifecycle | A successful fresh child inflated during multi-child update remained mounted and globally registered but absent from the authoritative parent child store when later child work threw (`framework/element.dart:987-1070` at audited HEAD `990b24c`). | P1 | Publish each successful fresh child before later throwing reconciliation work; no update transaction or rollback manager | Empty Row updated with successful keyed child followed by throwing build; retained live view, exact error/stack, teardown/dispose proof | Multi-child reconciliation and failure-containment tests | committed | `MultiChildRenderObjectElement` now publishes the exact fresh child to its existing authoritative store immediately after successful inflation and before later work. Production is one non-comment line with no helper, type, store, transaction, render sync, API, or P9-065 behavior. Authentic RED was `+7 -1`; removing the line after GREEN reproduced `+0 -1`; focused preservation is `+47`; architecture is `+114`; ordinary checkpoint `+941 ~2`; health `+1`; primitive parity `+2`; format 290/0, fatal analysis, and diff hygiene pass. Independent implementation review PASS. No restricted operation ran. | workspace-scratch notes (not retained) |
| P9-065 | Round 2 / framework lifecycle | A throwing `State.deactivate` after render/Element removal publication left the child active, in the former owner list, and outside inactive finalization (`framework/owner.dart:408-451`; `framework/element.dart:128-134,479-486` at audited HEAD `990b24c`). | P1 | Committed removal completes built-in subtree deactivation, inactive membership, and caller-list publication while preserving the first error object/stack | Single/component/generic-multi/Flexible real update paths, nested sibling continuation, render-error collision, finalization | Element/BuildOwner lifecycle and existing owner-local removal guards | committed | Built-in deactivation is now exhaustive; `State.deactivate` remains first and active-observing while framework completion always follows; `BuildOwner` unconditionally queues the inactive root and preserves an earlier committed render error over a later hook error. The four owner-local child algorithms remain unchanged. Production is 21 insertions/4 deletions (25 raw lines), with no helper, type, state, store, API, transaction, rollback, or compatibility surface. Behavior/structural REDs were `+27 -7` and `+8 -2`; four verifier mutations each failed `+0 -1`; focused preservation is `+86`; affected architecture `+15`; full architecture `+115`; ordinary checkpoint `+947 ~2`; health `+1`; primitive parity `+2`; format 291/0, fatal analysis, and diff hygiene pass. The 294-line test/guard shape received renewed architecture approval; independent implementation re-review PASS after one documentation-ordering correction. No restricted operation ran. | workspace-scratch notes (not retained) |
| P9-066 | Round 2 / focus ownership | `FocusNode.children` returns the mutable manager-owned identity set, so a public runtime cast can split membership from child parent pointers (`framework/focus_manager.dart:119-144` at audited HEAD `990b24c`). | P2 | One identity store, one cached live unmodifiable view, existing private adopt/drop writers | Retained view before attach, equality-equal identities, rejected mutation, live detach | FocusNode representation, focus behavior, existing focus architecture guard | committed | `FocusNode` now retains one lazy cached `UnmodifiableSetView` over its existing identity set while preserving the public `Iterable` signature and private adopt/drop writers. Runtime and structural REDs were each `+0 -1`; a mutable-getter mutation failed `+5 -2`; independent review found two guard holes, and actual parallel-store and parallel-view mutations then each failed `+0 -1`. Design-scoped preservation is `+34`; full architecture `+116`; ordinary checkpoint `+949 ~2`; health `+1`; primitive parity `+2`; format 291/0, fatal analysis, and diff hygiene pass. Production is 7 insertions/2 deletions (net `+5`), with behavior/guard additions of 40/28 lines and no new abstraction, API, export, dependency, snapshot, shim, or lifecycle algorithm. Independent verifier PASS. No restricted operation ran. | workspace-scratch notes (not retained) |
| P9-067 | Round 2 / native lifecycle | `Renderer.dispose` destroys `_ptr`, but unguarded raw `handle`/`bindings` remain reachable through exported cursor/mouse/keyboard extensions (`core/renderer.dart:150-175`; `core/cursor.dart`; `core/input.dart` at audited HEAD `990b24c`). | P1 | One Renderer-owned disposed guard before every native capability access; idempotent disposal unchanged | Safe post-dispose raw-accessor RED without FFI, then post-guard direct/extension matrix | Renderer lifecycle, low-level extensions, native lifecycle guard | committed | `Renderer` now owns the sole disposed guard; all nine direct native methods and both raw accessors invoke it before native state, while unchanged cursor/mouse/keyboard extensions inherit the rule. Safe raw-getter RED was `+0 -2`; structural RED `+0 -1`; four safe mutations separately caught missing handle/bindings guards, a competing direct-method rule, and non-idempotent disposal. Focused lifecycle/preservation is `+59`; full architecture `+117`; ordinary checkpoint `+974 ~2`; health `+1`; primitive parity `+2`; format 292/0, fatal analysis, and diff hygiene pass. Production is 21 insertions/11 deletions (32 raw, net `+10`) in `renderer.dart`; tests total 123 raw lines, with no API, abstraction, facade, binding seam, native/artifact, extension, auto-flush, finalizer, or disposal-order change. Independent verifier PASS. No restricted operation ran. | workspace-scratch notes (not retained) |
| P9-068 | Round 2 / package distribution | Six bundled MIT OpenTUI binaries ship without the upstream notice; README claims a nonexistent pub.dev release; intended package targets are implicit (`LICENSE`; `.pubignore`; `README.md`; `pubspec.yaml`; `native_manifest.json` at audited HEAD `990b24c`). | P0 release / P1 docs | Truthful source-package contents and availability; intended OS/architecture targets derived from the artifact matrix without claiming runtime acceptance; retained structural proof | Notice/provenance inclusion, `.pubignore` and manifest/platform parity, README availability wording | Package metadata, README, notice, existing package/native architecture guards | committed | The source package now carries the manifest-derived pinned OpenTUI notice and exact upstream license; README truthfully conditions its sole install command on the first publication; pubspec and README expose only the six bundled desktop targets while declining runtime certification; `.pubignore` remains byte-identical. Structural RED was `+0 -4`; four notice/order/metadata/ignore mutations each failed `+0 -1`; focused preservation is `+29`; architecture `+121`; ordinary checkpoint `+978 ~2`; health `+1`; primitive parity `+2`; format 293/0, fatal analysis, and diff hygiene pass. Notice/guard/docs are 31/148/27 raw lines within budget, with no runtime/native/manifest/workflow/API/dependency/version/tag/archive change. Independent verifier and Standards Conformance Auditor PASS. Final legal review, exact archive/publication, stable tag/version, and platform runtime proof remain open. No restricted operation ran. | workspace-scratch notes (not retained) |
| P9-069 | Round 2 / contributor safety and doc links | Contributor/test docs recommend an unfiltered suite that includes restricted signal/kill tests, and dartdoc has two current broken references. | P1 | Safe authorized validation partitions and resolvable authored documentation references | Structural command/link fail/pass | CONTRIBUTING, test guide, two authored API comments, existing docs/program guards | committed | Contributor and test guidance now uses the authorized ordinary partition, current focused selectors, and exact primitive parity while explicitly excluding the signal/termination wrapper and restricted host/native/release operations. The two malformed authored dartdoc references are prose/code spans with generated documentation at 0 warnings and 0 errors. Structural RED was `+0 -2`; six literal/unscoped/parity/wrapper/link mutations each failed `+0 -1`; focused guards are `+2`, documented focused commands are `+14` and `+2`, program ownership is `+11`, architecture is `+123`, ordinary checkpoint is `+980 ~2`, health is `+1`, primitive parity is `+2`, and format 293/0, fatal analysis, and diff hygiene pass. Independent specification and final implementation verification PASS after four reviewer-found false-pass/false-fail defects were corrected. No runtime, tag-default, workflow, shipped skill/example, compatibility, native, platform, or restricted-operation change ran. P9-036A separately owns shipped skill/example corrections; P9-037 owns final semantic public docs. | workspace-scratch notes (not retained) |
| P9-070 | Round 2 / package consumer proof | Dormant CI builds an ephemeral source consumer, but no retained repository fixture proves source-package resolution and current public member signatures. | P1 | Analyzer-owned source-package consumer proof now; exact archive proof only when authorized; final tier/type closure stays with P9-038 | Hermetic temporary consumer using the source path and retained fixture manifest | Consumer fixture, current examples, package architecture tests | committed | A retained four-file downstream package now proves representative high-only, high+low, and FFI-only signatures through exact supported imports. Its tagged semantic test copies the fixture to a system temporary directory, resolves offline, proves the generated `noir` package-config root is this repository, and analyzes every retained Dart file without executing native code. Structural/semantic REDs were `+0 -2` and `+0 -1`; nine stale-signature/private-import/cross-tier/quote/prefix/online/runtime/override/substitute-package mutations each failed `+0 -1`; package-distribution preservation is `+6`, source-consumer analysis is `+1`, architecture is `+125`, ordinary checkpoint is `+982 ~2`, health is `+1`, primitive parity is `+2`, and format 298/0, fatal analysis, and diff hygiene pass. Fixture/semantic/guard budgets are 53/112/84 lines with no production, API, export, dependency, workflow, native, platform, archive, publication, final-tier, or compatibility change. Independent final verifier PASS after all four review findings were closed. P9-038 still owns final type closure and negative reachability; authorized release work still owns exact archive evidence. No restricted operation ran. | workspace-scratch notes (not retained) |
| P9-071 | Round 2 / dependency hygiene | `dart pub outdated` reports compatible locked upgrades while `lints ^3` and `ffigen ^15` constrain newer resolvable majors. | P3 | Evidence-led dependency maintenance rather than version-recency churn | Activate only on a concrete compatibility, security, or tooling failure | pubspec, lockfile, analyzer/build-hook/codegen compatibility | verified | Optional maintenance, not a 1.0 gate. No current defect justifies changing constraints or the lockfile. | workspace-scratch notes (not retained) |
| P9-072 | Round 2 / dormant workflow source | Workflows retain Git LFS setup although no file is LFS-tracked, and publish preflight documents but does not enforce tag/version equality. | P2 | Workflow source matches direct-committed assets and fails closed on version/tag mismatch | Source-guard structural fail/pass and YAML parse only; no workflow execution | Dormant CI/release/publish YAML and existing ownership guards | committed | CI, release, and publish source now use the six directly committed native artifacts without obsolete Git LFS checkout or materialization. Pub.dev preflight requires exactly one plain pubspec version and the exact `v<version>` tag before SDK setup/dry-run; publish cannot bypass or continue past preflight failure. Authentic structural RED was `+4 -4`; 13 independent mutations/controls covered LFS variants, comments, tag source, malformed/duplicate declarations, mismatch handling, and failure/dependency bypasses. Final focused proof is `+8`; architecture `+127`; ordinary checkpoint `+984 ~2`; health `+1`; primitive parity `+2`; format 297/0 plus 2/0, fatal analysis, YAML parse, and diff hygiene pass. Independent re-review and Standards Conformance audit PASS after all three initial implementation-review findings were amended. No workflow execution, platform matrix, real terminal, native/artifact mutation, crash/leak probe, archive/publication, release, or other restricted operation ran; P9-040 still owns optional remote proof. | workspace-scratch notes (not retained) |
| P9-073 | Round 2 / product and performance boundary | Current docs list major React component/hook gaps and “performance in progress” without saying whether core-framework 1.0 excludes them or accepts current full-root/native-text costs. | P2 | Explicit supported core 1.0 scope and non-goals; measurement activates optimization machinery | Cross-document structural truth and no unsupported parity claim | Package landing, durable status docs, optional P9-032/P9-033 dispositions | committed | GOALS now owns one explicit core-framework 1.0 boundary; README and AGENTS align on the existing Widget/Element/RenderObject substrate, post-1.0 React component/hook parity, accepted full-root/native-text costs, measurement-only activation of P9-032/P9-033, and the absence of any release/version/platform/correctness-completion claim. The stale “performance in progress” and roughly-70% promise are deleted; `tasks/plan.md` remains unchanged and owns parity/harness work only. Authentic RED was `+6 -2`; nine isolated mutations covered missing scope, stale percentage, mandatory parity, missing accepted costs, unconditional optimization, partial capability loss, and three false release/platform claims. Final package proof is `+8`; architecture `+129`; ordinary checkpoint `+986 ~2`; health `+1`; primitive parity `+2`; format 297/0 plus 2/0, fatal analysis, and diff hygiene pass. Documentation/guard additions are 59/69 lines within budget, with no production/API/export/pubspec/version/dependency/native/workflow/parity/benchmark/optimization change. Independent architect, amended implementation re-review, and Standards Conformance audit PASS. No restricted operation ran. | workspace-scratch notes (not retained) |
| P9-074 | Round 2 / standards conformance | The deep plan's dedicated `## Hard rules` inventory omits the current pinned/read-only OpenTUI dependency rule even though GOALS and READ_HERE own it (`tasks/reference-implementation-plan.md:113-126`). | P2 | `GOALS.md` §2 OpenTUI dependency boundary and §6 principle 7; `READ_HERE.md` §3 rule 6 | Divider-bounded inventory has exactly five top-level bullets | Deep-plan hard-rule bullet, existing Phase 9 ownership guard, concise fitness descriptions, and tracker/session truth only | committed | The dedicated deep-plan inventory now has exactly six column-zero top-level rules. Its sixth block alone owns the pinned/read-only `external/opentui` submodule, fork provenance without authorization, allowed initialize/inspect/verify activity, prohibited source/ref/workflow/six-library/ABI/manifest/provenance mutation classes, visible nonblocking `read-only-upstream` disposition, and separate explicit dependency-strategy authority. The divider-bounded guard cannot borrow later prose, nested text, or sibling bullets: authentic RED was five blocks (`+18 -1`), preliminary GREEN is `+19`, and deletion, nesting, seven-block splitting, plus all five semantic-family mutations failed independently before exact hash restoration. GOALS and READ_HERE minimally inventory the expanded guard responsibility; all 39 P9-037 library files and its semantic-doc guard retain their frozen byte identity. The terminal `committed` value describes this task's part of the single combined P9-037/P9-074 commit landed at `4ed3eba` after exact-tree verifier, checkpoint, and Standards Conformance PASS. Phase 9 remains ACTIVE; this is not final acceptance or a PR merge-ready claim. | workspace-scratch notes (not retained) |
| P9-075 | Final repeat / API, docs, and text | `TextBuffer.create(int length, ...)` promises an initial allocation that pinned `createTextBuffer` explicitly ignores, while `TextBuffer.length` describes capacity but returns native `char_count` (`lib/src/core/text_buffer.dart:32-47,65-68`; pinned `lib.zig:383-395`; pinned `text-buffer.zig:190-305`). | P2 | Truthful supported named-only creation and logical native-cell length; raw ABI-2 two-slot fidelity; no-shim pre-1.0 correction | analyzer-AST structural guard and lifecycle characterization from the approved design | Supported wrapper/raw binding/compositor, existing lifecycle/display-list/source-consumer tests, existing public-member/program guards, durable fitness inventories, tracker/session | committed | Registered `required-local / blocks` and `designed` before RED. Untouched-production structural RED was `+11 -1`, while lifecycle characterization passed `+7`. The supported API is exactly `TextBuffer.create({WidthMethod widthMethod = WidthMethod.unicode})`: it creates empty, forwards literal zero into the retained raw ABI-2 two-required-int seam, rejects `nullptr` with `StateError` before `TextBuffer._` attaches ownership, and reports/reset current logical native-cell length truthfully. Preliminary GREEN is public-member `+12`, lifecycle/display-list `+14`, source consumers `+4`, and selected native/public/barrel/baseline ownership `+22`; all 19 actual-tree signature, ordering, outcome, forwarding, and declaration-local-doc mutations failed independently before exact restoration. The supported namespace remains exactly **168 high / 43 low companion / 15 FFI**, the low-level baseline file remains 44 entries, and protected dependency/native/generated/workflow/parity-shim paths plus the pinned submodule retain identity. Terminal `committed` records P9-075's inseparable part of the combined P9-075/P9-076/P9-077/P9-078 commit landed at `f798e74` after the decisive verifier and parent matrix PASS; P9-076 was found by P9-075's former precommit conformance gate. Phase 9 remains ACTIVE; this is not final acceptance, PR merge readiness, stable 1.0, publication, platform certification, or a fix for read-only-upstream limitations. | workspace-scratch notes (not retained) |
| P9-076 | Final repeat / API, docs, and text | Supported `TextBuffer.writeChunk` claims to return the number of cells written, but pinned Zig returns an opaque integer (`cellCount << 1`) and collapses native write failure to zero; raw 6 can accompany logical length 3 (`lib/src/core/text_buffer.dart`; `lib/src/ffi/bindings.dart`; pinned `lib.zig:443-449`). | P2 | Effect-only supported write contract; opaque raw integer fidelity; declaration-local failure truth; no-shim pre-1.0 correction | approved analyzer-AST structural guard and focused characterization from the design | Supported wrapper, guarded raw-binding docs, existing lifecycle/display-list/source-consumer tests, existing public-member/program guards, tracker/session | committed | Registration and the `designed` blocking row preceded production and RED-guard changes. Non-retained characterization proved raw 6 with logical length 3; authentic untouched-production RED was `+11 -1`. Supported `TextBuffer.writeChunk` is effect-only `void`; its exact body validates lifetime, updates persistent UTF-8 scratch storage, and discards one raw call result. Both raw wrappers remain direct `int` ABI forwarding and each declaration's docs independently own the opaque-result, Dart marshalling/invocation `FFIException`, and native-failure/zero facts without a count or blanket-throws promise. Final focused GREEN is public-member `+12`, lifecycle/display-list `+14`, source consumers `+4`, and selected native/public/barrel/baseline ownership `+22`; all 21 actual-tree return/body/doc/direct-forwarding/borrowing/consumer mutations failed independently before exact restoration. The formatted guard uses 59 incremental lines, supported namespaces remain **168 / 43 / 15**, the low-level baseline file remains 44 entries, and no native/generated/ABI/upstream/shim change exists. Terminal `committed` records P9-076's part of the combined P9-075/P9-076/P9-077/P9-078 commit landed at `f798e74` after the decisive verifier and parent matrix PASS. Phase 9 remains ACTIVE pending the postcommit all-eight-axis repeat audit, current-tree conformance, and final acceptance; no merge-readiness or release claim is made. | workspace-scratch notes (not retained) |
| P9-077 | Final repeat / API, docs, and text | Supported `TextBuffer.setCell` silently accepts empty/multi-scalar input and unchecked unsigned-width values; `DirectTextAccess` misnames encoded native cell words and exposes an invalid string decoder; selection docs omit the half-open native-cell interval; and the raw TextBuffer wrappers replace distinct nullable, opaque, swallowed, status-free, or cache-partial native outcomes with blanket failure prose (`lib/src/core/text_buffer.dart`; `lib/src/ffi/bindings.dart`; `lib/src/core/buffer.dart`). | P2 | One well-formed Unicode scalar and unsigned index/attribute validation before FFI; truthful encoded-cell words with no decoder shim; `[start, end)` native-cell selection; exact declaration-local 18-method raw outcome matrix | accepted design/specification registration and analyzer-AST RED plan | Supported TextBuffer wrapper, raw binding docs only, Buffer owner migration, existing lifecycle/display-list/source-consumer tests, existing public-member/program guards, tracker/session | committed | Registered as the sole `required-local / blocks` row before production, behavior/consumer tests, or contract-guard changes. Authentic RED was public-member `+11 -1` and source-consumer `+3 -1`; old native characterization passed `+15`. GREEN validates disposal first, unsigned index/attributes, and exactly one well-formed scalar before forwarding it once; exposes `DirectTextAccess.encodedCells` without `chars`/`getChar`; documents exact `00`/`10`/`11` process-global opaque words and split empty/non-empty lifetime; states `[start, end)` selection; and gives exactly 18 raw declarations local Dart-exception and distinct native-outcome truth, including count-bounded non-null-sentinel possibly-partial caches. Focused GREEN is public-member `+12`, lifecycle/display-list `+15`, source consumers `+4`, and selected ownership `+22`; all 36 actual-tree mutations failed before exact restoration. Terminal `committed` records P9-077's inseparable part of the combined P9-075/P9-076/P9-077/P9-078 commit landed at `f798e74`; each later finding came from the preceding mandatory conformance gate, and the decisive verifier and parent matrix PASSed before the commit. Phase 9 stays ACTIVE pending the postcommit all-eight-axis repeat audit, current-tree conformance, and final acceptance. No native failure channel, packed-grapheme decoder, stable 1.0, publication, platform certification, dependency-limit resolution, or merge readiness is claimed. | workspace-scratch notes (not retained) |
| P9-078 | Final repeat / API, docs, and native boundary | Supported write attributes, selection endpoints/order, both supported TextBuffer draw implementations, and all six TextBuffer-family input-bearing guarded raw wrappers did not reject Dart integers outside their fixed-width native domains before mutation/allocation/FFI (`lib/src/core/text_buffer.dart`; `lib/src/core/buffer.dart`; `lib/src/ffi/bindings.dart`). | P1 | Complete fail-closed u8/u16/u32/i32 TextBuffer family; supported lifecycle/semantic/domain/mutation order; one-pass bounded UTF-8 storage; raw width fidelity without invented semantics | base design plus production-ownership and signed-documentation amendments each independently PASS | Exact approved 16-file ceiling: supported TextBuffer/Buffer, guarded bindings, persistent UTF-8 storage, existing behavior/architecture/source-consumer owners, tracker/session/durable inventories | committed | Registration and the sole `required-local / blocks` row preceded production and authentic analyzer-AST RED `+12 -1`. Executor GREEN closes supported u8 write attributes with one bounded UTF-8 update, ordered u32 selection without a length clamp, one shared destination/source/fixed-width draw preflight, signed-i32 coordinates, u32 clip extents, and all six guarded raw wrappers in declaration-local pre-guard order. Exactly one `@internal` captured-handle compositing seam keeps cache/line ownership in `TextBuffer`; `buffer.dart` contains no source-cache query or duplicate line assembly. Exact incremental deltas are production/internal `299/123`, behavior/architecture `402/13`, and administrative `169/53`, all within reviewed ceilings; focused GREEN is `+65`, format is `307/0`, fatal analysis and diff hygiene pass, and the exact 16-file scope plus protected paths and pinned dependency remain intact. After a reviewed signed-documentation fitness correction, all 56 independent actual-tree mutations failed for their intended owners against canonical mutation hash `528f036a9f6a20af72261dfbd66226967a7c838655808546625c6803dc89ad32`, with exact restoration after every case. The decisive independent verifier passed in and the parent mechanical/checkpoint matrix passed before the combined P9-075/P9-076/P9-077/P9-078 commit landed at `f798e74` (a message-only amend of the original commit that removed a disallowed attribution trailer; identical tree). The required fresh Standards Conformance gate ran postcommit instead of precommit — a recorded sequencing deviation, not a waiver — and its FAIL registered successor findings P9-079 and P9-080 without reopening the landed contracts. Postcommit repeat audit, current final acceptance, merge, release, and publication remain pending. | `f798e74` |
| P9-079 | Postcommit conformance / API and native boundary | Public `Buffer.setCell`/`setCellWithAlphaBlending` accept unbounded `int attributes` against the native `u8` slot, producing silent truncation for values above `0xFF`; the six Buffer-family input-bearing guarded raw wrappers (`bufferSetCellWithAlphaBlending`, `bufferDrawText`, `bufferFillRect`, `bufferDrawBox`, `drawFrameBuffer`, `bufferResize`) carry no fail-closed fixed-width validation and keep blanket failure prose instead of declaration-local outcome truth; and `ClippedBuffer._copyTextBufferCells` forwards an unmasked `Uint16List` attribute read into the `u8` compositing call on an implicit invariant (`lib/src/core/buffer.dart:310-346,781,813-822`; `lib/src/ffi/bindings.dart:714-780`; pinned `lib.zig:245-256`; pinned `buffer.zig:83`). | P1 | Fail-closed fixed-width boundary standard established by P9-077/P9-078; GOALS §2/§6 | §2.1 and orchestrator addendum | Supported Buffer cell writes, guarded Buffer-family raw wrappers, clipped TextBuffer compositing seam, existing seam/program guards, tracker/session | committed | The registration preceded the approved design and all production change; the RED characterization proved the reachable defect (`setCellWithAlphaBlending(..., 0x100)` stored `attributes[0] == 0`). The landed contract rejects every out-of-domain fixed-width value with pre-invocation `RangeError`: all six guarded raw wrappers validate their u8/u32/i32 domains in declaration order before `_guard`/`_guardAlloc` and carry declaration-local outcome truth matching the pinned exports; the supported tier validates lifecycle → semantic → domain with the single supported-tier attributes owner in `_setCellCodeWithAlphaBlending` after the bounds check; clipped views validate lifecycle and attributes before the `_inClip` drop while keeping documented signed view-space clipping; no runtime branch was added at the compositing seam, whose ≤0xFF invariant is documented with evidence; and there is no `& 0xFF` masking anywhere, structurally enforced. Authentic RED was validity 5/7-fail (filtered), comprehensive 7/1, seams 13/1, with the dangerous raw partitions written but deferred to GREEN; final gates are validity `+23`, seams `+14`, architecture `+167`, golden `+55`, per-file rendering `+142`, per-file widgets `+156`, format and fatal analysis clean. Production deltas `+76/−1` and `+78/−27`; the bindings removal floor of 27 is mandate-driven (7 banned-prose doc lines plus 20 hoist-relocated body lines) and orchestrator-approved over the `−25` estimate. One retained environmental finding: the combined multi-directory test invocation aborts in this sandbox with a dynamic-loader SEGV, proven pre-existing at baseline `389710b` with the slice stashed; per-file and per-directory runs all pass. Independent verifier PASS with three mutation-catch citations. | workspace-scratch notes (not retained) |
| P9-080 | Postcommit conformance / API, docs, and text | The unreachable `_scanLineInfo` fallback and nullptr-sentinel branch contradict the declared no-sentinel raw contract and the packed encoded-cell documentation, reinterpreting `encodedCells` as plain code points with no behavioral caller; and `_readLineMetadata` trusts `textBufferGetLineCount` past the sized native cache, so a violated finalize precondition fails open into a native over-read instead of fail-closed (`lib/src/core/text_buffer.dart:243-246,262,267-290`; `lib/src/ffi/bindings.dart:526-542`; pinned `text-buffer.zig:329-331,1001-1009`). | P2 | No future-proofing hooks without a current caller (GOALS §5/§6); fail-closed boundary standard; one truth per declaration | §2.2/§2.3 | Supported TextBuffer line metadata, raw binding docs, existing lifecycle/seam guards, tracker/session | committed | The registration preceded the approved design and all production change. Line-metadata reads now fail closed behind a private staleness flag armed by `writeChunk`/`setCell` after their validations and cleared only after the native calls in `finalizeLineInfo`/`reset`; `lineCount`, `lineStarts`, `lineWidths`, `lineInfo`, and the compositing snapshot throw `StateError` naming `finalizeLineInfo` while stale, and stale clipped compositing surfaces that same error. The dead nullptr sentinel, the unreachable `fallbackAccess` branch, and `_scanLineInfo` are deleted so the raw no-sentinel contract and the wrapper body state one truth; the `count == 0` ternary is retained as the raw contract's documented zero-count rule, and the review-driven `_readLineMetadata` body pin locks the sentinel out structurally. Authentic RED was 24 passed / 6 failed against untouched production; focused GREEN `+30`; architecture `+167`; ordinary serial `+1151 ~2`; format and fatal analysis clean; net `−4` production lines with all 45 text-buffer deletions being mandated dead code. Independent verifier PASS with mutation-catch citations; its sole coverage-gap follow-up is closed by the body pin. The pinned-upstream residual (partial cache appends under `catch {}`) stays documented in the raw declarations, not fixed. | workspace-scratch notes (not retained) |
| P9-081 | P9-079 design review / API and native boundary | `DirectBufferAccess.setAttributes` stores an unbounded Dart `int` directly into its `Uint8List` native-memory view, silently truncating values above `0xFF` instead of failing closed; `setChar` is not affected because Dart runes are bounded by `0x10FFFF`, inside the u32 domain (`lib/src/core/buffer.dart:565-568`; pinned `buffer.zig:83`). | P2 | Fail-closed fixed-width boundary standard (P9-077/P9-078/P9-079) | Orchestrator-verified read of the direct-access setters; P9-079 design blast-radius item 7 | Direct-access setters, existing seam guards, behavior tests, tracker/session | committed | The verification preceded the approved design and the production change. `DirectBufferAccess.setAttributes` now validates the unsigned 8-bit attribute domain between its coordinate bounds resolution and the native-memory store, throwing `RangeError` instead of silently truncating; `setChar` is confirmed unaffected (runes are bounded by `0x10FFFF` inside the u32 chars domain) and no other direct-access setter takes a width-exceeding integer — `setForeground`/`setBackground` take `Color` through the documented f32 channel path, and `DirectTextAccess` has no setter. The ordered seams pin locks bounds → domain → store (the sole owner catching a check-after-store mutation), the behavior tests pin named rejection at `-1`/`0x100` plus `0xFF` and astral-plane readbacks, and the P9-079 whole-file masking ban covers this file. Authentic RED `+28 -2` against untouched production; GREEN `+30`; format and fatal analysis clean; production delta `+5/−1`. Independent verifier PASS with mutation-catch citations. | workspace-scratch notes (not retained) |
| P9-082 | Round 3 simplification / core semantics | `Constraints`/`BoxConstraints` are the only geometry value types without `operator ==`/`hashCode`; `PipelineOwner._constraintsEqual` and `RenderParagraph._sameConstraints` are two divergent private re-implementations of the missing equality, and `RenderConstrainedBox`'s equality short-circuit degrades to identity so the non-const `BoxConstraints` that `Container` mints per rebuild re-lays out on every rebuild even when unchanged (`lib/src/render/geometry.dart`; `lib/src/rendering/object.dart:162-176`; `lib/src/rendering/paragraph.dart:237-241`; `lib/src/rendering/constrained_box.dart:29`; `lib/src/widgets/container.dart:213-224`). | P2 | One equality owner per exported value type; exact no-work render invalidation (P9-015) | workspace-scratch notes (not retained) | Geometry value types, two private comparators, invalidation regression coverage, tracker/session | committed | The verification preceded the RED and production change. `Constraints` and `BoxConstraints` now carry value equality with `runtimeType` participation and matching hashes in the file's established idiom, with `@immutable` markers; both divergent private comparators are deleted and their callers use `==`. The exhaustive comparator-swap analysis shows the new equality can never skip a relayout the old comparator performed: the only divergent cases are mixed-runtime-type comparisons that are unreachable in production — both `flushLayout` callers pass the exact `BoxConstraints` minted by `RenderView.terminalConstraints`, and the paragraph cache always compares exact `BoxConstraints` — and they fail safe toward an extra relayout. The regression test assigns non-const field-equal constraints (immune to const canonicalization) through the named `RenderConstrainedBox` setter path and proves no relayout; equality unit tests cover every field, both maxima null forms, and base-versus-subtype in both directions. Authentic RED `+27 -3` against untouched production; focused `+52`; architecture `+168`; ordinary serial `+1156 ~2`; analyzer and format clean. Independent verifier PASS with the full semantics table. | workspace-scratch notes (not retained) |
| P9-083 | Round 3 simplification / Unicode and text | `_ClippedBufferView.drawText` computes its horizontal clip window from `text.length` and slices with `text.substring(...)` — UTF-16 code units used as terminal cell offsets, wrong for CJK and astral-plane content — while `unicode_guard_test.dart`'s checked file list omits `lib/src/core/buffer.dart` (clipped drawText region; GOALS §2 bans code-unit indexing on visual-text paths). | P2 | Grapheme/cell owners in `grapheme_metrics.dart`; GOALS §2 visual-text non-negotiable | workspace-scratch notes (not retained) | Clipped drawText, Unicode guard file list, behavior/golden coverage, tracker/session | committed | The verification preceded the RED and production change. The clipped view now clips in terminal cells through the `grapheme_metrics.dart` owners: a cluster-accumulating skip drops any left-edge straddling wide cluster whole and draws the remainder at the accumulated draw column, not the clip edge (keeping the tail aligned with the unclipped layout), and `sliceByCells` bounds the right edge so a straddling wide cluster is dropped whole. No code-unit arithmetic survives on the visual path, and the Unicode guard now checks `lib/src/core/buffer.dart` with three patterns that each match the old body. The behavior tests derive expected native cells structurally from the packing constants (wide-start/continuation bits and pool ids) for CJK, astral-plane, and ASCII no-regression cases; authentic RED failed exactly the CJK/emoji cases against untouched production. Focused `+21`; architecture `+168`; canonical suite `+1161 ~2` in one run; goldens byte-identical; analyzer and format clean. Independent verifier PASS including the left-edge overshoot re-derivation. Residual: `terminalCellWidth` remains the documented shared approximation under read-only-upstream P9-020; the clipped view is now consistent with the rest of the stack. | workspace-scratch notes (not retained) |
| P9-084 | Round 3 simplification / slices A–D | The round-3 review's accepted behavior-preserving items across the whole production tree: cross-layer dead-code and zero-caller removals (slice A), core/ffi/rendering consolidations (slice C), framework/tools/helper consolidations (slice D), and the documentation-truth sweep with the fourth filler-family guard (slice B). | P2 | Behavior preservation with caller/consumer evidence; GOALS §5/§6 | Four independent reviewer reports plus per-slice executor proofs | Cross-layer production, six fitness guards, test helpers, durable docs, low-level baseline | committed | The four slices landed as `39af145`, `e990fd1`, `400bc28`, and `7a2f5cf`, each with orchestrator-run gates and an independent verifier PASS (slice A after one required stale-reference fix; slice C completed after an executor cutoff, including the `intersectWith` naming that avoids Flutter's different-semantics `enforce`; slice D after one comment-truth correction; slice B after one parity-note correction). Slice A shrank the low-level baseline to 42 symbols by unexporting `FlexChildData`; the current supported namespaces are **168 high / 42 low companion / 15 FFI**. The postcommit all-eight-axis repeat audit independently re-verified the landed changes at `b43969a` and returned CLEAN, standing as the retained cross-slice verification. | workspace-scratch notes (not retained) |
| P9-085 | 2026-08-03 authorized real-terminal review / native lifecycle | The pinned alternate-screen lifecycle moves the main-screen cursor during capability probes before entering the alternate screen; on the observed macOS/iTerm run, shutdown returned to main-screen row 1/column 1 instead of the launch cursor and overwrote earlier shell rows. | P1 | Native owns terminal escape ordering; read-only OpenTUI dependency boundary | Authorized dedicated-window iTerm capture plus pinned Zig source-order inspection | Pinned renderer/terminal source, durable consumer/contributor truth, P9-039 evidence contract, public package limitation guard | verified | Frames 1–5 were clean, one Enter advanced each frame, the shell remained usable, and before/after `stty -g` values were byte-identical; those facts did not prevent the retained main-screen row 1/column 1 overwrite. Pinned `setupTerminal` orders `saveCursorState` before `queryTerminalSend` before `enterAltScreen`, while the query performs two `home` probes before alternate-screen entry. A correct fix requires changing pinned native source and rebuilding the bundled artifacts; Dart-side ANSI/save-slot workarounds would duplicate native ownership. P9-085 therefore remains a visible `read-only-upstream` limitation and is not fixed. | workspace-scratch visual/source-order evidence (not retained) |
| P9-086 | 2026-08-03 validation follow-up / runtime input and lifecycle | `TerminalSession` invokes `Renderer.setupTerminal()` before it constructs and starts `StdinInputDriver`. The raw bindings example directly demonstrated the terminal-line-discipline mechanism: capability replies reached canonical, echoing input and became visible, while an external no-echo control removed the visible replies. The high-level captures were clean and high-level corruption was not reproduced, so the high-level effect remains a timing-race inference. P9-086 is distinct from P9-039 and P9-085. | P1 | Input ownership must precede native capability queries; one owner acquires and exactly restores inherited stdin modes; app/session code does not call FFI | Durable registration slice; a separate implementation architect must derive the minimum complete correction before RED or production edits | TerminalSession, StdinInputDriver, internal capability-response routing, lifecycle/parser/integration tests, existing app/input fitness guards | registered | Not implemented. A future TDD slice must prove input acquisition and capability routing precede setup, exact inherited-mode restoration and failure rollback, complete capability replies emit no application input, and every failure path preserves the primary error while releasing all owners. Closeout also requires separately authorized dedicated-terminal acceptance; P9-039 remains optional evidence and P9-085 remains read-only upstream. | Current Dart/native/reference source order, authorized raw-example mechanism evidence summarized here, durable consumer/contributor truth, and public package limitation guard |

### Native P0 follow-up (post-Round 1)

#### Withdrawn native follow-up

On 2026-07-23 the operator withdrew the additional native follow-up numbered
P9-044 through P9-048 and prohibited its executable fixtures. The associated
local programs and tracked test were removed from the workspace and must not be
recreated or invoked by this phase. Those items are no longer phase gates or
release prerequisites. This withdrawal records scope only; it does not certify
the underlying native behavior.

#### Interaction with P9-011

P9-011 is an independent Round 1 animation finding; its implementation and
semantic proofs are outside this native batch. By the user-approved 2026-07-12
checkpoint policy then in force, that isolated implementation could be
committed and pushed so the workspace could pause and resume from Git. That
historical checkpoint did not advance the ledger row to `checks-clean` or final
`committed` acceptance: the then-required literal default-concurrency
`dart test` gate failed on the historical native tuple, while the serial
diagnostic suite's `+628 ~2` result did not replace it.

The row was reconciled to `committed` at exact HEAD `8876203` only after an
independent current-tree review confirmed that the production and semantic-test
blobs remain byte-identical to implementation commit `4b69b99` and that the
sole later P9-owned path change is unrelated documentation wording. The
temporary local-validation policy added in `8876203` expressly overrides the
repository's test commands and mandatory test gates, so the reconciliation
uses fresh format and fatal-analysis results without claiming an exact-HEAD
test run. This does not rewrite the historical checkpoint, describe P9-011 as
native dependency work, or satisfy Phase 9 close/final acceptance.

#### P9-042 pushed checkpoint

Commit `8cb3ccc` is the user-approved 2026-07-12 resumable checkpoint for the
P9-042 wrapper implementation. The ledger row remains `verified`; this is not
Darwin GREEN, an independent implementation PASS, `checks-clean`, or final
`committed` acceptance. Its final-hash focused selection passed `+13`, scoped
format/analyze/syntax/shellcheck/diff checks passed, and survivor/temp scans
were empty. The last complete broad wrapper/parity run passed `+45` before the
final harness-only timeout/format edits and therefore is not final-hash broad
evidence.

On resume, complete the independent verifier's missing local design oracles:
post-work FIFO injection/open-failure/ceiling zero-new-byte cases, gated
non-sole/mismatched authorization, post-authorization abort precedence, and
event-owned mismatch injection without ordinal coupling. Then rerun the exact
focused/broad/direct parity matrix at final hashes, retain Darwin GREEN, obtain
Linux evidence in GitHub Actions, rerun the independent verifier and current
task/checkpoint gates, and only then advance the P9-042 row.

The 2026-07-13 local-oracle completion slice closes those missing Darwin
oracles. The production delta is one guarded canonical retained-owner
diagnostic in the already-failing unconsumed-cleanup branch; the final fixture
and test hashes are recorded in
the retained local-oracle record. Exact final-hash
ceiling/selector/legacy cases pass, scoped mechanical gates pass, direct
S1/S2/S3 parity passes, and the independent rereview is an **interim
Darwin-local PASS** at report SHA `4269bf17...`. The ledger row deliberately
remains `verified`: the assertion-only final test edit still needs the exact
final broad rerun, the combined wrapper-plus-primitives alarm must be reviewed
for the intentional new bounded cases and rerun, Linux lifecycle evidence must
come from GitHub Actions, and the then-current final repository gates remain.
Do not rewrite the earlier checkpoint history or claim P9-042 complete from
this slice.

The 2026-07-13 closeout checkpoint adds explicit CI ownership for that shell
lifecycle suite: `go_snapshot_wrapper_test.dart` carries the
`process-spawning` tag, the portable Linux/macOS/Windows render matrix excludes
that tag, and the dedicated Ubuntu parity step runs the complete wrapper and
Go parity directory with a 15-minute command bound and a 20-minute Actions
fallback. Its expanded output is retained in a regular file for post-timeout
diagnostics. Those 15m/20m values are exact P9-042 historical evidence;
P9-049 later superseded them with the current 30-minute GNU timeout and
35-minute Actions ceiling, which P9-050 retains unchanged in CI as the sole
parity owner. A Colima Linux/ARM64 reproduction exposed one harness-only
portability error: procps `kill` killed the negative process group but returned
1 without an explicit `--` option terminator. With the terminator, the focused
case passed `+1`, the complete wrapper passed `+52` in 07:10, and the combined
parity gate passed `+54` in 07:31. At the exact Darwin local tuple, the
final broad selector passed `+22` in 03:52, the reviewed 900-second combined
wrapper-plus-primitives gate passed `+54` in 09:16, and direct S1/S2/S3 binary
comparison passed. The portable serial suite passed `+626 ~2`; format,
analysis, architecture, binary verification, CLI build, and publish dry-run
also passed. After earlier unrelated native instability, a fresh literal default-concurrency
`dart test` passed `+679 ~2` in 09:20 on the updated tuple. The P9-042 ledger row
is now `committed`: exact implementation SHA `0ab4f13` passed Ubuntu Actions
job `86920919777` with complete wrapper `+52` and final parity `+54` in 08:20,
and the exact-SHA independent verifier returned an unconditional **PASS**. The
known Windows patch-manager portability failures are separate from P9-042.

#### 2026-07-18 P9-050 parity-harness reliability correction

The P9-050 row's local waiver recorded that two parity attempts failed only
in three unchanged P9-042/P9-043 wrapper cases that pass alone (`+1` each),
with two controls at 29 seconds against a 30-second Dart timeout — a
resumable commit/push waiver, not `checks-clean` or local/remote acceptance.
This correction resolves that blocked state.

The test-only design and its six amendments were recorded in workspace-scratch
notes (not retained). Amendment 1 gave the
wrapper-test file a 60-second `@Timeout`, a 15-second `_Harness.run` default
parent deadline, split the combined 127/138/delayed-127 test into three named
cases (16s/16s/12s), and raised the two post-election INT/TERM ceilings to 45
seconds (timeout case unchanged at 50s). Amendments 2 and 3 replaced the
hand-tuned per-marker `_poll` budgets (3/8/12/16 seconds across eighteen
waiter sites) with one shared 30-second `_pollBudget` default. Amendment 4 raised `stable admission contradictions
fail closed`'s ceiling from 1 to 2 minutes (measured 64-68s composed
runtime). Amendment 5 raised two fixture-facing production `timeoutValue`
floors that raced under fixture pacing: hard-link `childWinner` `'3'` ->
`'12'`, and the FIFO fail-closed loop `'1'` -> `'4'` (with
`_timeoutDiagnosticFor(4)`). Amendment 6 made no test-side change: an
attempted `'4'` for `watchdogWinner` was empirically refuted (race inversion,
child won 2 of 3 focused runs), so the site stayed `'3'`; it instead
documents a transient-liveness escalation gate — a single transient `ps`
read inside the production wrapper's `anchor_identity_is_live` is
unrecoverable, and if the exact signature (`did not observe
watchdog.candidate before wrapper exit` with `action|child|frozen` ->
`cause|protocol|status=1` against a live child) recurs, test-side work stops
and a production hardening change control opens.

Commit `2f266fe` ("test(parity): compose wrapper-test timing budgets
explicitly", `+69 -48`, `test/parity/go_snapshot_wrapper_test.dart` only) is
the sole behavioral delta on top of baseline `028010c`. The complete
`GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart test -r expanded
test/parity --concurrency=1` partition's historical pre-landing evidence
needed six earlier complete attempts
across the six amendments before landing two consecutive clean 97-test
passes: `+94 -3` (21:06) and `+92 -5` (20:39, disjoint failing identities)
before Amendment 3; `+97` (22:08) then `+96 -1` (22:10, stable-admission
ceiling) before Amendment 4; `+95 -2` (23:17) before Amendment 5; `+96 -1`
(22:49, `watchdogWinner` transient miss) before Amendment 6; then `+97`
(22:26) and `+97` (22:22) at the final state, two consecutive. The
non-process partition passed `+629 ~2` (00:16) and the health check passed
`+1` at the same state; `git diff --check`, `dart format` (252 files, 0
changed), `dart analyze --fatal-infos`, and architecture `+70` are all clean.

Independent verification is **VERIFIER-CLEAN**: `scripts/run_go_snapshot.sh`
SHA-256 verified byte-identical to the frozen baseline
`01c68d920ea4885bd78ad469916cf0222bb32152f97d1b9ae5c68270deeacfa6`; fixtures
and `dart_test.yaml` unchanged; no weakened assertion; every amendment
traceable doc-to-code; one historical doc-only defect (a 95- versus
97-test count)
remediated and re-verified; an advisory addendum records the
nonzero-preflight case's 47-48 second in-partition measurement for future
re-derivation if its 60-second ceiling is ever breached.

Proof: workspace-scratch notes (not retained).

### Rejected Round 1 candidates

These 13 candidate suspicions do not create implementation rows. Their source
reports contain the required counter-evidence.

| Candidate IDs | Status | Counter-evidence |
| --- | --- | --- |
| CORE-010–011 | rejected | workspace-scratch notes (not retained) |
| ADTP-010–012 | rejected | workspace-scratch notes (not retained) |
| NL-006–007 | rejected | workspace-scratch notes (not retained) |
| PO-007–008 | rejected | workspace-scratch notes (not retained) |
| RLI-010–011 | rejected | workspace-scratch notes (not retained) |
| UT-008–009 | rejected | workspace-scratch notes (not retained) |

## Per-finding execution

Every verified non-trivial finding follows this loop:

1. A read-only architect writes a design brief with the
   semantic brief, source references, ownership, invariants, test plan, blast
   radius, and smallest complete correction.
2. The executor first demonstrates the defect with a failing semantic test, or
   records explicit structural/documentation proof when a red test cannot
   represent the defect. It then implements the minimum complete correction.
3. An independent verifier writes a review record and
   checks the actual diff for scope, reference semantics, meaningful tests,
   lifecycle, drift, and stale contracts.
4. The orchestrator runs the task gates named by the accepted design:

   ```sh
   dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/
   dart analyze --fatal-infos
   dart test test/architecture/
   <the exact design-scoped semantic test commands>
   ```

5. Commit one finding or one inseparable finding set with a professional
   message, then update this ledger with the evidence and commit.

Before one or more verifier-clean finding commits are pushed, merged, or
handed off together, run the three serial checkpoint partitions once against
that exact checkpoint HEAD:

```sh
dart test --exclude-tags process-spawning --concurrency=1
dart test test/bin/health_check_test.dart --concurrency=1
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart test -r expanded test/parity/primitives_parity_test.dart --concurrency=1
```

The tagged process-lifecycle wrapper suite is not part of the ordinary
checkpoint. It deliberately owns signal, termination, and cleanup-race
behavior and requires exact task-specific authorization.

Behavior fixes and behavior-preserving simplifications land separately. If a
finding exposes a new drift vector, add a fitness function and update the
durable fitness-function inventory in the same reviewed task.

## Repeat-audit stop condition

After every `required-local` finding and residual candidate is committed or
rejected, an independent auditor starts from the current HEAD and repeats
every coverage axis. Any new verified correctness finding reopens the
execution loop. Optional-performance, optional-restricted, and
optional-maintenance rows remain visible but do not block Noir-local
closeout. `read-only-upstream` limitations also remain visible and cannot be
called fixed. Phase 9's Noir-local closeout is complete only when:

- every coverage box is backed by a current audit report;
- every required-local row is committed or rejected with evidence;
- every required-dependency row has its named Noir-local predecessor resolved;
- every read-only-upstream limitation has exact current evidence and no
  repository-local correction is being deferred under that label;
- the per-phase Auditor and Standards Conformance Auditor both report clean;
- `GOALS.md` §7 re-verifies the Noir-owned surface against the current tree
  while explicitly retaining the pinned dependency limitations; and
- all final checks below pass from fresh output.

Once re-earned after P9-086, this stop condition supports the claim “The
post-merge Noir-local Phase 9 validation follow-up is verifier-clean and its
Noir-local closeout is complete against the pinned dependency.” It does not
rewrite or reopen the historical PR #12 merge, and it does not support a stable
1.0, publication, platform certification, or fully corrected native/Unicode
claim.

## Final checks

```sh
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/
dart format --output=none --set-exit-if-changed hook/ scripts/
dart analyze --fatal-infos
dart test test/architecture/
dart test --exclude-tags process-spawning --concurrency=1
dart test test/bin/health_check_test.dart --concurrency=1
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart test -r expanded test/parity/primitives_parity_test.dart --concurrency=1
dart run scripts/fetch_opentui_binaries.dart --verify-only
git diff --check
```

Also run every affected focused, golden, and ordinary hermetic integration
suite.

### Authorization-gated supplemental evidence

Run the process-lifecycle wrapper suite only for a task that changes that
ownership and only with exact authorization. Real terminal, PTY/ConPTY,
raw-mode, visual-session, deliberate signal/kill, CLI archive,
publication/release, and remote workflow operations are separate restricted
evidence. OpenTUI source, gitlink, ABI, artifact, manifest, and workflow
mutations remain outside this program. None becomes a Phase 9 gate merely
because a historical checkpoint or optional design used it.

P9-039 owns any future terminal-lifecycle evidence/harnesses. Newly observed
runtime findings receive normal ledger rows rather than being hidden inside
that optional project: P9-085 records the read-only native cursor limitation,
while P9-086 separately records required Noir-local input/query ordering.
P9-040 owns any future retained release-candidate evidence tied to an audited
HEAD across Linux, macOS, and Windows. Neither optional row is implemented or
waived by this rebaseline.

## Non-goals

- Invent findings or features before evidence demonstrates a contract gap.
- Rewrite the history or status of the v1 acceptance.
- Duplicate or silently supersede the parity roadmap.
- Preserve obsolete APIs or add future-proofing hooks.
- Optimize without a measured risk or bottleneck.

## What landed

- **Latest local slice — P9-084 (2026-08-02):** the round-3 simplification
  closeout. Slices A–D landed as `39af145`/`e990fd1`/`400bc28`/`7a2f5cf`
  (dead-code and zero-caller removals including the `FlexChildData` unexport
  shrinking the low-level baseline to 42; core/ffi/rendering and
  framework/tools/helper consolidations; the documentation-truth sweep with
  the fourth filler-family guard), each independently verified. P9-082
  (`43063ca`) gave the constraint types value equality and deleted both
  divergent comparators; P9-083 (`b43969a`) made the clipped view clip text
  in terminal cells and extended the Unicode guard. The all-eight-axis
  repeat audit re-verified the whole set at `b43969a`: CLEAN.
- **Prior local slice — P9-083 (2026-08-02):** clipped-view text clipping in
  terminal cells; see the ledger row (review notes were workspace-scratch,
  not retained).
- **Prior local slice — P9-082 (2026-08-02):** constraint value equality and
  comparator consolidation; see the ledger row (review notes were
  workspace-scratch, not retained).
- **Prior local slice — P9-081 (2026-08-01):**
  `DirectBufferAccess.setAttributes` rejects out-of-domain attributes with
  `RangeError` between its coordinate bounds resolution and the
  native-memory store, closing the last known silent typed-list truncation;
  `setChar` is confirmed safe (runes fit the u32 chars domain) and no other
  direct-access setter takes a width-exceeding integer. The ordered seams
  pin locks bounds → domain → store and the P9-079 masking ban covers the
  mask variant. Authentic RED `+28 -2`, GREEN `+30`, production `+5/−1`;
  independent verifier PASS with mutation-catch citations. Evidence:
  workspace-scratch notes (not retained).
- **Prior local slice — P9-080 (2026-08-01):** line-metadata reads fail
  closed behind a private staleness flag armed by `writeChunk`/`setCell` and
  cleared only after successful `finalizeLineInfo`/`reset`; stale reads and
  stale clipped compositing throw `StateError` naming `finalizeLineInfo`.
  The dead nullptr sentinel, unreachable `fallbackAccess` branch, and
  `_scanLineInfo` are deleted so the raw no-sentinel contract has one truth,
  the `count == 0` ternary is retained as the documented zero-count rule,
  and the review-driven `_readLineMetadata` body pin locks the sentinel out.
  Authentic RED 24 passed / 6 failed; focused GREEN `+30`; architecture
  `+167`; ordinary serial `+1151 ~2`; net `−4` production lines; independent
  verifier PASS. Evidence: workspace-scratch notes (not retained).
- **Prior local slice — P9-079 (2026-08-01):** the Buffer family now fails
  closed exactly like the TextBuffer family. The RED characterization proved
  the reachable defect (`setCellWithAlphaBlending(..., 0x100)` stored
  attribute `0`); the landed contract rejects every out-of-domain u8/u32/i32
  value with pre-invocation `RangeError` across the supported Buffer surface,
  all six guarded raw Buffer-family wrappers (declaration-order checks before
  `_guard`/`_guardAlloc`, declaration-local outcome truth matching the pinned
  exports), and the clipped views (lifecycle and attributes validated before
  the `_inClip` drop, view-space coordinates keeping documented silent
  clipping). The compositing seam documents its ≤0xFF invariant through the
  single supported-tier owner with no new runtime branch and no `& 0xFF`
  masking anywhere, structurally enforced. Gates: validity `+23`, seams
  `+14`, architecture `+167`, golden `+55`, per-file rendering `+142` and
  widgets `+156`, format/fatal analysis clean; independent verifier PASS with
  three mutation-catch citations. Retained environmental finding: the
  combined multi-directory test invocation SEGVs in this sandbox's dynamic
  loader, proven pre-existing at baseline `389710b`. Evidence:
  workspace-scratch notes (not retained).
- **Prior local slice — P9-075/P9-076/P9-077/P9-078 combined commit
  (2026-08-01):** the four inseparable TextBuffer contract slices landed
  together at `f798e74`, a message-only amend of the original combined commit
  that removed a disallowed attribution trailer over an identical tree.
  P9-075 makes `TextBuffer.create` named-only and empty with truthful logical
  native-cell length; P9-076 makes `writeChunk` effect-only `void` with
  opaque raw-result truth; P9-077 lands one-scalar `setCell` validation,
  `encodedCells` without a decoder shim, half-open `[start, end)` selection,
  and the exact 18-declaration raw outcome matrix; and P9-078 closes the
  fail-closed u8/u16/u32/i32 TextBuffer-family boundaries. Registration
  preceded authentic RED in every slice, and the independent mutation sweeps
  were 19, 21, 36, and 56 actual-tree failures with exact restoration. The
  decisive verifier passed (workspace-scratch notes, not retained); the parent
  matrix checkpoint passed (workspace-scratch notes, not retained) with
  architecture `+165`, focused `+65`, ordinary serial `+1133 ~2`, health
  `+1`, primitive parity `+2`, and six-artifact verification. The required
  fresh Standards Conformance gate ran postcommit instead of precommit — a
  recorded sequencing deviation, not a waiver — and returned FAIL
  (workspace-scratch notes, not retained),
  registering P9-079 and P9-080 and correcting the low-level baseline claim
  to the 44-entry file. The supported namespaces at that checkpoint were
  **168 / 43 / 15**; no
  native failure channel, packed-grapheme decoder, stable 1.0, publication,
  platform certification, dependency-limit resolution, or merge readiness is
  claimed.
- **Prior local slice — P9-037 + P9-074 terminal task closeout (2026-08-01):**
  all 227 exact P9-037 filler comments across 39 library files are replaced by
  independently verified semantic contracts, with zero known filler hits and
  no changed non-Dartdoc library line. The deep plan now carries the missing
  sixth pinned/read-only OpenTUI hard rule with its exact top-level placement
  and five semantic families.
  P9-037 evidence is focused `+1`, API/member/distribution `+27`, semantic
  preservation `+184`, architecture `+158`, ordinary `+1119 ~2`, health `+1`,
  primitive parity `+2`, format `307/0`, fatal analysis and dartdoc clean,
  six-binary verification, bijective 227-key attestation, and independent
  verifier PASS. P9-074 authentic RED is five blocks (`+18 -1`), preliminary
  GREEN is `+19`, and eight actual-tree mutations fail across deletion,
  nesting, splitting, and all five semantic families before exact restoration.
  P9-037's 39 library files and semantic guard retain their frozen hashes.
  Both task rows use terminal `committed` as the self-description of the one
  combined commit being prepared for the final exact-tree verifier,
  checkpoint, and Standards Conformance gates. Phase 9 remains ACTIVE; this
  task closeout does not claim final acceptance or PR merge readiness.
  Evidence: workspace-scratch notes (not retained).
- **Prior local slice — P9-036B (2026-08-01):** shipped and durable guidance
  now matches the final owning `TuiApp` lifecycle and committed three-tier API
  surface. It documents synchronous handle ownership, app-priority idempotent
  registrations, idempotent cleanup, headless renderer absence, ordinary /
  advanced / raw-FFI imports, and the framework-owned Element and paint
  backend boundary. The stale chat detach comment and eager-ticker `..stop()`
  no-op are deleted with chat/ticker preservation `+6`. Authentic structural
  RED was `+29 -3`; focused green is `+32`; architecture is `+157`; format is
  `306/0`; fatal analysis and dartdoc are clean; ordinary is `+1118 ~2`;
  health is `+1`; primitive parity is `+2`; six binaries verify; protected
  scope/diff hygiene is clean; and independent verification PASS. P9-036 is
  now committed, the superseded compiler/archive mechanism remains retired,
  and at that checkpoint P9-037 was the sole remaining Noir-local task.
  Evidence: workspace-scratch notes (not retained).
- **Prior local slice — P9-038 (2026-08-01):** the supported namespace is
  exactly **168 high / 43 low companion / 15 FFI** at that checkpoint (the
  round-3 slice A later shrank the low tier to 42). Ordinary apps receive the
  narrow `TuiApp` facade; advanced hosting and custom rendering use the
  companion tier; shared semantic values remain FFI-free; and the exact
  eight-method `TuiCanvas` exposes paint vocabulary without Element,
  display-list/compositor, raw owner, or native-allocation machinery.
  Structural REDs were `+5 -5`, `+1 -6`, `+1 -3`, and `+1 -8`; the independent
  correction loop closed all seven findings. Final evidence is architecture
  `+154`, source consumers `+4`, focused semantics `+106`, format `306/0`,
  fatal analysis and dartdoc clean, ordinary `+1115 ~2`, health `+1`, primitive
  parity `+2`, six-artifact verification, protected scope/diff hygiene clean,
  and independent final review PASS. Evidence: workspace-scratch notes
  (not retained).
- **Earlier local slice — P9-031 (2026-07-31):** TextArea no longer traverses
  Elements on controller notifications. One final private State-lifetime
  holder receives the latest successfully completed render-layout size through
  the private leaf; State consumes only a both-positive pair and otherwise
  uses the whole `(widget.width ?? 80, widget.height)` fallback. The public
  `RenderTextArea` constructor and barrel exports remain unchanged. Exact-HEAD
  readiness/design PASS; structural RED `+5 -1`; old-production semantic
  baseline `+13`; corrected focused guard/controller `+19`; design-scoped
  semantics/goldens `+45`; serial direct-constructor coverage `+38`;
  architecture `+143`; format `301/0`; final ordinary serial checkpoint
  `+1102 ~2`; health `+1`; primitive parity `+2`; fatal analysis, diff hygiene,
  protected-path checks, and final independent verification PASS. The initial
  verifier-found fresh-holder false-pass is corrected. An initial
  default-parallel direct-constructor run encountered an unexpected native bus
  error after `+35`; the decisive serial rerun passed `+38`. The retained
  failure was not a deliberate/restricted crash probe, and no native, FFI,
  workflow, restricted-operation, or public-API work was performed. Evidence:
  workspace-scratch notes (not retained).
- **Prior local slice — P9-005D (2026-07-31):** one internal Dart validator
  rejects non-positive renderer create/resize dimensions before the unsigned
  FFI boundary, invalid resize preserves cached buffer state, and
  `WidthMethod` now exposes exactly `wcwidth(0)` and `unicode(1)`. RED
  `+12 -3`, focused `+28`, architecture `+141`, format `283/0`, fatal analysis,
  verifier PASS, and protected diff clean. P9-005N remains read-only upstream;
  no native source, artifact, manifest, workflow, or ABI work was performed or
  described as fixed. Evidence: workspace-scratch notes (not retained).
- The 2026-07-29 program rebaseline makes the existing OpenTUI submodule and
  six ABI-2 artifacts read-only, replaces the obsolete fork/Actions/native-roll
  continuation with five Noir-local rows, keeps native/Unicode limitations
  visible and nonblocking, and administratively closes P9-041 with Tasks 1 and
  2 complete and the exact-three shim intentionally retained. Structural RED
  was `+31 -9`; corrected focused guards pass `+43`; architecture passes
  `+139`; format is `301/0`; fatal analysis, six-artifact verification, and
  diff hygiene pass; the independent implementation verifier and
  standards-conformance re-review both pass. The first ordinary serial
  checkpoint retained the existing bundled-validation SIGSEGV/exit `134` at
  `+347`; one retry passed `+1077 ~2`, followed by health `+1` and primitive
  parity `+2`. The retry does not erase the crash, and no protected dependency
  or restricted operation changed.
- P9-036A corrected the shipped Noir skill, four retained references, example
  guide, and contributor-only helper guide against current source truth.
  Package consumers are separated from private source-checkout helpers;
  instance/sync signatures, integer layout contracts, Tab traversal, capture
  roles, inspector singleton use, supported imports, safe commands, and
  qualified Flutter comparisons are structurally guarded. Authentic RED,
  independent mutation evidence, analyzer proof, and implementation
  verification pass. P9-036B subsequently completed the final lifecycle/tier
  wording, so whole P9-036 is committed; the superseded compiler/archive
  mechanism was not restored.
- P9-026 replaced ambiguous hunk/file staging with exactly two typed units:
  canonical content-only patches and truthful whole-file changes. Whole-file
  transport reuses P9-027A's immutable raw Git identity and sole literal-NUL
  pathspec encoder; content headers preserve opaque Git openers only as a
  non-authoritative patch envelope. Typed repository outcomes, target-local
  controller state,
  direct whole-only previews, and a refresh-required staging interlock make
  uncertain mutation visible and recoverable without restoring P9-029's
  retired workflow or changing P9-028 load-generation ownership.
- P9-027A established one lossless Git identity boundary on the smaller Patch
  Manager model: command streams are bytes, raw `-z` records authoritatively
  own immutable `GitPath` identities, patch headers corroborate without
  rediscovering identity, stable IDs use exact bytes, invalid-UTF8 identities
  never reach filesystem APIs, literal NUL-delimited pathspec stdin owns
  mutation, and printable ASCII presentation is derived only at the UI or
  diagnostic edge. Fixed ordinal two-block grouping covers real Git type
  changes without making them content-stageable. P9-027B remains downstream
  of the read-only P9-020 limitation; landed P9-026 consumes this transport
  without another decoder.
- P9-029 made the visible workspace `DiffSet` the sole Patch Manager load
  payload and removed the retired approval/index-preview/snapshot/shortstat
  workflow, hunk-only adapters, silent refresh branch, dead section toggles,
  and unread presentation data. Reachable direct staging, skip, refresh,
  P9-028 generation ownership, and byte-identical rendered goldens remain on
  the smaller model; landed P9-027A and P9-026 preserve that shape without
  resurrecting the retired surface.
- P9-058 contains framework lifecycle failures without a transaction layer:
  fresh child inflation rolls back while preserving the original mount error,
  multi-child mount publishes each success before the next attempt, built-in
  teardown and inactive finalization attempt every independent cleanup once,
  and terminal owner disposal clears root, input, focus, key-handle, pipeline,
  and scheduler-callback ownership while preserving the first error and stack.
- P9-057 closed the real P9-030 duplication through a smaller one-store
  design: `RenderObjectWithSingleChild` now derives one authoritative generic
  edge across all six owners, publishes coherent structure before scheduling
  errors escape, and deletes the six concrete child shadows plus duplicate
  traversal/default paint. Single- and multi-child protocols remain distinct;
  no typed-owner layer, transaction, rollback machinery, or Flutter linked
  list was added.
- P9-056 made resize publication failure-atomic: invalid and same-size
  requests are true no-ops, renderer resize succeeds before session geometry
  changes, and `TuiBinding` schedules only an applied change.
- P9-055 made inherited dependency and focus-tree membership identity-based,
  including supplied-node replacement and traversal lookup, so supported
  equality-overriding subclasses cannot collapse distinct framework nodes.
  Widget-key reconciliation intentionally keeps its declared semantic
  equality.
- P9-054 replaced forward-search multi-child matching with positional
  prefix/suffix reconciliation and keyed-only unmatched-middle movement.
  Duplicate sibling keys now fail before mount/update mutation, while keyed
  reorders and compatible one-point edits retain Element, State, and
  RenderObject identity without attachment churn.
- P9-060 historically rebaselined active-program ownership at its 2026-07-24
  checkpoint: required local and native/Unicode work then remained blocking;
  optional performance, terminal, and release evidence was removed from the
  core gate; and the live guards were inventoried. Its native-blocking
  disposition is superseded by the 2026-07-29 read-only dependency decision;
  the authorized local partitions remain.
- `6ebfb75` — activated the evidence-led Phase 9 workflow; restored the
  canonical `CLAUDE.md` link; synchronized all 23 architecture guards across
  durable inventories; normalized stale barrel and roadmap context; and added
  revision-topology, parity-blocker, publication, and downstream-consumer
  proof requirements.
- `88d739a` — consolidated all 67 Round 1 candidate dispositions into 42
  independently verified implementation tasks, recorded the one qualified
  parity-roadmap exception and 13 evidence-backed rejections, and completed
  all eight Round 1 coverage axes without advancing the clean re-audit.
- `3f0a38f` — made terminal-session construction, root mounting, and binding
  teardown exception-safe; preserved the causal error and stack; isolated
  every cleanup boundary; and proved owned-resource release, cancellation,
  terminal restoration, reentrancy, and at-most-once disposal under failure.
- `278eea3` — introduced the BuildOwner-owned `GlobalKey` registry and
  inactive-element lifecycle: same-parent reorders reuse Element/State,
  duplicate live keys throw, and registration is now `@internal` rather than
  public app API. It also introduced document-order-only cross-parent reclaim,
  which P9-059 supersedes with the final lookup/same-parent contract.
  Independent review surfaced two liveness regressions the new
  deactivate/inactive window opened (ghost rebuild in `buildScope` and ghost
  notify in `notifyDependents`) and a lost-dispose-at-teardown path; all three
  were fixed with their own red/green proof and an `active` liveness gate.
- `c6bdb94` — aligned inherited-widget notification with Flutter:
  `InheritedElement.update` notifies dependents before rebuilding the proxy
  child, `State.didChangeDependencies` is deferred to the dependent's rebuild
  via a flag (so a dependent removed mid-pass is never notified), and a
  `clearDirty`/`buildScope` dedup guarantees one `didChangeDependencies`
  immediately followed by one build per change. Corrected the test that had
  locked the stale-then-rebuild order.
- `982198e` — brought the `State` lifecycle to Flutter parity:
  `StatefulElement.unmount` now disposes while the State is still attached
  (mounted, readable context, once, children bottom-up) then detaches;
  `setState` after teardown throws a descriptive `StateError` in every build
  mode instead of silently dropping in release; and `attach`/`updateWidget`/
  `detach` are `@internal`. Closes the `State` half of ADTP-004 (the GlobalKey
  half landed in `278eea3`).
