# OpenTUI Parity and Harness Implementation Plan

> **For agentic workers:** Required workflow: read and follow
> `tasks/READ_HERE.md`. Each non-trivial roadmap task uses architect → TDD
> executor → independent verifier → mechanical/checkpoint gates → commit. Use
> the available executing-plans skill when running an accepted plan; the skill
> does not replace those review gates.

**Goal:** Extend local Dart-vs-Go validation from primitive scenes into
widget-backed scenes, remove the redundant hand-maintained widget snapshot
lane after preserving any unique semantic proof in the four supported
harnesses, and remove the temporary Go `textbuffer` shim once the checked-in
native library and header agree.

**Architecture:** Keep `tasks/plan.md` as the single live roadmap. The core
roadmap has three tasks: (1) deterministic widget parity scenes, (2) snapshot
lane consolidation and deletion instead of further manual serializer
expansion, and (3) retire the Go textbuffer shim only after the exact-three
missing native symbols are present in all six artifacts. P9-039
multi-frame/PTY/HTML validation is a fourth, optional and separately
authorized host-sensitive project. Keep all parity work repo-owned.
`external/opentui` is read-only for this roadmap; wrapper insufficiency is
recorded as an upstream limitation rather than permission to change the
submodule, ABI, or bundled artifacts.

**Tech Stack:** Dart, `package:test`, OpenTUI Dart FFI bindings, repo-owned Go snapshot tool, bash wrapper tooling

---

This file is the canonical parity/harness roadmap for the repo.

## Active continuation checkpoint

Pull request #12 remains the main integration PR. Tasks 1 and 2 are complete
repository-local roadmap slices, each landed through the normal independent
review workflow. Task 3 remains an upstream-triggered cleanup: the pinned
all-six-artifact exact-three symbol gate is red, so the test-only shim stays.
This roadmap will not produce a replacement native source or artifact tuple.
Task 4 remains optional and restricted.

This file still solely owns parity/harness work. The Phase 9 tracker documents
the native/Unicode limitations against the same read-only dependency. No
submodule change, workflow run, artifact build/replacement, ABI roll, release,
tag, or publication is an execution path in this roadmap.

## Historical validated baseline

The following was validated against the then-current tree on 2026-05-20. It is
retained as historical evidence, not current-HEAD acceptance:

- `dart analyze --fatal-infos` passes
- `dart test test/architecture/` passes
- `dart test` passes
- `GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart test test/parity/go_snapshot_wrapper_test.dart test/parity/primitives_parity_test.dart -r expanded` passes after hardening `bin/parity_compare.dart` to ignore Dart build-hook chatter before snapshot JSON
- `dart run scripts/fetch_opentui_binaries.dart --verify-only --verify-urls` passes
- current branch was clean at commit `48e32a3` before the final cleanup pass

Three core roadmap items remain:

- Tier 2 widget parity scenes for `Text`, `Row`, and `Column`
- Removal of the unused hand-maintained widget snapshot lane after any unique
  semantic assertions move to the four supported harnesses
- Removal of the temporary Go `textbuffer` shim after the packaged native library exports the exact three still-missing symbols (`textBufferConcat`, `textBufferResize`, `textBufferGetCapacity`). This remains pending as of 2026-05-20.

P9-039 terminal visual validation remains an optional, restricted project:
deterministic multi-frame cell recordings, a self-contained HTML preview, and
real PTY/raw-ANSI lifecycle evidence. It is not the next automatic slice and
does not block the three core roadmap tasks. Start it only after a fresh
review and exact authorization for the operations actually proposed.

Resume boundary (2026-07-13): the P9-042 Darwin local-oracle slice has an
interim independent PASS and is checkpoint-ready, but its ledger row is not
advanced. Linux runner evidence belongs in GitHub Actions, and the exact-final
broad/combined parity, binary, and literal repository gates remain part of
P9-042 closeout. The historical handoff named P9-039 as the next slice; P9-060
supersedes that sequencing. Task 4 below remains the unimplemented optional
design record.

