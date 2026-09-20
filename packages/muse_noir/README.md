# muse_noir

`muse_noir` is the terminal renderer adapter between Muse 1.0 and
[`package:noir`](https://pub.dev/packages/noir). It is an unpublished nested
package (`publish_to: none`) and is excluded from Noir's pub archive.

## Ownership

- Applications own `MuseIntentNavigator`, state/fact sources, actions, model
  transport, and disposal.
- `MuseNoirView` borrows the navigator and never starts generation or disposes
  it.
- Muse parses, assures, prepares, edits drafts, validates action provenance,
  and retains accepted surfaces.
- Trusted Noir builders receive only `MuseNoirRenderNode`: resolved properties,
  built children, check feedback, and narrow `edit` / `activate` operations.
- `lib/src/muse_bridge.dart` is the only approved import of
  `package:muse/src/internals.dart`; it is never exported.

The package temporarily pins Muse commit
`b7a7dff9ccd7f241465933f84a6d3537dcd017c1`, proposed by
[conceptadev/muse#77](https://github.com/conceptadev/muse/pull/77). The commit
contains ADR-0022, the external-renderer exception, and the boundary gate
required by this adapter.

## Catalog

The v2 catalog id is
`https://github.com/leoafarias/noir/catalogs/muse-noir/v2`.

| Components | Terminal presentation |
|---|---|
| `Column`, `Row`, `Panel` | integer-cell layout and grouping |
| `Text`, `Badge`, `Callout`, `Divider` | bounded semantic content |
| `Progress`, `Spinner` | progress and activity |
| `Button` | awaited validated action with pending and failure feedback |
| `Question` | single choice, multiple choice, free text, or choices plus text |

`museNoirRenderer` and `museNoirCatalog` derive from the same eleven bindings.
Compatibility is checked only for component types used by an accepted surface,
so unused catalog entries and extra renderer entries are allowed.

Reusable constraints cap Questions at four and autofocus Questions at one.
Muse 1.0 currently has no unique-property constraint, so an application cannot
express cross-component `questionId` uniqueness as local assurance. Applications
should use stable IDs and action constraints while treating uniqueness as an
upstream constraint gap.

## Use

```dart
final renderer = museNoirRenderer;
final intent = MuseIntent(
  id: 'terminal_dashboard',
  description: 'Compact terminal dashboard.',
  instructions: 'Build a compact status dashboard.',
  catalog: renderer.catalog(id: 'example/dashboard/v2'),
  constraints: museNoirConstraints,
);
final navigator = MuseIntentNavigator(
  generator: generator,
  routes: <MuseIntentRoute>[MuseIntentRoute(intent)],
);

// Navigation is an app event, never a view side effect.
await navigator.push(intent);
final view = MuseNoirView(navigator: navigator, renderer: renderer);
```

Dispose the navigator in the application owner. Put confirmation for guarded
mutations inside the declared action handler before changing app state.

## Question drafts

`Question.answer` is bindable and uses this shape:

```json
{"selectedValues": ["production"], "freeText": ""}
```

The component action reads the component-local draft:

```json
{
  "event": {
    "name": "save_answer",
    "context": {
      "questionId": "deployment",
      "answer": {"path": "/draft/questionDeployment/answer"}
    }
  }
}
```

Edits stay local until activation. Activation reads the current draft even
before the next frame and dispatches through Muse's validated renderer door.
Stale, disposed, hidden, disabled, or forged gestures fail closed.
Disabled and in-flight Questions remain mounted and focusable, but their
single-line field is read-only so visible text cannot diverge from the Muse
draft. A failed check remains editable so the user can correct the answer.

Button activation is awaited locally. A pending Button suppresses duplicate
gestures, and a failed result appears below the retained accepted surface until
the user retries. Replacing or disposing the rendered action invalidates its
late completion.

## Prompt-driven example

The example makes no request at launch. It creates the first activation only
after submission and watches an explicitly disclosed prompt fact for later
regeneration. A revision field makes same-text retry observable. Private
progress and answer values never enter model facts.

A failed regeneration keeps the previous accepted dashboard visible and shows
`Regeneration failed; showing previous output` with the same redacted failure
description used for first-generation errors. Starting a retry clears that
feedback; success leaves only the replacement output.

```sh
cd packages/muse_noir
dart run example/generated_dashboard.dart --offline
```

For Google generation:

```sh
export GOOGLE_AI_API_KEY=...
dart run example/generated_dashboard.dart
```

`MUSE_GOOGLE_AI_MODEL` optionally selects a model. The example owns the
Dartantic bridge and streams the declarations, disclosed facts, and Muse
protocol through `MuseGenerator`; the renderer library has no model dependency.

## Current limitations

- Noir has no accessibility-semantics surface corresponding to A2UI
  accessibility metadata. Visible labels remain required.
- The adapter pin remains temporary until Muse PR #77 lands on a durable ref.
- No live paid call, real terminal, PTY, native build, or release operation is
  covered by the headless package checks.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the implementation contracts and
verification boundary.
