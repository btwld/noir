# Changelog

## Unreleased

- Replace the pre-1.0 integration with Muse intents, catalogs, navigators,
  generators, facts, states, constraints, drafts, and validated dispatch.
- Pin the Muse PR #77 adapter-policy commit containing ADR-0022 and isolate
  the only internal import in `muse_bridge.dart`.
- Add the v2 eleven-component catalog and resolved-node renderer contract.
- Replace session-hosting UI with a borrowed navigator view and retained
  activation behavior.
- Add deterministic Noir-to-Muse listenable adapters.
- Move Question answers to component-local Muse drafts while retaining all
  four terminal interaction forms and duplicate-submit suppression.
- Port the prompt dashboard to app-owned state/facts and a direct Dartantic
  `MuseGenerator`, preserving credential-free scripted mode.
- Add real assurance, renderer, navigation, draft, privacy, constraint, and
  80x24 headless tests plus root adapter-boundary checks.
- Keep disabled and in-flight Question fields read-only without losing their
  mounted controller, focus, selection, or failed-check editability.
- Await Button actions, suppress pending duplicates, show local failures, and
  invalidate late completions when the rendered action changes.
- Keep accepted output visible after failed regeneration with explicit,
  redacted feedback that clears on retry and recovery.
- Restore navigation, stale-callback, confirmation, panel/callout, clipping,
  and parsed 80x24 interaction regressions from the pre-replacement baseline.

## 0.0.1-dev.1

- Initial experimental pre-1.0 integration (superseded).