Closeout update (2026-07-13): exact-final broad (`+22`), combined parity
(`+54` under the reviewed 900-second alarm), and S1/S2/S3 binary comparison are
green. The wrapper suite is now explicitly Linux-CI-owned through the
`process-spawning` tag and a dedicated parity step with a 15-minute
command bound plus the 20-minute Actions fallback. The command retains expanded
output in a regular log file for post-timeout diagnostics. A Colima Linux/ARM64
reproduction exposed one harness-only portability error: procps `kill` killed
the negative process group but returned 1 without an explicit `--` option
terminator. With that terminator, the focused case passed `+1`, the complete
wrapper passed `+52` in 07:10, and the combined parity gate passed `+54` in
07:31. The portable serial
suite and all non-default repository gates are green. A fresh literal
default-concurrency `dart test` also passed `+679 ~2` in 09:20; preserve the
earlier unrelated native instability as historical evidence,
not a current failure on this tuple. Exact implementation SHA `0ab4f13` passed
Ubuntu Actions job `86920919777` with `+54` in 08:20, and the independent final
verifier returned an unconditional PASS. P9-042 is now `committed`. P9-039
remains a separate optional visual-testing project and is not part of this
closeout.

Current ownership update (2026-07-15): the 15m/20m bounds above remain exact
P9-042 historical evidence. P9-049 superseded them with a 30-minute GNU
timeout and 35-minute Actions ceiling. P9-050 keeps that safety envelope
unchanged in CI, makes CI the sole Go-parity owner, and removes ordinary test
and parity duplication from release validation.

Deferred, not active:

- The open notes in `lib/src/painting/box_decoration.dart` for rounded hit testing, gradients, images, and shadows stay deferred until a concrete feature requires them. They are not blocking parity or the current test harness.

## File Structure

Current ownership across landed and remaining work:

- `tasks/plan.md`
  Canonical roadmap and task tracker. Update status here as each task lands.
- `bin/snapshot_scenes.dart`
  Dart-side parity scene entry point. Primitive and widget scenes coexist
  without changing the primitive scene contract.
- `test/helpers/buffer_capture.dart`
  Existing widget capture harness reused by widget parity through a relative
  import from `bin/snapshot_scenes.dart`. Do **not** add
  `lib/src/testing/widget_scene_snapshot.dart` or any fifth mount harness.
- `test/helpers/buffer_capture_test.dart`
  Focused proof that loose direct captures remain available while parity can
  opt into the tight root constraints used by a full terminal frame.
- `test/parity/widget_parity_test.dart`
  Widget-backed parity tests remain separate from primitive parity so both are
  independently debuggable.
- `tools/parity/go_snapshot/main.go`
  Go-side baseline generator with deterministic `W1`, `W2`, and `W3` outputs
  matching the current Dart widget layouts.
- `README.md`
  Consumer-safe parity scope only. Do not add checkout-only paths, commands,
  or test-guide links.
- `test/README.md`
  Test workflow documentation for the landed primitive/widget parity coverage.
- `test/helpers/snapshot_utils.dart`,
  `test/snapshots/widget_snapshot_test.dart`, and the snapshot-only surface in
  `test/helpers/golden_testing.dart`
  Deleted superseded manual representation. The accepted Task 2 design
  inventories every caller and migrates any unique semantic assertion before
  deletion; the retirement guard now keeps these paths/surfaces absent after
  the unique selection-paint proof migrated to `BufferCapture`.
- `tools/parity/go_snapshot/stubs.go`
  Temporary CGo include shim. Delete only after the packaged native library exports the missing `textBuffer*` symbols.
- `tools/parity/go_snapshot/textbuffer_stubs.c`
  Temporary symbol shim for the Go bindings. Delete only after the packaged native library exports the missing `textBuffer*` symbols.
- `scripts/run_go_snapshot.sh`
  Local wrapper for the Go parity tool. Do not change this unless shim retirement requires it.
- `test/parity/go_snapshot_wrapper_test.dart`
  Existing coverage for the wrapper. Re-run it when retiring the shim.

## Execution Rules

- Keep scene geometry deterministic. Reuse the existing `20x5` scene size unless a test proves a different size is necessary.
- Keep the JSON snapshot schema unchanged: `version`, `width`, `height`, `cells[]`, with `ch`, `fg`, and `bg`.
- Keep `external/opentui` pinned during remaining local parity work. The
  submodule, gitlink, ABI, manifest, and checked-in artifacts are read-only for
  this roadmap. The shim-retirement task is explicitly gated on a future
  already-available packaged binary, not on work performed here.
