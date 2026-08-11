# Phase 9 continuation handoff — 2026-07-23

> **Superseded for execution by P9-060.** This file is retained as dated
> checkpoint history; current scope, dispositions, and gates live in the
> authoritative documents linked below.
>
> **Read-only dependency update (2026-07-29):** do not execute any fork,
> native-source, ABI, artifact, manifest, or workflow plan recorded below.
> OpenTUI is a pinned read-only submodule for this program. Current execution
> authority lives in `tasks/SESSION.md` and the active Phase 9 checklist.

This is a dated execution aid, not a second source of truth. The next agent
must treat `tasks/READ_HERE.md`, `GOALS.md`,
`tasks/phase-9-post-v1-reference-review.md`, the active phase checklist, and
the current Git HEAD as authoritative. If this snapshot and those sources
disagree, follow the authoritative sources and correct this snapshot.

## Starting point

- Workspace: `/Users/leofarias/conductor/workspaces/cli_ui/amarillo`
- Branch: `leoafarias/reference-review-goal`
- Baseline before this handoff: `758406a`
- P9-024 resumable implementation checkpoint: `c738417`
- Do not rename the branch.
- Preserve unrelated work and do not revive withdrawn or superseded tasks.
- Before changing any non-trivial item, perform the required exact-HEAD
  compatibility drift audit and Phase Readiness Review.
- Then use architect → implementation → independent review → mechanical
  checks → commit. Commit and push each coherent independently verified item.

## Validation authority

Ordinary semantic, unit, widget, golden, architecture, package-consumer,
hermetic integration, and ordinary subprocess tests are allowed and expected.
The serial checkpoint partitions are:

```bash
dart test --exclude-tags process-spawning --concurrency=1
dart test test/bin/health_check_test.dart --concurrency=1
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh \
  dart test -r expanded test/parity/primitives_parity_test.dart --concurrency=1
```

Also run:

```bash
dart format --set-exit-if-changed lib/ test/ example/ bin/ scripts/
dart analyze --fatal-infos
git diff --check
```

Do not run without exact user authorization:

- leak, sanitizer, or resource-exhaustion probes;
- deliberate crash, abort, fatal-signal, or process-kill tests;
- real PTY/ConPTY/raw-mode/iTerm/visual-terminal automation;
- native rebuild, ABI fault injection, artifact, publish, or release work; or
- GitHub Actions dispatch, rerun, or re-enablement.

GitHub Actions remains disabled. Existing ledger wording that says all tests
are policy-blocked is stale when the required proof fits the allowed ordinary
test categories; correct it during the task's exact-HEAD readiness pass.

## First task: finish P9-024

`c738417` is safe to resume from but is not P9-024 completion. Keep its ledger
status `designed` until every remaining gate passes.

Read:

- Task artifacts were workspace-scratch notes (not retained).

The checkpoint already centralizes focused active-selection repair in
`TextEditingOwnerStateMixin`, removes widget/connection duplicate ownership,
fails direct invalid connection state before mutation, and has focused `+35`,
affected regression `+39`, architecture `+83`, clean format/analyze/diff, and
assertions-disabled evidence.

Still required:

1. Add and inspect focused buffer/style/cursor goldens for owned and external
   TextInput and multiline TextArea at document end, focused programmatic
   replacement, unfocused hidden cursor, and blur/refocus transitions.
2. Complete owned/external lifecycle coverage: both focus states, all
   owned/external controller swap directions, usable versus invalid
   replacement selection, focus-node replacement, disposal/survival,
   detachment, repeated swaps, and stable listener counts.
3. Complete callback cardinality proof for raw controller notification,
   mixin hook, rebuild, TextArea viewport hook, `onChanged`, and `onSubmit`
   across edit, move, focus gain/loss, paste, repair, programmatic update,
   parent update, nested invalidation, throwing hook, detach, and dispose.
4. Cover the public connection's edit/delete/move families, directional
   selection, ignored read-only/limit paths, and pre-mutation failure.
5. Add a direct regression for repeated teardown/idempotent detach.
6. Write truthful GREEN proof, obtain independent completion review, run
   focused/regression/architecture/mechanical gates and all three serial
   checkpoint partitions, then change P9-024 to `committed` with evidence.

P9-020 owns later wide/combining cursor-coordinate proof; do not pull that
native-dependent work into P9-024.

## Dependency-ready work after P9-024

Do these as separate tasks and commits, each after a fresh exact-HEAD audit:

1. **P9-025 — positive `maxLines` validation (P1).** Rebase the accepted
   design, correct stale policy wording, implement positive-or-null validation
   before storage/mutation, and prove invalid const/assertions-disabled and
   existing size/display-list/ellipsis behavior.
2. **P9-028 — generation-ordered patch-manager loads (P1).** Rebase the
   accepted design, implement last-started-wins generation plus repository
   identity, prove both stale success/failure completion orders and
   replacement/disposal, and use captured cursor sidecars rather than terminal
   automation.
3. **P9-034 — maintained Element depth buckets (P2).** Its P9-006 and P9-014
   predecessors are committed. Repeat the exact-descendant owner/reparent
   audit and readiness review before deterministic 10/100/1000 RED/GREEN.
4. **P9-041 — parity-roadmap correction (P2, plan-only).** Rebase its
   accepted design and use allowed architecture/static checks. Keep
   `tasks/plan.md` the sole parity roadmap; do not execute restricted P9-039
   terminal work.

P9-025 and P9-028 are independent after their readiness reviews. Do not combine
them in one implementation or commit.

## Blocked dependency chains

Record exact evidence and continue independent work rather than attempting
restricted operations.

- **Native root:** P9-005 needs authority for a reachable native submodule
  commit, six coherent artifacts/hashes, and actual Linux/Windows proof.
- **Native/render/Unicode chain:** P9-005 → P9-018 → combined P9-020A/P9-021N
  ABI-4 roll → P9-020B → P9-021 → P9-022.
- **Editor descendants:** P9-023 needs P9-020 and completed P9-024; P9-031
  then needs rebased P9-023.
- **Patch-manager descendants:** P9-029 is landed. P9-027A raw Git
  identity/transport is the next local predecessor for P9-026; P9-027B exact
  terminal-cell presentation still needs P9-020.
- **Rendering simplification/performance:** P9-030 needs P9-018; P9-032 needs
  the native/Unicode chain plus P9-030/P9-031; P9-033 needs P9-032 and the
  native text stack.
- **Distribution/API/docs:** P9-035 needs P9-005 package content; P9-038 needs
  P9-005/P9-020 and affected semantic descendants; P9-036 then needs P9-035,
  final semantic descendants, and P9-038; P9-037 follows the final public
  surface.
- **Terminal and final evidence:** P9-039 is explicitly restricted and also
  waits for its listed semantic/native predecessors. P9-040 is final-last and
  needs operator authorization, enabled GitHub Actions/runners, and a final
  publish candidate.

P9-050 is historical `verifier-clean` process evidence with a later local
reliability correction. Do not revive or relabel it merely to create work;
only reconcile it if the authoritative checklist explicitly makes that a
current closeout requirement.

## Completion rule

Phase 9 is not complete while any active ledger row remains uncommitted or an
external dependency prevents the goal from being true. Finish every
independent allowed item first. For a genuine external blocker, preserve exact
commands/results/authority needed, keep the row honest, and do not substitute
a waiver or a restricted test with an unsupported completion claim.
