# Phase 9 current integration handoff

Updated: 2026-08-03

> **Evidence note (2026-08-03):** Per-task artifacts written under the
> workspace-scratch `.context/` directory were never committed and are not
> retained. The durable evidence for the claims below is the committed code,
> the committed test suite, and the referenced commit hashes.

## Current decision

PR #12 merged to `master` as `d24a1fd` on 2026-08-03. Its former
`leoafarias/reference-review-goal` branch and pre-merge handoff are historical,
not the current workspace or an open integration decision.

The current post-merge validation follow-up runs on local branch
`leoafarias/verify-1.0-readiness-review`, configured to track
`origin/leoafarias/verify-1.0-readiness-review`. Git reports that the local
branch is ahead of its configured upstream. Its target/base is `origin/master`
at merged PR #12 commit `d24a1fd`; the P9-086 registration slice began from
local committed base `268b18e`.

Historically, the combined P9-075/P9-076/P9-077/P9-078 commit landed at
`f798e74`, a message-only amend of the original combined commit that removed a
disallowed attribution trailer over an identical tree; the amended head was
pushed with lease to the then-unreviewed PR. The decisive independent verifier
and the parent mechanical/checkpoint matrix both passed before the commit. The
required fresh Standards Conformance gate ran postcommit instead of precommit
— a recorded sequencing deviation, not a waiver — and returned FAIL with two
successor findings: P9-079 (Buffer-family fixed-width boundaries, P1) and
P9-080 (unreachable line-scan fallback and unbounded line-metadata reads, P2).
Both were registered `required-local / blocks` rows before any design, RED, or
production change, and both have since landed verifier-clean in their own
commits, followed by P9-081 from the P9-079 design review. The landed TextBuffer
contracts themselves re-verified conforming; the failures were successor
findings, not regressions of the four landed slices. The round-3 simplification
review then verified P9-082 and P9-083, both since landed verifier-clean; at
that audited checkpoint, no
`required-local / blocks` rows remained open. P9-086 below is a later
validation finding and does not rewrite that checkpoint history.

The former OpenTUI fork branch, native artifact roll, and GitHub Actions build
plan is superseded by the read-only dependency decision recorded in
`GOALS.md`.

## OpenTUI dependency boundary

`external/opentui` is a read-only Git submodule pinned at
`ddbc9edf81a1fa89961135ab0481df15054ed4b0`. Its configured
`leoafarias/opentui` URL records source and artifact provenance; it does not
authorize changes to that repository.

No OpenTUI source, gitlink, ABI, binary, manifest, provenance URL, branch,
tag, or workflow mutation is part of this program. Agents may initialize and
inspect the pinned submodule, use the six checked-in ABI-2 artifacts, and run
read-only verification. Do not edit or advance the submodule, create or push
OpenTUI refs, dispatch or re-enable OpenTUI workflows, rebuild or replace
bundled libraries, or roll the native ABI/manifest.

The native/Unicode findings remain documented limitations. They are not
presented as fixed; they did not block the historical PR #12 merge and do not
become current Noir-local work. P9-086 is separate required local work and does
block current Phase 9 closeout. Reversing the native dependency boundary
requires a separate explicit dependency-strategy decision.

## Exact checkpoint

- current validation branch: `leoafarias/verify-1.0-readiness-review`
- configured upstream:
  `origin/leoafarias/verify-1.0-readiness-review`; the local branch is ahead of
  that remote tip (`711eac3`)
- registration-slice committed base:
  `268b18e38e3074ae287480e67cd56ccccd76e86e`
- target/base: `origin/master` at `d24a1fd`
- historical PR #12 merge:
  `d24a1fd8ed00673b638fd668546b7fc4498c67f7`
- historical PR #12 branch: `leoafarias/reference-review-goal`; its configured
  remote branch is gone
- audited code/document checkpoint before this rebaseline:
  `e0b3d198fcbec7f109838fdaca77ed4e2c8be357`
- historical P9-005D task checkpoint:
  `d31e112eaec6161ab15af39218b5466433264803`
- parity Task 1:
  `817c82c19f56f52ee4da58ffca1737f45e7502e3`
- parity Task 2:
  `3cc34fcaa66c49af34b9adc39c33f0886817530f`
- P9-026:
  `a18c00191dd321c700cfaeb198133927730acf18`