- Use TDD for each task: write the failing test first, run it, implement the minimum change, rerun the narrow test, then run the task gates and the serial checkpoint partitions at the cadence below.
- The current `scripts/run_go_snapshot.sh` lifecycle protocol is
  maintenance-only. Existing correctness and portability defects may be fixed
  through the normal reviewed loop, but no new FIFO/gate,
  election/disposition, descendant-ownership, signal, or timeout protocol may
  be added in Bash until a separate clean-sheet design compares continued Bash
  maintenance with a compiled supervisor. That review must cover
  cross-platform process ownership, signal/timeout semantics, observability,
  test migration, and rollback. This rule neither selects a supervisor nor
  creates a brittle line-count guard.

### Task 1: Add Tier 2 Widget Parity Scenes

**Files:**
- Create: `test/parity/widget_parity_test.dart`
- Modify: `bin/snapshot_scenes.dart` (relative-import `../test/helpers/buffer_capture.dart`)
- Modify: `test/helpers/buffer_capture.dart` (optional root layout constraints)
- Modify: `test/helpers/buffer_capture_test.dart` (loose/tight geometry proof)
- Modify: `tools/parity/go_snapshot/main.go` (opaque-black clear for W scenes)
- Modify: `README.md` (scope only; no checkout-only paths, commands, or links)
- Modify: `test/README.md`

- [x] **Step 1: Write the failing widget parity test**

```dart
import 'dart:io' as io;

import 'package:test/test.dart';

void main() {
  group('Widget Parity (Dart vs Go baseline)', () {
    final goCmd = io.Platform.environment['GO_SNAPSHOT_CMD'];

    test('W1,W2,W3 parity', () async {
      final result = await io.Process.run(
        'dart',
        [
          'run',
          'bin/parity_compare.dart',
          '--scenes',
          'W1,W2,W3',
          '--width',
          '20',
          '--height',
          '5',
        ],
        environment: io.Platform.environment,
      );

      final out = result.stdout.toString();
      final err = result.stderr.toString();

      expect(
        result.exitCode,
        0,
        reason: 'Comparator failed.\\nSTDOUT:\\n$out\\nSTDERR:\\n$err',
      );
      expect(out, contains('PASS: W1'));
      expect(out, contains('PASS: W2'));
      expect(out, contains('PASS: W3'));
    },
        timeout: const Timeout(Duration(minutes: 2)),
        skip: (goCmd == null || goCmd.isEmpty)
            ? 'GO_SNAPSHOT_CMD not set; skipping parity test.'
            : false);
  });
}
```

- [x] **Step 2: Run the new test and verify it fails because the scenes do not exist yet**

Run:

```bash
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart test test/parity/widget_parity_test.dart -r expanded
```

Expected: FAIL with `Unknown scene: W1` or `unknown scene: W1`.

- [x] **Step 3: Reuse BufferCapture for widget-backed scene capture and wire `W1`, `W2`, and `W3` into `bin/snapshot_scenes.dart`**

Do **not** create `lib/src/testing/**`. In `bin/snapshot_scenes.dart`, relative-import the existing harness and give W scenes **one** complete capture→JSON path. S1–S3 may keep the low-level `Buffer` / DirectBufferAccess serializer; W1–W3 must not use that path as their only serializer and must not call an undefined helper.

