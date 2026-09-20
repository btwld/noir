# muse_noir architecture

Status: **implemented, locally verified, and independently reviewed**.

## Dependency boundary

Muse is pinned to `b7a7dff9ccd7f241465933f84a6d3537dcd017c1`, the
adapter-policy commit proposed by
[conceptadev/muse#77](https://github.com/conceptadev/muse/pull/77). It contains
ADR-0022 and the upstream boundary tests that authorize Noir's renderer
adapter. Until that change lands on a durable ref, do not replace the pin with
Muse `main`.

`lib/src/muse_bridge.dart` is the only file that imports
`package:muse/src/internals.dart`, and the package does not export that bridge.
A standalone consumer has resolved and imported the pinned Git subpackage.
The renderer has no Flutter or model dependency. Dartantic is a development
dependency used only by the example.

## Ownership and rendering

Applications own `MuseIntentNavigator`, state and fact sources, actions, model
transport, and disposal. `MuseNoirView` borrows the navigator. Mounting the
view does not start generation, and unmounting it does not dispose the
navigator.

`MuseNoirComponentBinding` pairs a `MuseComponent` declaration with a trusted
builder. `MuseNoirRenderer` derives its catalog from those declarations.
Builders receive `MuseNoirRenderNode`, which exposes resolved properties,
built children, check feedback, and narrow `edit` and `activate` operations.

Before invoking a builder, the private surface walker checks every used
component identity. It omits invisible subtrees, scopes component keys to the
shown activation, reads draft-aware properties and check feedback, reads
action parameters at gesture time, and dispatches with the rendered surface's
provenance. Stale, hidden, disabled, disposed, or forged gestures fail closed.
Per-component action leases preserve callback identity for an unchanged
rendered action and invalidate callbacks when the action is replaced, hidden,
or disposed.

`MuseNoirView` retains a live accepted surface while a replacement activation
generates. It also retains the surface after failed regeneration of the same
activation. A disposed or never-accepted activation clears the view. Replacing
the navigator resets retained state, and replacing the renderer reruns
compatibility checks.

The dashboard distinguishes a retained regeneration failure from an initial
failure. It keeps the accepted surface mounted, presents a redacted failure
description beside it, hides obsolete feedback while a retry is generating,
and clears it after success.

`MuseValueListenable` and `MuseNotifierListenable` remove forwarded listeners
without disposing the borrowed Noir sources.

## Question controls

`Question` supports four forms:

| Form | Interaction | Submission |
|---|---|---|
| Single choice | bounded radio-style `Select` | immediate |
| Multiple choice | bounded checkbox-style `Select` | explicit button |
| Free text | bounded `TextInput` | Enter or button |
| Choices plus text | choice with optional Other text | mode-specific |

The literal `questionId` is stable, `answer` is bindable, and action parameters
read `/draft/<componentId>/answer`. The canonical answer contains ordered
`selectedValues` and trimmed `freeText`. Editing a draft does not mutate host
state or invoke a model.

Noir's `TextEditingController` follows host and draft updates without
rewriting unchanged text. Standard Noir controls own their focus nodes.
In-flight submission suppresses duplicates. Check and rejected-action feedback
remain visible without replacing the accepted surface. A failed check blocks
submission but leaves draft editing enabled.

Inactive and in-flight free-text controls use Noir's reusable
`TextInput.readOnly` policy. Typing, paste, and deletion are blocked while
focus, caret movement, controller identity, programmatic updates, and general
TextInput submission semantics remain intact. Question itself separately
disables submission while disabled, busy, misconfigured, or actionless.

Default Button controls await validated activation, suppress duplicate pending
gestures, clear local feedback on retry, and show a returned failure below the
button. Application confirmation remains inside the declared Muse handler;
the adapter does not add a second policy or dispatch layer.

Muse 1.0 has no unique-component-property constraint, so the adapter cannot
locally assure cross-component `questionId` uniqueness. Applications must use
stable IDs and action constraints.

## Generator example

The example owns its navigator, generator, private state, and explicitly
disclosed submitted-prompt fact. Mounting the UI makes no request. The first
submission pushes the intent; later fact notifications regenerate it. A
monotonically increasing revision permits same-text retries.

Live mode wraps Dartantic's Google agent in `MuseGenerator` and streams output
text through Muse assurance. Only declarations, disclosed facts, and the Muse
protocol enter the model prompt. Private answer, progress, count, and status
values stay out of model facts. Credentials come from `GOOGLE_AI_API_KEY`, are
redacted from displayed failures, and never enter provider labels sent to
Muse.

Offline mode uses `MuseGenerator.scripted` with the same assurance path. Its
deterministic composition has 15 nodes, all eleven catalog types, four
Question forms, private-state bindings, and component-local drafts.

## Verification boundary

The package tests cover catalog compatibility, visibility, replacement and
disposal of stale gestures, immediate draft reads, forged parameters,
navigator replacement, push/pop draft retention, controller selection,
same-turn busy-input rejection, retained surfaces and regeneration feedback,
listener cleanup, Button pending, same-activation replacement, and failure
behavior, application confirmation, all eleven components, all four Question
forms, panel/callout presentation, request privacy, same-text retry, the
15-node gallery, and parsed keyboard plus clipped scrolling at 80x24.

The correction slice passes nested format and fatal-info analysis, all 50
nested tests, root format and fatal-info analysis, all 232 architecture tests,
all 2,316 serial root tests, and `git diff --check` on 2026-09-20.

The pre-refresh implementation passed nested format and fatal-info analysis,
all 37 nested tests, root format and fatal-info analysis, all 194 architecture
tests, all 2,202 root tests, all six binary verifications, a 15 MB publish
dry-run with zero warnings, and `git diff --check` on 2026-09-18. PR #77 was
then rebased without changing the `packages/muse` or `packages/muse_flutter`
trees. After the pin refresh on 2026-09-20, nested format and fatal-info
analysis, all 37 nested tests, all 194 root architecture tests, and
`git diff --check` passed. The recoverable pre-cutover snapshot remains at
`refs/conductor/muse-noir-pre-1.0-baseline-20260918`
(`55d9e327adc21de04203271317e95175dea0cefb`).

These checks do not cover a paid model call, real terminal or PTY behavior,
native builds, publication, or release operations.