- P9-036A:
  `7acfb96c090f7587b56b37059af3b03b92c343bb`
- P9-031 / P9-038 implementation base:
  `20be184fe7960aaf802085d083c5c8d95678b412`
- P9-038 landed / P9-036B exact base:
  `88a58a2245f24649fa7f33a683cf52f55c758b2a`
- P9-036B landed / combined P9-037 and P9-074 exact base:
  `039b6f4dcea71abe605bcb491104dff6065cd7c6`
- combined P9-037/P9-074 landed / P9-075 exact base:
  `4ed3eba7446fd52c097b828e936d9d3575919b2b`
- combined P9-075/P9-076/P9-077/P9-078 commit:
  `f798e744f918cca53b71bc40f4205cd8c01771f0`
- pinned OpenTUI source:
  `ddbc9edf81a1fa89961135ab0481df15054ed4b0`

Always reconfirm branch, upstream relation, target/base, submodule identity,
and worktree before resuming after a handoff.

## Remaining Noir-local work

The 2026-08-02 closeout checkpoint had no `required-local / blocks` rows, and
every then-current closing gate ran from fresh output. The postcommit
all-eight-axis repeat audit is CLEAN at `b43969a`, and the combined final
Standards Conformance and GOALS §7 acceptance audit is PASS with its
documentation follow-ups closed by the closeout commit (every §7 box passed
from fresh output with no waiver needed).

That checkpoint earned the target outcome:

> Noir-local Phase 9 work is verifier-clean, locally validated, and PR #12
> is ready to merge against the pinned OpenTUI dependency.

PR #12 then merged to `master` as `d24a1fd` on 2026-08-03. A later validation
follow-up registered P9-086 as the current `required-local / blocks` row, so
Noir-local Phase 9 closeout is open again and that historical target statement
must not be reused for the current tree until P9-086 completes its full task
workflow. The package version stays `0.1.0-dev.1`; release/publication
decisions remain tracked in `tasks/1.0-verification-plan.md` §5. No stable 1.0,
publication, platform certification, dependency-limit resolution, or release
is claimed. Phase 9 remains ACTIVE. No native failure channel,
packed-grapheme decoder, or platform-runtime certification is implied by the
historical checkpoint.

## Current Noir-local required work — P9-086

Current `TerminalSession` source invokes `Renderer.setupTerminal()` before it
constructs and starts `StdinInputDriver`. Pinned setup synchronously emits its
native capability-query batch, while the stdin driver does not acquire
terminal modes or listen for replies until `start()`. The raw bindings example
directly demonstrated that terminal-line-discipline mechanism: capability
replies arrived while stdin was canonical and echoing and became visible;
applying only external no-echo removed the visible replies.

The high-level captures were clean and high-level corruption was not
reproduced. That does not disprove the unsafe window; it qualifies the public
effect as a timing-race inference instead of an observed high-level frame
failure. P9-086 is therefore a P1 `required-local / blocks` finding, distinct
from optional P9-039 evidence and read-only-upstream P9-085 restoration.

The next step is a separate full architect → TDD executor → independent
verifier → mechanical and authorized dedicated-terminal acceptance → commit
workflow. It must put one failure-atomic stdin-mode owner and the internal
capability-response route in place before setup, restore inherited modes
exactly, preserve first-error cleanup semantics, and emit no application input
for capability replies. Do not fold that production work into this
registration slice or into P9-039/P9-085.

## Read-only upstream limitations

These remain open findings but are not executable or merge-blocking under the
current dependency boundary:

- P9-005N native guarded-operation/status contract;
- P9-018 failure-atomic, command-complete destination clipping;
- P9-020 exact OpenTUI-compatible terminal-cell width;
- P9-021 packed multi-code-point grapheme storage and routing;
- P9-022 native-cell selection mapping;
- P9-023 exact terminal-cell preferred vertical caret column;
- P9-027B Unicode-friendly exact-cell path presentation;
- P9-085 exact alternate-screen main-screen content and launch cursor
  restoration; and
- parity Task 3 removal of the exact-three TextBuffer shim.

Keep the current reversible ASCII-safe path presentation and the fail-fast
test-only TextBuffer shim. Do not replace either with a knowingly partial
local approximation.

### 2026-08-03 terminal-lifecycle evidence — P9-085