```dart
// bin/snapshot_scenes.dart
import 'package:noir/noir.dart' as ui;
import '../test/helpers/buffer_capture.dart';

/// Widget scenes only: BufferCapture → CapturedBuffer cells → parity JSON.
/// Schema: {version, width, height, cells[{ch, fg[4], bg[4]}]}.
/// Do not call Renderer.create, debugFlushFrame, or debugCurrentBuffer here.
Map<String, dynamic> captureWidgetSceneSnapshot(
  ui.Widget widget, {
  required int width,
  required int height,
}) {
  final capture = BufferCapture(
    width: width,
    height: height,
    layoutConstraints: ui.BoxConstraints.tight(
      width: width,
      height: height,
    ),
  );
  try {
    final captured = capture.capture(widget);
    return _snapshotFromCapturedBuffer(captured);
  } finally {
    capture.dispose();
  }
}

Map<String, dynamic> _snapshotFromCapturedBuffer(CapturedBuffer captured) {
  return {
    'version': '1',
    'width': captured.width,
    'height': captured.height,
    'cells': [
      for (var y = 0; y < captured.height; y++)
        for (var x = 0; x < captured.width; x++)
          {
            'ch': captured.getChar(x, y),
            'fg': [
              captured.getForegroundColor(x, y).r,
              captured.getForegroundColor(x, y).g,
              captured.getForegroundColor(x, y).b,
              captured.getForegroundColor(x, y).a,
            ],
            'bg': [
              captured.getBackgroundColor(x, y).r,
              captured.getBackgroundColor(x, y).g,
              captured.getBackgroundColor(x, y).b,
              captured.getBackgroundColor(x, y).a,
            ],
          },
    ],
  };
}

// S1–S3 only (low-level Buffer scenes). Not the widget path.
Map<String, dynamic> _snapshotFromBuffer(Buffer buffer) {
  final direct = buffer.getDirectAccess();
  return {
    'version': '1',
    'width': direct.width,
    'height': direct.height,
    'cells': [
      for (var y = 0; y < direct.height; y++)
        for (var x = 0; x < direct.width; x++)
          {
            'ch': direct.getChar(x, y),
            'fg': [
              direct.getForeground(x, y).r,
              direct.getForeground(x, y).g,
              direct.getForeground(x, y).b,
              direct.getForeground(x, y).a,
            ],
            'bg': [
              direct.getBackground(x, y).r,
              direct.getBackground(x, y).g,
              direct.getBackground(x, y).b,
              direct.getBackground(x, y).a,
            ],
          },
    ],
  };
}

switch (argz.scene) {
  case 'S1':
  case 'S2':
  case 'S3':
    jsonOut = _capturePrimitiveScene(argz);
  case 'W1':
    jsonOut = captureWidgetSceneSnapshot(
      const ui.Text('Hello'),
      width: argz.width,
      height: argz.height,
    );
    break;
  case 'W2':
    jsonOut = captureWidgetSceneSnapshot(
      const ui.Row(
        children: [
          ui.Text('Left'),
          ui.Text('Middle'),
          ui.Text('Right'),
        ],
      ),
      width: argz.width,
      height: argz.height,
    );
    break;
  case 'W3':
    jsonOut = captureWidgetSceneSnapshot(
      const ui.Column(
        children: [
          ui.Text('Line 1'),
          ui.Text('Line 2'),
          ui.Text('Line 3'),
        ],
      ),
      width: argz.width,
      height: argz.height,
    );
    break;
  default:
    io.stderr.writeln('Unknown scene: ${argz.scene}');
    io.exitCode = 2;
    return;
}
```

Contract for W scenes: the only serializer is `captureWidgetSceneSnapshot` →
`_snapshotFromCapturedBuffer`. Walking `CapturedBuffer` / `CapturedCell`
(`char`, `foreground`/`getForegroundColor`, `background`/`getBackgroundColor`)
is required so widget paint output, not a parallel low-level draw path, defines
the Dart baseline. The explicit tight constraints match `TuiBinding`'s
full-terminal `RenderView.terminalConstraints`; `BufferCapture` keeps its
loose default for focused direct captures. `_capturePrimitiveScene` alone owns
`OpenTuiBindings` renderer acquisition, transparent clear, primitive drawing,
direct-buffer serialization, and destruction; W dispatch must not allocate
that renderer before entering `BufferCapture`.

- [x] **Step 4: Add matching Go baseline scenes in `tools/parity/go_snapshot/main.go`**

The Go scenes should match the already-validated current Dart widget output, not a hypothetical layout:

```go
switch *scene {
case "S1":
    must(buffer.DrawText("Hello", 0, 0, opentui.White, nil, 0))
case "S2":
    drawManualBox(buffer)
case "S3":
    must(buffer.FillRect(0, 0, 12, 5, opentui.NewRGBA(0.05, 0.05, 0.08, 1)))
    must(buffer.DrawText("Inner", 1, 1, opentui.White, nil, 0))
case "W1":
    // BufferCapture clears widget scenes to opaque black; match that baseline.
    must(buffer.Clear(opentui.NewRGBA(0, 0, 0, 1)))
    must(buffer.DrawText("Hello", 0, 0, opentui.White, nil, 0))
case "W2":
    // Default Row in 20x5: centered vertically at y=2; x = 0, 4, 10.
    must(buffer.Clear(opentui.NewRGBA(0, 0, 0, 1)))
    must(buffer.DrawText("Left", 0, 2, opentui.White, nil, 0))
    must(buffer.DrawText("Middle", 4, 2, opentui.White, nil, 0))
    must(buffer.DrawText("Right", 10, 2, opentui.White, nil, 0))
case "W3":
    // Default Column in 20x5: six-cell lines centered at x=7; y = 0, 1, 2.
    must(buffer.Clear(opentui.NewRGBA(0, 0, 0, 1)))
    must(buffer.DrawText("Line 1", 7, 0, opentui.White, nil, 0))
    must(buffer.DrawText("Line 2", 7, 1, opentui.White, nil, 0))
    must(buffer.DrawText("Line 3", 7, 2, opentui.White, nil, 0))
default:
    fatalf("unknown scene: %s", *scene)
}
```

