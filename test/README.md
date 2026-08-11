# Noir Test Guide

The test suite mixes framework-level unit coverage, render/golden verification, example regression coverage, and local Go parity checks.

## Primary Commands

Run the standard validation set:

```bash
dart analyze
dart test test/architecture/
dart test test/layout_widgets_test.dart --reporter=expanded
dart test --exclude-tags process-spawning --concurrency=1
```

Focused unit, widget, golden, and architecture tests are ordinary local
validation. The ordinary checkpoint excludes `process-spawning` so that
subprocess checks can be selected deliberately and the restricted parity
wrapper is never selected by accident.

## Test Layout

The suite is organized by behavior instead of a generic `unit/integration` split:

- `test/animation/`: ticker and animation controller coverage
- `test/app/`: `TuiBinding`, `runTuiApp`, and `TuiApp` facade behavior
- `test/core/`: low-level renderer/cursor/buffer helpers
- `test/framework/`: element tree, lifecycle, keys, diagnostics, and updates
- `test/rendering/`: render-object correctness checks
- `test/widgets/`: widget behavior and input/focus tests
- `test/example/`: example-specific regression coverage
- `test/golden/`: reusable visual regression suites
- `test/parity/`: Dart-vs-Go parity tooling
- `test/helpers/`: capture and golden infrastructure

## Goldens

Golden tests compare captured output against files in `test/goldens/`.

Normal runs compare only:

```bash
dart test test/golden
dart test test/example/layout_basics_golden_test.dart
```

Regenerate goldens only for intentional visual changes:

```bash
UPDATE_GOLDENS=1 dart test test/golden
UPDATE_GOLDENS=1 dart test test/example/layout_basics_golden_test.dart
```

When a golden comparison fails, helper code writes artifacts to `test/failures/`. That directory is ignored by git and should be treated as disposable local output.

## Parity

Local parity is opt-in and requires the repo-owned Go snapshot wrapper. If
your checkout did not fetch submodules, initialize the pinned OpenTUI
reference first:

```bash
git submodule update --init external/opentui
```

Then run:

```bash
./scripts/run_go_snapshot.sh --scene S1 --width 20 --height 5
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart test -r expanded test/parity/primitives_parity_test.dart --concurrency=1
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart test -r expanded test/parity/widget_parity_test.dart --concurrency=1
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart test -r expanded test/parity/primitives_parity_test.dart test/parity/widget_parity_test.dart --concurrency=1
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart run \
  bin/parity_compare.dart \
  --scenes S1,S2,S3,W1,W2,W3 --width 20 --height 5
```

S1–S3 exercise low-level buffer primitives. W1–W3 exercise painted
`Text`, default `Row`, and default `Column` widget output through
`BufferCapture`. The comparator checks every character, foreground RGBA, and
background RGBA cell in the fixed `20x5` scenes.

The wrapper validates signal and process-termination behavior.
`go_snapshot_wrapper_test.dart` is tagged `process-spawning`, excluded from
routine validation, and must only run with exact task-specific authorization.
Do not use the whole `test/parity` directory as a routine selector.

## Helpers

Important helper utilities:

- `test/helpers/buffer_capture.dart`: root render-pipeline capture
- `test/helpers/golden_testing.dart`: golden comparison and failure artifact handling
- `test/helpers/widget_tester.dart`: widget-oriented test support

## Maintenance Notes

- Keep `test/failures/` untracked.
- Update goldens only through `UPDATE_GOLDENS=1`.
- Prefer targeted regression tests for framework fixes before expanding golden
  coverage.