An authorized dedicated-window macOS/iTerm run produced clean application
frames 1–5 and a usable shell after exit. The inherited stdin modes restored
byte-for-byte: before and after `stty -g` both hashed to
`00e0e45635e79ca788f0ab621d8a9bceeced0a21619376ca709f2254df8b3464`.
Nevertheless, shutdown returned to main-screen row 1/column 1 instead of the
launch cursor, so the success line and shell overwrote earlier command rows.

Pinned source explains that result: `CliRenderer.setupTerminal` writes
`saveCursorState`, runs `queryTerminalSend` with two main-screen `home` probes,
and only then calls `enterAltScreen`. The correct fix requires changing pinned
native source and rebuilding the six bundled artifacts. P9-085 is therefore a
P1 `read-only-upstream / does not block` limitation, not a Noir-local fix or a
reason to skip disposal. P9-039 may later characterize it with repeatable
PTY/ConPTY evidence, but does not own or supply the correction.

## Optional non-goals

- P9-032/P9-033 remain measurement-gated performance proposals.
- P9-039 remains a separately authorized PTY/ConPTY/real-terminal evidence
  project; it may characterize runtime lifecycle findings but does not own the
  required P9-086 implementation or the P9-085 native correction.
- P9-040 remains optional remote release-candidate evidence.
- P9-071 remains optional dependency maintenance without a demonstrated
  compatibility, security, or tooling reason.
- Do not dispatch dormant GitHub workflows, publish, tag, release, or claim
  platform certification as part of this closeout.

## Parity roadmap status

The repository-local parity roadmap is closed for the current pinned
dependency:

- Task 1 is complete at `817c82c`;
- Task 2 is complete at `3cc34fc`; and
- Task 3 is intentionally retained as an upstream-triggered cleanup because
  all six artifacts still lack the exact three required TextBuffer symbols.

P9-039/Task 4 remains optional and does not block the local roadmap or current
Phase 9 closeout.

## Latest completed slice — P9-083

P9-083 is verifier-clean and complete as of 2026-08-02. The clipped view
draws text clipped in terminal cells through the `grapheme_metrics.dart`
owners: straddling wide clusters are dropped whole at both clip edges, the
remainder draws at the accumulated draw column so the tail stays aligned
with the unclipped layout, and no code-unit arithmetic survives on the
visual path. The Unicode guard now checks `lib/src/core/buffer.dart` with
patterns proven against the old body. Structural CJK/emoji/ASCII tests
derive expected native cells from the packing constants. Focused `+21`;
architecture `+168`; canonical suite `+1161 ~2`; goldens byte-identical;
Independent verifier PASS. The `terminalCellWidth` approximation remains the
documented shared residual under read-only-upstream P9-020.

## Prior slice — P9-082

P9-082 is verifier-clean and complete as of 2026-08-02. `Constraints` and
`BoxConstraints` carry value equality with `runtimeType` participation in
the file's established idiom; the two divergent private comparators are
deleted, and the non-const field-equal regression proves `Container`-path
constraint updates no longer relayout when unchanged. The exhaustive
comparator analysis shows the swap can never skip a relayout the old code
performed and fails safe for unreachable mixed-type cases. Authentic RED
`+27 -3`; focused `+52`; architecture `+168`; ordinary serial `+1156 ~2`;
Independent verifier PASS. Artifacts: workspace-scratch design/proof/review
notes (not retained).

## Prior slice — P9-081

P9-081 is verifier-clean and complete as of 2026-08-01.
`DirectBufferAccess.setAttributes` now rejects attribute values outside the
unsigned 8-bit domain with `RangeError` between its coordinate bounds
resolution and the native-memory store, closing the last known silent
typed-list truncation. `setChar` needs no check because Dart runes are
bounded by `0x10FFFF` inside the u32 chars domain, and no other
direct-access setter takes a width-exceeding integer. The ordered seams pin
locks bounds → domain → store — the sole owner catching a check-after-store
mutation — and the P9-079 whole-file masking ban covers the mask variant.

Evidence: authentic RED `+28 -2` against untouched production (the silent
store was confirmed first); GREEN `+30`; format and fatal analysis clean;
production delta `+5/−1`. Independent verifier PASS with mutation-catch
citations.

Artifacts: workspace-scratch design/proof/review notes (not retained).