- [x] **Step 5: Run the widget parity test and direct comparator until both pass**

Run:

```bash
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart test test/parity/widget_parity_test.dart -r expanded
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart run bin/parity_compare.dart --scenes W1,W2,W3 --width 20 --height 5
```

Expected:

- The test prints `All tests passed!`
- The comparator prints `PASS: W1`, `PASS: W2`, and `PASS: W3`

- [x] **Step 6: Update the user-facing parity docs after the scenes are green**

Update docs after scenes are green:

- `test/README.md` may document checkout-only parity commands (`GO_SNAPSHOT_CMD`,
  `dart test`, comparator recipes).
- Root `README.md` may state the supported parity scope (S1–S3, W1–W3) only.
  Do **not** add a test-guide link, internal test path, `GO_SNAPSHOT_CMD`,
  `dart test`, or another checkout-only command (P9-035 package-landing
  boundary).

- [x] **Step 7: Run the task gates and commit**

Run:

```bash
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/
test -z "$(gofmt -d tools/parity/go_snapshot/main.go)"
dart analyze --fatal-infos
dart test test/architecture/
dart test --reporter=expanded test/helpers/buffer_capture_test.dart
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh \
  dart test -r expanded \
  test/parity/primitives_parity_test.dart \
  test/parity/widget_parity_test.dart \
  --concurrency=1
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh \
  dart run bin/parity_compare.dart \
  --scenes S1,S2,S3,W1,W2,W3 --width 20 --height 5
dart test --exclude-tags process-spawning --concurrency=1
dart test test/bin/health_check_test.dart --concurrency=1
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh \
  dart test -r expanded test/parity/primitives_parity_test.dart \
  --concurrency=1
git diff --check
```

Expected: all commands pass.

Commit:

```bash
git add \
  bin/snapshot_scenes.dart \
  test/helpers/buffer_capture.dart \
  test/helpers/buffer_capture_test.dart \
  test/parity/widget_parity_test.dart \
  tools/parity/go_snapshot/main.go \
  README.md \
  test/README.md \
  tasks/plan.md
git commit -m "test: add widget parity scenes for text row and column"
```

Task 1 completed and was pushed at
`817c82c19f56f52ee4da58ffca1737f45e7502e3`. Its authentic missing-W1 RED,
tight-root geometry amendment, independent implementation review, Standards
Conformance audit, focused helper/widget/combined parity gates, direct
six-scene comparison, architecture `+137`, ordinary `+1075 ~3`, health `+1`,
and final primitive parity `+2` all passed. Task 2 completed separately at
`3cc34fcaa66c49af34b9adc39c33f0886817530f`; Task 3 remains native-gated.

### Task 2: Consolidate and Remove the Manual Widget Snapshot Lane

> **Round 2 disposition:** The former serializer-expansion recipe is
> superseded, not implemented. The free-form `SnapshotSerializer` is a fifth,
> manually maintained representation beside the four supported harnesses; no
> `*.snapshot.json` golden is tracked and `expectGoldenSnapshot` has no caller.
> Adding more Text/Row/Column fields would deepen redundancy.

**Expected files after an accepted exact-HEAD design:**

- Delete or narrow: `test/helpers/snapshot_utils.dart`
- Delete or migrate: `test/snapshots/widget_snapshot_test.dart`
- Remove snapshot-only API/docs from:
  `test/helpers/golden_testing.dart`, `test/helpers/README.md`, and
  `dart_test.yaml`
- Preserve any unique behavior proof in an existing
  `WidgetTester`, `BufferCapture`, `KeyDriver`, or `createTuiTestApp` test

- [x] **Step 1: Architect the caller and assertion inventory**

