# Noir test guide

The suite is organized by behavior:

- `test/animation`: ticker and controller behavior.
- `test/app`: binding, application, and terminal-session lifecycle.
- `test/core`: buffers, renderer, input parser, and native resource helpers.
- `test/framework`: Element, State, key, dependency, and diagnostics semantics.
- `test/rendering`: render-object layout and painting.
- `test/widgets`: widget behavior, focus, editing, and interaction.
- `test/example`: runnable-example regressions.
- `test/golden` and `test/goldens`: visual capture tests and fixtures.
- `test/parity`: Dart-versus-Go parity.
- `test/architecture`: executable ownership and distribution boundaries.

## Normal validation

    dart analyze --fatal-infos
    dart test test/architecture/ --concurrency=1
    dart test --exclude-tags restricted-process-lifecycle --concurrency=1

`safe-process-spawning` tests are ordinary isolated-process checks and run in
the normal suite. `test/parity/go_snapshot_wrapper_test.dart` alone uses
`restricted-process-lifecycle` because it deliberately tests signal and
termination behavior. Run it only after exact authorization, by exact path,
with `--run-skipped`. Never select the whole parity directory as a shortcut.

## Harness ownership

| Harness | Use |
| --- | --- |
| `WidgetTester.pumpWidget` | Layout and widget lifecycle |
| `BufferCapture.capture` | A single rendered frame |
| `KeyDriver` | Synthetic parsed input |
| `createTuiTestApp` | Binding/parser integration |

Use `BufferMatchers` for cells and captured cursor state.

## Goldens

Normal runs compare checked-in captures:

    dart test test/golden/
    dart test test/example/layout_basics_golden_test.dart

Only intentional visual changes regenerate them:

    UPDATE_GOLDENS=1 dart test test/golden/

Inspect `test/failures/` before accepting a changed capture. Visual goldens use
character buffers plus style and cursor sidecars unless the assertion is
intentionally text-only.

## Safe parity

Initialize the pinned reference, then select only the primitive/widget tests:

    git submodule update --init external/opentui
    GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart test --reporter=expanded test/parity/primitives_parity_test.dart test/parity/widget_parity_test.dart --concurrency=1

These compare fixed-size Dart and Go scenes. They do not run the restricted
wrapper lifecycle test.