## Prior slice — P9-080

P9-080 is verifier-clean and complete as of 2026-08-01. Line-metadata reads
now fail closed: `writeChunk` and `setCell` arm a private staleness flag
after their validations and before their native calls, `finalizeLineInfo`
and `reset` clear it only after their native calls succeed, and `lineCount`,
`lineStarts`, `lineWidths`, `lineInfo`, and the compositing snapshot throw
`StateError` naming `finalizeLineInfo` while stale — including stale clipped
compositing. The dead nullptr sentinel, the unreachable `fallbackAccess`
branch, and `_scanLineInfo` are deleted, so the raw no-sentinel contract and
the wrapper body state one truth; the `count == 0` ternary is retained as
the raw contract's documented zero-count rule; and the review-driven
`_readLineMetadata` body pin locks the sentinel out structurally.

Evidence: authentic RED 24 passed / 6 failed against untouched production;
focused GREEN `+30`; architecture `+167`; ordinary serial `+1151 ~2`; format
and fatal analysis clean; net `−4` production lines with every deletion
being mandated dead code. Independent verifier PASS with mutation-catch
citations; its sole coverage-gap follow-up is closed by the body pin. The
pinned-upstream residual (partial cache appends under native `catch {}`)
stays documented in the raw declarations, not fixed.

Artifacts: workspace-scratch design/proof/review notes (not retained).

## Prior slice — P9-079

P9-079 is verifier-clean and complete as of 2026-08-01. Public `Buffer` cell
writes and draw/resize methods now reject out-of-domain fixed-width values
with pre-invocation `RangeError`, so the formerly reachable silent `u8`
truncation is impossible: the RED characterization proved
`setCellWithAlphaBlending(..., 0x100)` stored attribute `0`, and the landed
contract throws instead. All six Buffer-family guarded raw wrappers
(`bufferDrawText`, `bufferFillRect`, `bufferDrawBox`,
`bufferSetCellWithAlphaBlending`, `drawFrameBuffer`, `bufferResize`) validate
their u8/u32/i32 domains in declaration order before `_guard`/`_guardAlloc`
and carry declaration-local outcome truth matching the pinned exports.
Clipped views keep their documented signed view-space clipping while
lifecycle and attributes are validated before the `_inClip` drop; the
compositing seam documents its ≤0xFF invariant through the single
supported-tier owner with no new runtime branch and no `& 0xFF` masking
anywhere, structurally enforced.

Evidence: authentic RED (filtered validity 5/7-fail, comprehensive 7/1,
seams 13/1) with the dangerous raw partitions written but deferred to GREEN;
final focused validity+comprehensive `+23`, seams `+14`, architecture `+167`,
golden `+55`, per-file rendering `+142` and widgets `+156`, format and fatal
analysis clean. Production deltas are `+76/−1` and `+78/−27`; the bindings
removal floor of 27 is mandate-driven and orchestrator-approved over the
`−25` estimate. One environmental finding is retained truthfully: the
combined multi-directory test invocation aborts in this sandbox with a
dynamic-loader SEGV, proven pre-existing at baseline `389710b` with the
slice stashed; per-file and per-directory runs all pass. Independent
verifier PASS with three mutation-catch citations.

Artifacts: workspace-scratch design/proof/review notes (not retained).

## Prior combined slice — P9-075/P9-076/P9-077/P9-078

The four inseparable TextBuffer contract slices are committed together at
`f798e74` on 2026-08-01. The commit was created as `b4bcae9` and amended to
`f798e74` before any dependent work to remove a disallowed attribution
trailer; the tree is byte-identical and the amended head was force-pushed
with lease to the unreviewed PR #12.

Each slice kept its registration-before-RED discipline and full mutation
evidence: P9-075 named-only empty creation and truthful logical native-cell
length (19 mutations), P9-076 effect-only `void` `writeChunk` with opaque
raw-result truth (21 mutations), P9-077 supported one-scalar `setCell`,
`encodedCells` without a decoder, half-open `[start, end)` selection, and the
exact 18-declaration raw outcome matrix (36 mutations), and P9-078
fail-closed u8/u16/u32/i32 TextBuffer-family boundaries (56 mutations). The
decisive independent verifier passed, and the parent mechanical/checkpoint
matrix passed with architecture `+165`, focused `+65`, ordinary serial
`+1133 ~2`, health `+1`, primitive parity `+2`, and six-artifact
verification.

