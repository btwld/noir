# Start here

This is the entry point for work in Noir.

Read, in order:

1. [`../AGENTS.md`](../AGENTS.md) for architecture, ownership, and safety.
2. [`../GOALS.md`](../GOALS.md) for the durable quality and release gates.
3. [`release-readiness.md`](release-readiness.md) for current work and residual
   risk.
4. [`1.0-release-plan.md`](1.0-release-plan.md) for the ordered private-history
   and clean-`main` handoff.
5. The affected source, tests, and pinned OpenTUI reference implementation.

## Workflow

For non-trivial behavior or API work:

1. Audit the current behavior and compatibility drift.
2. Have an architect specify observable behavior, ownership, failure
   semantics, RED tests, and affected files.
3. Add and run the RED tests.
4. Implement the minimum coherent change.
5. Have an independent verifier inspect behavior, tests, and the full diff.
6. Run focused tests, architecture tests, and the ordinary suite.
7. Update release readiness, then commit only the verified slice.

Documentation-only corrections may use a lightweight edit → focused checks →
commit path. They still require link checks and a stale-reference scan.

## Standard verification

    dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ scripts/
    dart analyze --fatal-infos
    dart test test/architecture/ --concurrency=1
    dart test --concurrency=1
    dart run scripts/fetch_opentui_binaries.dart --verify-only
    dart pub publish --dry-run
    git diff --check

Safe subprocess tests and automatic push/pull-request CI are ordinary checks.
Do not run real terminal/PTY tests, native builds, artifact refreshes, manual
workflow dispatches or reruns, tags, publication, or releases without exact
authorization.

## Done means

- behavior and ownership match the implementation contract;
- the regression test would fail if the bug returned;
- no stale API, file, branch, PR, tag, or release claim remains;
- no generated or native artifact changed accidentally;
- the release-readiness record is honest about unresolved risk;
- the final diff is independently reviewed and mechanically clean.