Prove every production/test/doc caller, every tracked fixture, and every
assertion that is not already covered by the four supported harnesses. The
design must identify exact migrations before deleting a semantic assertion.
It must not create a replacement serializer, diagnostics tree, fifth harness,
or public testing API.

- [x] **Step 2: Record the structural/semantic RED**

Add the smallest guard or focused semantic assertion that proves the obsolete
snapshot-only surface still exists or that a unique behavior would be lost.
The RED must fail for that reason, not because an import was deleted early.

- [x] **Step 3: Migrate unique proof and delete the obsolete lane**

Move only genuinely unique behavior assertions into the appropriate existing
harness, then delete the manual serializer, opt-in snapshot tests/preset, and
unused `expectGoldenSnapshot` surface. Preserve visual buffer/style/cursor
goldens unchanged.

- [x] **Step 4: Independent review and task gates**

The verifier must confirm no semantic proof, visual golden, or supported
harness was lost and no replacement representation was introduced. Run the
focused migrated tests, helper/golden tests, architecture tests, format, fatal
analysis, and the authorized ordinary serial checkpoint before committing
this deletion separately.

Task 2 completed and was committed separately at
`3cc34fcaa66c49af34b9adc39c33f0886817530f`. The exact-head design required
two readiness corrections before execution: the unselected captured
background is opaque black after `BufferCapture` clear/compositing, and the
persistent RED belongs in the already-inventoried parity-roadmap fitness
test rather than a new guard file. The authentic compiling RED was `+3 -1`;
the migrated selection proof and focused preservation set passed `+15`, the
retirement guard passed `+4`, architecture passed `+138`, format checked 300
files with no change, fatal analysis and diff hygiene passed, and the serial
checkpoint passed ordinary `+1076 ~2`, health `+1`, and primitive parity
`+2`. Independent readiness and implementation reviews are PASS. No visual
golden changed, no replacement serializer or fifth harness was introduced,
and no restricted operation was performed.

### Task 3: Retire the Temporary Go `textbuffer` Shim When the Native Binary Is Ready

**Files:**
- Delete: `tools/parity/go_snapshot/stubs.go`
- Delete: `tools/parity/go_snapshot/textbuffer_stubs.c`
- Verify: `scripts/run_go_snapshot.sh`
- Verify: `test/parity/go_snapshot_wrapper_test.dart`
- Verify: `test/parity/primitives_parity_test.dart`
- Verify: `test/parity/widget_parity_test.dart`

This is an upstream-triggered cleanup, not a native implementation plan. Do
not start it until a separately supplied, already-reviewed dependency tuple
makes the symbol check in Step 1 succeed. With the current pinned read-only
tuple, this task intentionally remains pending and the fail-fast shim stays.

- [ ] **Step 1: Verify that every packaged native library exports the missing `textBuffer*` symbols**

Shim retirement is gated on **all six** checked-in artifacts under `native/`,
not on the host `uname` library alone. Host selection may be used for local
iteration convenience, but Step 1 fails closed unless every artifact path
below exports the exact-three list.

Run:

```bash
ROOT_DIR="$(pwd)"

# Exact-three gate (P9-043): only the symbols still missing from the packaged
# native library. Do not restore the former ten-symbol stub list.
required_symbols=(
  textBufferConcat
  textBufferResize
  textBufferGetCapacity
)

# All six packaged artifacts (macos/linux/windows × arm64/x64).
artifacts=(
  "native/macos/arm64/libopentui.dylib"
  "native/macos/x64/libopentui.dylib"
  "native/linux/arm64/libopentui.so"
  "native/linux/x64/libopentui.so"
  "native/windows/arm64/libopentui.dll"
  "native/windows/x64/libopentui.dll"
)

list_symbols() {
  local lib_path="$1"
  case "$lib_path" in
    */macos/*)
      nm -gU "$lib_path" 2>/dev/null || true
      ;;
    */linux/*)
      nm -D --defined-only "$lib_path" 2>/dev/null \
        || nm -gU "$lib_path" 2>/dev/null \
        || true
      ;;
    */windows/*)
      # PE exports: prefer llvm-nm when present; fall back to nm.
      if command -v llvm-nm >/dev/null 2>&1; then
        llvm-nm -gU "$lib_path" 2>/dev/null || true
      else
        nm -gU "$lib_path" 2>/dev/null || true
      fi
      ;;
    *)
      echo "unsupported artifact path: $lib_path" >&2
      return 1
      ;;
  esac
}

missing=0
for rel in "${artifacts[@]}"; do
  LIB_PATH="$ROOT_DIR/$rel"
  if [[ ! -f "$LIB_PATH" ]]; then
    echo "missing artifact file: $rel"
    missing=1
    continue
  fi
  symbols="$(list_symbols "$LIB_PATH")"
  for symbol in "${required_symbols[@]}"; do
    if ! printf '%s\n' "$symbols" | rg -q "(^|[[:space:]])_?${symbol}\\b"; then
      echo "missing: $rel -> $symbol"
      missing=1
    fi
  done
done
exit "$missing"
```