One sequencing deviation is recorded truthfully: the fresh Standards
Conformance gate that the checkpoint proof required as the only remaining
precommit gate did not run before the commit. It ran postcommit on
2026-08-01 and returned **FAIL**, registering P9-079 and P9-080 and
correcting the low-level baseline claim to the 44-entry file truth. The landed slices themselves re-verified conforming;
the failures are successor findings in the Buffer family and the line-scan
fallback, not regressions of the four landed contracts. The supported
namespaces at that checkpoint were **168 / 43 / 15**; the round-3 slice A
later shrank the low tier to 42.

Phase 9 remains ACTIVE; this is not a merge-readiness or release claim.

## Prior completed slice

P9-037 and P9-074 are in their terminal combined task-closeout state. P9-037
replaces the exact `99 / 21 / 107 = 227` filler inventory across 39 files with
independently verified semantic Dartdoc and zero changed non-Dartdoc library
lines. Its focused guard is `+1`; API/member/distribution is `+27`; semantic
preservation is `+184`; architecture is `+158`; ordinary checkpoint is
`+1119 ~2`; health is `+1`; primitive parity is `+2`; format is `307/0`; fatal
analysis and dartdoc `0/0` are clean; all six binaries verify; and the
independent 227-key implementation review PASSes.

P9-074 aligns the deep plan's dedicated inventory with GOALS and READ_HERE by
adding one exact sixth pinned/read-only OpenTUI hard rule. The existing program
guard parses only top-level bullets before the first divider, requires exactly
six, and validates the sixth block's five semantic families without borrowing
later prose or sibling rules. Authentic RED was five blocks (`+18 -1`),
preliminary GREEN is `+19`, and eight deletion/nesting/splitting/semantic
mutations failed before exact restoration. The 39 P9-037 library files and its
semantic guard retain their frozen hashes.

Artifacts: workspace-scratch design/proof/review notes (not retained).

Both ledger rows use `committed` only as the self-description of their combined
landed commit. Phase 9 remains ACTIVE; their closeout did not claim final
acceptance or PR merge readiness.

P9-038 is verifier-clean, mechanically checkpointed, and complete in commit
`88a58a2`. The public namespace landed exactly **168 high / 43 low companion
/ 15 FFI**. Ordinary applications receive a private-constructor `TuiApp`
facade; advanced hosting and custom rendering use the companion low-level
tier; raw native calls stay in the FFI tier. Shared `Color`, `TextAlign`,
`Attr`, `BorderSides`, and `BoxOptions` values are FFI-free, with private
marshalling. `TuiCanvas` is the exact eight-method non-constructible paint
vocabulary; recorder, display-list, compositor, Element, raw owner, and native
allocation machinery remain hidden or internal.

Authentic structural REDs were `+5 -5`, `+1 -6`, `+1 -3`, and `+1 -8`.
The independent correction loop closed all seven findings, including exact
FFI and custom-render consumers, effective inherited-member/alias closure,
facade priority/cancellation/disposal behavior, portable path sets, and the
assertion-disabled zero-paint probe. Final task gates are architecture `+154`,
source consumer `+4`, focused semantics `+106`, format `306/0`, fatal analysis
clean, and dartdoc `0/0`. The exact checkpoint is ordinary `+1115 ~2`, health
`+1`, primitive parity `+2`, and six-artifact verification. Diff hygiene,
protected-path checks, and final independent verification PASS.

Artifacts: workspace-scratch design/proof/review notes (not retained). No
OpenTUI source/gitlink, ABI, native artifact, manifest, generated binding,
workflow, terminal/PTY, publication, or release mutation ran.

## Earlier completed slice

P9-031 is verifier-clean and complete as of 2026-07-31. TextArea now owns one
final private State-lifetime layout-metrics holder, forwards that exact
identity through its private leaf into a final nullable `RenderTextArea`
field, and publishes the latest completed size only after successful layout.
State consumes that pair only when both axes are positive and otherwise uses
the whole `(widget.width ?? 80, widget.height)` fallback. The former per-edit
Element traversal is gone; the public `RenderTextArea` constructor and barrel
exports are unchanged.

Exact-HEAD readiness/design PASS; structural RED `+5 -1`; semantic baseline
`+13` against untouched production; corrected focused guard/controller `+19`;
design-scoped semantics/goldens `+45`; serial direct-constructor coverage
`+38`; architecture `+143`; format `301/0`; final ordinary serial checkpoint
`+1102 ~2`; health `+1`; primitive parity `+2`; fatal analysis, diff hygiene,
protected-path checks, and final independent verification PASS. The first
verifier found a fresh-per-build-holder false-pass in the source guard; the
correction now locks exactly one construction and the exact State-to-leaf
forwarding edge.

An initial default-parallel direct-constructor run encountered an unexpected
native bus error after `+35`; the decisive serial rerun passed `+38`. The
passing serial run does not erase that retained result. It was not a deliberate
or restricted crash probe, and no native, FFI, ABI, artifact, manifest,
workflow, terminal/PTY, release, publication, or public-API work was performed
or claimed.

Artifacts: workspace-scratch design/proof/review notes (not retained).

The immediately preceding P9-005D slice remains verifier-clean and landed at
`d31e112`: Dart rejects non-positive renderer dimensions before unsigned FFI
conversion, invalid resize preserves cached buffer state, and `WidthMethod`
exposes exactly `wcwidth(0)` and `unicode(1)`. P9-005N remains read-only
upstream and is not described as fixed. Its evidence was workspace-scratch
design/proof/review notes (not retained).

## Rebaseline verification evidence

- structural RED: `+31 -9`;
- corrected focused ownership/distribution selection: `+43`;
- complete architecture suite: `+139`;
- format: `301` files unchanged;
- fatal analysis: no issues;
- native manifest and all six pinned binaries: verified unchanged;
- first ordinary serial attempt: retained SIGSEGV/exit `134` at `+347` in the
  existing bundled ABI-validation path;
- one ordinary serial retry: `+1077 ~2`;
- health check: `+1`;
- Go-backed primitive parity: `+2`; and
- protected dependency diff and diff hygiene: clean;
- independent implementation verifier: PASS; and
- standards-conformance re-review: PASS.

The passing retry does not erase the retained crash result. Read-only
native-backed tests, submodule inspection, and manifest/hash verification did
run as listed. No native build or artifact replacement, submodule/gitlink
change, ABI/manifest mutation, workflow dispatch or re-enablement,
terminal/PTY operation, release, or publication ran.

## Acceptance language

The historical PR #12 target outcome was:

> Noir-local Phase 9 work is verifier-clean, locally validated, and PR #12 is
> ready to merge against the pinned OpenTUI dependency.

Do not rewrite that as a stable 1.0 release, pub.dev publication, complete
native/Unicode correctness, target-platform runtime certification, or
resolution of the documented read-only dependency limitations.

The 2026-08-02 checkpoint earned that target outcome: the repeat audit was
CLEAN, the final Standards Conformance and GOALS §7 acceptance audit was PASS
with follow-ups closed, and every then-current final check ran green from fresh
output. P9-086 was registered by the later 2026-08-03 validation review and is
now `required-local / blocks`; the claim above is historical evidence for the
merged PR #12 checkpoint, not current Phase 9 closeout language.

After P9-086 completes the full workflow and the repeat-audit stop condition is
re-earned, the current target outcome is:

> The post-merge Noir-local Phase 9 validation follow-up is verifier-clean and
> its Noir-local closeout is complete against the pinned dependency.

## Resume checklist

1. Read `tasks/READ_HERE.md`, `GOALS.md`,
   `tasks/phase-9-post-v1-reference-review.md`, `tasks/plan.md`, and this file.
2. Confirm branch, upstream relation, target/base, worktree, and pinned OpenTUI
   identity.
3. P9-086 is the current `required-local / blocks` row. Execute its separate
   full architect → TDD executor → independent verifier → mechanical and
   authorized dedicated-terminal acceptance → commit workflow. Keep it
   separate from optional P9-039 evidence and read-only-upstream P9-085.
4. Preserve the architecture invariant:

   > Widgets declare. Elements preserve identity. RenderObjects layout and
   > record paint. Compositor talks to OpenTUI. Native owns FFI, memory, ABI,
   > and binaries.

5. Update the owning tracker, run the authorized local checks, and commit/push
   only after independent verification.