Expected: every symbol in the exact-three list is present on **each** of the
six artifacts. On 2026-05-20 this still fails for all three on every artifact;
stop here and leave Task 3 unchecked until the native source, header, all six
artifacts, and semantic Go proof agree. A single-host `uname` pass is not
sufficient. No local no-op or Phase 9 withdrawn fixture may satisfy the gate.

- [ ] **Step 2: Remove the shim files once Step 1 is green**

Delete these files:

```text
tools/parity/go_snapshot/stubs.go
tools/parity/go_snapshot/textbuffer_stubs.c
```

There should be no replacement code. The point of this task is to prove the checked-in binary now satisfies the Go bindings directly.

- [ ] **Step 3: Run primitive/widget parity without the shim**

Run:

```bash
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart test test/parity/primitives_parity_test.dart test/parity/widget_parity_test.dart -r expanded
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart run bin/parity_compare.dart --scenes S1,S2,S3,W1,W2,W3 --width 20 --height 5
```

Expected:

- primitive parity passes
- widget parity passes
- direct comparator prints `PASS` for all six scenes

The tagged `go_snapshot_wrapper_test.dart` suite deliberately exercises
signals, process groups, forced termination, and cleanup races. It is an
authorization-gated process-lifecycle supplement, not a shim-retirement or
ordinary checkpoint gate. Run it only when the exact task changes that
ownership and the user authorizes those operations.

- [ ] **Step 4: Commit shim retirement separately**

```bash
git add tools/parity/go_snapshot/stubs.go tools/parity/go_snapshot/textbuffer_stubs.c
git commit -m "chore: remove temporary go textbuffer parity stubs"
```

### Task 4: Optional/restricted terminal validation (P9-039)

This accepted design remains unimplemented and does not block core roadmap or
Phase 9 closeout. Do not start it without exact authorization for the proposed
host-sensitive operations. A pure-Dart recording/HTML subset may be
reconsidered only through a fresh design; it must not claim PTY, ConPTY, raw
terminal, signal, or remote-platform evidence.

P9-039 owns optional terminal-lifecycle evidence and harnesses, not runtime
implementation. In particular, it characterizes P9-085 and does not fix it;
the pinned-native source/artifact correction remains outside this roadmap.

The semantic evidence remains layered:

1. Existing buffer, style, cursor, and `createTuiTestApp` tests remain the fast
   source of truth for widgets, parsing, layout, paint, and point-in-time state.
2. A test-only recording codec captures named frames (initial, focused, typed,
   scrolled, selected, resized, submitted) from complete cell/style/cursor
   state. A pure-Dart CLI renders those recordings as one self-contained HTML
   file with no network dependency.
3. A separate OS PTY harness owns real stdin/stdout, resize, raw ANSI, process
   reaping, terminal-mode restoration, and signal/failure cleanup. HTML is a
   review surface, not an ANSI parser or semantic replacement for goldens.

- [ ] **Step 1: Freeze the recording, PTY, and platform contracts**
  - Define frame schema, colors/attributes, cursor/blink state,
    wide/continuation cells, raw-ANSI boundaries, resize readiness, cleanup,
    Unix PTY ownership, and the Windows ConPTY strategy.
  - Obtain an independent design PASS before code or golden changes.

- [ ] **Step 2: Extract one round-trip golden/recording codec**
  - Preserve every existing `.buffer.txt`, `.styles.txt`, and `.cursor.txt`
    byte-for-byte.
  - Add strict decode/encode and malformed-input tests.

- [ ] **Step 3: Build the self-contained HTML cell renderer**
  - Escape payload text; preserve dimensions, spaces, foreground/background,
    attributes, cursor style/visibility, and deterministic named-frame order.
  - Verify deterministic HTML fragments and inspect a generated recording in
    the browser with screenshots/contact sheets.

- [ ] **Step 4: Record multi-frame interaction scenarios**
  - Extend only the existing test helpers around `createTuiTestApp`.
  - Cover focus, typing, arrows, paste, mouse, resize, submit, and multiple
    cursor states with deterministic actions and idempotent teardown.

- [ ] **Step 5: Add Unix PTY and raw-ANSI tests**
  - Seed main-screen sentinel rows, place the terminal at a known launch
    cursor, then launch a real Noir example at fixed dimensions, wait on
    observable output, send byte-exact input/resize/signal events, and retain
    raw stdout bytes.
  - After exit, compare the sentinel content and cursor position as well as
    terminal modes and absence of leftover processes. `stty` equality alone is
    insufficient: it does not prove main-screen content or cursor restoration.
  - Run locally on macOS; run the identical source on Linux in GitHub Actions.

- [ ] **Step 6: Add the Windows runtime path**
  - Validate the reviewed ConPTY/equivalent helper in GitHub Actions, including
    input, resize, output, cursor/mode cleanup, exit status, and child reaping.
  - Linux and Windows runtime evidence is intentionally remote CI evidence; it
    is not a prerequisite for making the local implementation checkpoint
    commit, but it is required before merge/final P9-039 acceptance.

- [ ] **Step 7: Verify and close P9-039**
  - Require the focused codec/recording/PTY suites, format, fatal analysis,
    architecture tests, the serial checkpoint partitions, independent
    implementation PASS, generated HTML/contact-sheet inspection, and retained
    Linux/Windows CI run URLs/artifacts before advancing the tracker to
    complete under a separately authorized P9-039 execution.
  - Report P9-085 as characterized, not corrected, unless a separately
    authorized dependency strategy has landed the native fix and rebuilt
    artifact tuple.

Stop any Unicode-fidelity claim while packed native graphemes still capture as
`*`; HTML proves deterministic cell geometry/styles, not terminal-font glyph
fidelity. Do not introduce xterm.js, a browser ANSI parser, or a permanent
`expect` dependency without a separately reviewed design decision.

## Ongoing Validation Commands

After the independent verifier is clean, run these before each task commit:

```bash
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/
dart analyze --fatal-infos
dart test test/architecture/
<the exact design-scoped semantic test commands named by the accepted design>
```

Before one or more verifier-clean task commits are pushed, merged, or handed
off together, run these once against that exact checkpoint HEAD:

```bash
dart test --exclude-tags process-spawning --concurrency=1
dart test test/bin/health_check_test.dart --concurrency=1
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart test -r expanded test/parity/primitives_parity_test.dart --concurrency=1
```

The tagged process-lifecycle wrapper suite, PTY/ConPTY or real-terminal work,
publication/release operations, and workflow execution require exact
task-specific authorization; they are not ordinary roadmap gates. OpenTUI
source, gitlink, ABI, manifest, and bundled-artifact mutations are outside this
roadmap and require a separate dependency-strategy decision, not ordinary task
authorization.

Use this command while iterating on parity scenes:

```bash
GO_SNAPSHOT_CMD=./scripts/run_go_snapshot.sh dart run bin/parity_compare.dart --scenes S1,S2,S3,W1,W2,W3 --width 20 --height 5
```

## Completion Conditions

Local parity-roadmap completion requires all three statements below:

- Widget parity exists and passes locally for `W1`, `W2`, and `W3`
- The manual widget snapshot lane is removed after any unique semantic proof is
  preserved in the four supported harnesses; no replacement serializer or
  fifth harness is introduced
- The temporary Go `textbuffer` shim is either removed because the exact-three native symbols are exported, or explicitly left pending here because Step 1 still fails

Tasks 1 and 2 are complete. Task 3 is explicitly left pending because the
read-only pinned artifacts fail Step 1, so the local parity roadmap is complete
for this dependency tuple without claiming shim retirement.

Task 4 / P9-039 remains visibly open and optional. Its recording, HTML,
PTY/ConPTY, and platform evidence does not block local parity-roadmap
completion and is not treated as waived or implemented. P9-041 is
administratively closed while this file remains the sole parity-roadmap owner:
Tasks 1 and 2 are complete, and Task 3 remains explicitly pending on the
all-six-artifact native symbol gate. That pending cleanup cannot be turned
into a local fork/build/artifact-roll project.
