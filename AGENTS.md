# Agent Guidelines for OpenTUI Dart Framework

## North Star

**Start here:** [`tasks/READ_HERE.md`](tasks/READ_HERE.md). It is the single entry point for any agent or human joining the reference-implementation refactor — it tells you what to read, in what order, the hard rules, the sub-agent workflow, the fitness functions, the verification commands, and where each phase's checklist lives.

If you only have time for one paragraph: every phase starts with the compatibility drift audit and Phase Readiness Reviewer; every non-trivial phase task is architect → executor → verifier → mechanical-checks → commit. Tiny documentation/comment fixes can use the lightweight edit → checks → commit path described in `tasks/READ_HERE.md`, but they still cannot introduce stale references. No backwards-compat shims. Fitness functions enforce; review verifies. The full picture is in `tasks/READ_HERE.md`.

The supporting documents (linked from `READ_HERE.md`):

- **`GOALS.md`** — the durable standard (quality bar, process, drift guardrails, audit).
- **`tasks/reference-implementation-plan.md`** — the deep review + phased plan (the "why").
- **`tasks/phase-*.md`** — per-phase checklists with task lists agents check off as they go.

The core invariant from `GOALS.md`:

> Widgets declare. Elements preserve identity. RenderObjects layout and record paint. Compositor talks to OpenTUI. Native layer owns FFI, memory, ABI, and binaries.

If a change blurs any line above, it is not reference-quality.

`tasks/plan.md` is a separate, narrower roadmap (parity scenes / harness) running in parallel — not part of the reference-implementation refactor.

## Project Purpose

This project creates a **Flutter-like reactive UI framework for terminal applications** using OpenTUI as the rendering backend. The goal is to bring Flutter's declarative widget patterns, state management, and layout system to terminal interfaces while leveraging all available OpenTUI primitives through Dart FFI.

**Core Philosophy**: Build a complete terminal UI framework that feels familiar to Flutter developers but is optimized for terminal constraints and capabilities. As we are planning never worry about backwards support, or deprecations, while we are still working on the MVP.

## Framework Overview

We are creating a pseudo-Flutter framework that includes:
- **Widget System**: StatelessWidget, StatefulWidget with familiar APIs
- **Layout Engine**: Row, Column, Container, Flexible, Expanded widgets with sophisticated alignment
- **State Management**: setState() patterns, BuildContext, element lifecycle
- **Styling System**: TextStyle, BoxDecoration, and the `Color` palette adapted for terminal output
- **OpenTUI Integration**: Full utilization of OpenTUI primitives through Dart FFI bindings

## OpenTUI Reference Implementations

When validating behavior or understanding OpenTUI capabilities, **always consult these local reference implementations**:

### Dart Implementation (This Package)
```
./lib/
./test/
./example/
./bin/
```
- Current Flutter-like framework implementation
- Widget system, layout engine, and FFI bindings
- Examples and test cases demonstrating Dart-specific patterns

**Supported OpenTUI integration tiers:**

*High-level application/widget barrel (`lib/noir.dart`):*
- Ordinary application and widget authoring, including the owning `TuiApp`
  facade, semantic input/style values, widgets, and the supported paint
  vocabulary.

*Low-level companion barrel (`lib/noir_low_level.dart`):*
- Advanced hosting, renderer/buffer access, and supported custom
  render-widget/render-object protocols. Concrete Element implementations and
  backend recording/compositing machinery remain framework-owned.

*Raw FFI barrel (`lib/noir_ffi.dart`):*
- ABI-unstable guarded bindings, ABI constants/errors, shared semantic values,
  and opaque native handles. Generated bindings and native loading remain
  internal.

### Go Implementation
```
/external/opentui/packages/go/
```
- Primary reference for OpenTUI behavior and patterns
- Check how layout, rendering, and input handling work
- Use as source of truth for expected OpenTUI primitive behavior

### React Implementation
```
/external/opentui/packages/react/
```
- Reference for component-based UI patterns
- Understanding how declarative UI maps to OpenTUI primitives
- Examples of state management and component lifecycle

### Core Library
```
/external/opentui/packages/core/
```
- Low-level OpenTUI primitives and APIs
- Understanding buffer management, rendering, and event handling

**Validation Rule**: When implementing or debugging any OpenTUI behavior, verify it against these reference implementations to ensure consistency with OpenTUI's intended design.

### Read-only OpenTUI dependency

`external/opentui` is a read-only Git submodule pinned by Noir.
The configured fork URL records provenance; it does not authorize changes to that repository.
For the active Phase 9 program and pull request #12, initialize and inspect the
pinned source as a reference and verify the checked-in artifacts, but do not
edit or advance the submodule, create or push OpenTUI refs, run OpenTUI
workflows, rebuild or replace bundled libraries, or roll the native ABI or
manifest. Findings that require those changes are documented
`read-only-upstream` limitations, not Noir-local merge blockers. A future
change to this boundary requires a separate explicit dependency-strategy
decision.

P9-085 is one such pinned-native lifecycle limitation. On the observed
macOS/iTerm path, native capability probes move the main-screen cursor before
alternate-screen entry, so shutdown can return to row 1/column 1 instead of
the launch cursor and overwrite prior shell rows. P9-002 proves
exception-safe cleanup ownership and best-effort restoration, not exact
terminal byte/content/cursor-position semantics. `TuiApp.dispose()` remains
required to release owned input modes, handlers, and renderer resources; do
not add a Dart ANSI/save-slot workaround that duplicates native ownership.

## Development Commands

### Repository automation policy

GitHub Actions is intentionally disabled at the repository-permissions level.
The checked-in workflow files are dormant configuration and must not be
dispatched, rerun, or re-enabled unless the user explicitly requests it.

Ordinary repository-local validation is authorized. Agents may run:

```bash
dart format --set-exit-if-changed lib/ test/ example/ bin/ scripts/
dart analyze --fatal-infos
dart test test/architecture/
dart test <focused test paths or name filters>
dart test --exclude-tags process-spawning --concurrency=1
```

This includes unit, widget, golden, architecture, package-consumer, and
ordinary integration tests that run through the repository's existing
hermetic or in-process harnesses. Use the focused/checkpoint cadence in
`tasks/READ_HERE.md`; a full suite is not required after every small task. A
literal unfiltered `dart test` is authorized only when its selected tests have
first been checked not to exercise a restricted behavior below.

Do not run host-sensitive or destructive diagnostics unless the user
explicitly authorizes the exact operation. This restricted category includes:

- memory-leak, sanitizer, Valgrind, heap-profiler, or resource-exhaustion
  probes;
- deliberate native crashes, aborts, segmentation faults, fatal-signal
  injection, or process-kill testing;
- real terminal, PTY, ConPTY, raw-mode, iTerm, or visual-session automation;
- native binary rebuilds, ABI fault injection, artifact publication, release
  operations, or checks that replace the checked-in native artifacts; and
- GitHub workflow dispatch, rerun, or re-enablement.

An ordinary Dart test is not host-sensitive merely because the package uses
the checked-in OpenTUI library. Existing parser fakes, headless renderers,
temporary-directory Git fixtures, subprocess consumer analysis, and
architecture source scans remain authorized unless they deliberately exercise
one of the restricted behaviors above.

### Run Tests
```bash
dart test --exclude-tags process-spawning  # Complete ordinary suite
dart test --reporter=expanded <focused paths>  # Verbose focused output
dart test test/layout_widgets_test.dart  # Specific test file
dart test --name="Layout"          # Tests matching pattern
```

### Code Analysis
```bash
dart analyze                       # Static analysis
dart analyze --fatal-infos         # Strict analysis with warnings as errors
dart format lib/ test/ example/    # Code formatting
```

### Run Examples
```bash
dart run example/layout_demo.dart     # Comprehensive layout showcase
dart run example/hello.dart           # Introductory app
dart run example/focus_form.dart      # Focus & input routing demo
dart run example/pulse_animation.dart # AnimationController showcase
```

### Visual rendering verification (interactive TUI checks)

For changes that affect colors, attributes, cursor, or box-drawing glyphs — things text-only goldens cannot see — use the `iterm2-control` MCP plus the bitmap screenshot helper. **This complements, not replaces, golden tests.**

The MCP opens **dedicated iTerm2 windows** the agent controls. Never reuse the user's existing iTerm2 windows — session isolation is the whole point so the user can keep working in their own terminals undisturbed.

Workflow when the user asks "test this in the terminal" / "show me how this renders":

1. `iterm_new_session` → `iterm_rename_session` to a stable title (e.g. `baghdad-test`). If a session with that name already exists from a prior run, `iterm_stop_session` it first.
2. `iterm_send_and_read` to run the example, e.g. `dart run example/hello.dart`.
3. `iterm_capture_screen` for a fast text snapshot of cells (colors/attrs preserved in the tool response).
4. `bash scripts/screenshot_iterm.sh baghdad-test .context/screenshots/<name>.png` for the bitmap — this is the only way to verify the rendered cursor, true colors, and glyph fidelity, since goldens discard all three.
5. `iterm_stop_session --close-window` when done.

Prefer this over piping the example through a non-tty (e.g. `dart run ... | head`) — the latter strips ANSI, hides the cursor, and forces the renderer onto a degraded code path.

When validating an already-open dedicated iTerm window, resolve it by
title/id instead of screen coordinates:

```bash
wid="$(GetWindowID iTerm2 baghdad-codex-test)"
screencapture -x -l "$wid" .context/final_visual_checks/example.png
```

Capture both iTerm text contents and bitmap screenshots before/after key
interactions, then build a contact sheet under
`.context/final_visual_checks/contact_sheet.png` and inspect it for wrong
screens, blank captures, clipping, spacing, flex allocation, cursor state,
and visible interaction results. Do not use Computer Use for this workflow.

### OpenTUI Library Setup
```bash
# Verify checked-in native assets against native_manifest.json
dart run scripts/fetch_opentui_binaries.dart --verify-only

# Build a hook-aware CLI bundle with libopentui under bundle/lib/
dart build cli -t bin/health_check.dart

# Exact development override for a custom build
export OPENTUI_LIBRARY_PATH=/path/to/libopentui.{dylib|so|dll}
```

## OpenTUI Primitive Usage

**Primary Goal**: Utilize ALL available OpenTUI primitives through Dart FFI, including:

- **Buffer Management**: Text positioning, color handling, screen updates
- **Layout Primitives**: Constraint systems, size calculations, positioning
- **Input Handling**: Keyboard, mouse, focus management
- **Rendering**: Character cells, styling, decorations
- **Event System**: User interactions, state changes

**Integration Approach**: Build high-level Flutter-like widgets that efficiently map to OpenTUI's low-level primitives while maintaining the declarative programming model.

## Validation Workflow

When implementing or debugging features:

1. **Check Reference Implementations**: Look at Go/React packages for expected behavior
2. **Test with OpenTUI Examples**: Run reference implementation examples to understand expected output
3. **Verify Primitives**: Ensure Dart FFI calls match the OpenTUI API contracts
4. **Cross-Reference**: Compare widget behavior against Flutter documentation where applicable

## Code Quality Standards

- **Focus on Widgets**: Implement complete widget APIs similar to Flutter
- **Container**: Keep the Flutter-style `Container` convenience widget backed by the current render stack; update docs if its role changes
- **OpenTUI First**: Always prefer OpenTUI primitives over custom implementations
- **Performance**: Efficient FFI usage, minimal memory allocations
- **Testing**: Comprehensive tests including visual regression (golden files)
- **Documentation**: Clear examples demonstrating Flutter-like patterns

## Success Criteria

The framework should enable developers to:
- Build complex terminal UIs using familiar Flutter patterns
- Access all OpenTUI capabilities through high-level widgets
- Manage state reactively with setState() and rebuild cycles
- Create responsive layouts with sophisticated alignment and flex systems
- Style applications with colors, borders, and text formatting
- Handle user input through standard Flutter event patterns

## What NOT to Include

- Technical implementation details about FFI bindings or low-level APIs
- OpenTUI-specific memory management details
- Platform-specific rendering optimizations
- Widget internals or element tree management

## Important Development Guidelines

- **Never reference Claude or AI assistance** in commit messages, PR descriptions, or documentation
- **Git commits should be professional** and focus on technical changes, not mention AI tools
- **Code quality first** - ensure all changes pass tests and linting before committing

Focus on **usage patterns**, **validation approaches**, and **development workflow** rather than implementation specifics.

## Widget development rules

These rules apply to any new widget, render object, or test added to this
project. They consolidate patterns that emerged while building Select,
ScrollBox, TextArea and refactoring TextInput; deviating without a clear
reason produces avoidable code duplication or correctness gaps.

- **Focus-owning widgets** must use `FocusNodeOwnerStateMixin`
  (`lib/src/widgets/focus_node_owner_mixin.dart`). Override
  `widgetFocusNode` to forward the constructor parameter and call
  `syncFocusNode(oldWidget.focusNode)` from `didUpdateWidget`. Don't
  hand-roll `_focusNode`/`_ownsFocusNode` lifecycles.
- **Text editing** must go through `TextEditingController`
  (`lib/src/foundation/text_editing_controller.dart`) — both single-line
  and multi-line.
  Don't reinvent cursor or edit logic in widget state. For single-line
  inputs pass `allowNewline: false` to `insert(...)`.
- **Pointer click mapping** must use render-tree hit testing and
  `MouseEvent.localPosition`; never walk the element tree or recompute
  absolute origins in State. For non-pointer layout metrics that State must
  read after layout, prefer a render-owned metrics object over paint-time
  closures or callbacks.
- **Painting outside a widget's own bounds** must go through the display-list
  clipping surface (`PaintingContext` / `TuiCanvas.clipRect`) — never trust
  ad-hoc bounds checks. Used by `RenderScrollBox` to clip child paints to the
  viewport.
- **`RenderProxyBox.child=` is idempotent**. Re-assigning the same child
  or one already adopted via `attachRenderObject` must be safe (no double
  adoption). Match this pattern in any new RenderProxyBox-like class.
- **RenderObjectWidget over Paintable mixins**. Real rendering happens
  via `createRenderObject` returning a `RenderBox` subclass. The
  framework's paint walk visits `RenderObject` children, not Element
  mixins.
- **Visual goldens validate colour, attributes, and cursor by default** via
  sidecars (`<name>.styles.txt`, `<name>.cursor.txt`). Opt out only for
  intentionally text-only assertions.
- **Behavioural input tests** use `KeyDriver` (`test/helpers/key_driver.dart`)
  for synthetic parsed events, or `createTuiTestApp`
  (`test/helpers/tui_test_app.dart`) when the real binding/parser path matters.
  Don't repeat the `Future.delayed(Duration.zero)` boilerplate.
- **Use `BufferMatchers`** for cell-level assertions (`hasCharAt`,
  `hasColorAt`, `hasBackgroundAt`, `cursorAt`) instead of
  manually pulling fields off `CapturedCell`.
- **Four test harnesses, each with a distinct job:** `WidgetTester.pumpWidget`
  for layout math, `BufferCapture.capture` for single-frame rendered output,
  `KeyDriver` for synthetic input behavioural tests, and `createTuiTestApp`
  for end-to-end integration through real bindings/parsers. New tests must
  slot into one, not invent a fifth. See
  `test/helpers/README.md`.

## Current Status

- ✅ Core Widget/Element/RenderObject system
- ✅ Layout widgets (Row, Column, Container, Flexible, Expanded, Padding, SizedBox, Align)
- ✅ Text rendering with styles
- ✅ State management with setState()
- ✅ Comprehensive FFI bindings
- ✅ Golden testing framework (text-only buffer captures; see "Test accuracy" below)
- ✅ Focus, FocusScope, PointerListener
- ✅ TextInput (single-line) — refactored to RenderObjectWidget
- ✅ Select&lt;T&gt; — keyboard- and mouse-driven option list
- ✅ ScrollBox — `ScrollController`, viewport clipping (via `TuiCanvas.clipRect`),
      vertical/horizontal scroll, scrollbar, keyboard + wheel input
- ✅ TextArea — multi-line input with `TextEditingController`, cursor management,
      Ctrl+Enter for submit
- ✅ InheritedWidget pattern
- ✅ Core-framework 1.0 boundary defined for the existing Widget/Element/RenderObject substrate
- 📋 Post-1.0 OpenTUI-React components: TabSelect, Code, Diff, Markdown, AsciiFont
- 📋 Post-1.0 hook-style APIs (`useKeyboard`, `useTerminalDimensions`, `useTimeline`)
      and interaction extensions (drag-thumb scrollbar, TextArea selection)
- 📋 Measurement-gated P9-032/P9-033 performance proposals

### Test accuracy

Golden tests render through the real OpenTUI FFI pipeline (`Renderer` →
`Buffer` → C library) and capture cells via `BufferCapture` /
`DirectBufferAccess`. The stored `.buffer.txt` records **characters only**.
Style and cursor expectations live in sidecars (`<name>.styles.txt`,
`<name>.cursor.txt`) when visual goldens are used. To assert color,
attribute, or cursor correctness in unit tests, use `BufferMatchers`
(`hasColorAt`, `hasBackgroundAt`, `cursorAt`) or inspect
`CapturedCell` / captured cursor fields directly.

The terminal cursor used by `TextInput` / `TextArea` is rendered via
`CursorController`; it is not part of the character buffer. The cursor sidecar
and cursor matchers validate the captured cursor state, while bitmap/iTerm
checks remain the way to validate actual terminal escape rendering.

`createTuiTestApp` drives integration tests through the real
`StdinInputDriver` parser by feeding raw ANSI bytes directly into the same
parser entry point used by production stdin. It is not a real OS pseudo-TTY,
so a future PR can still add (a) a richer golden format that snapshots ANSI
output bytes and (b) a pty harness for terminal-mode behavior outside the
parser itself.

Core-framework 1.0 covers the declarative Widget/Element/RenderObject lifecycle,
state, layout and paint recording, text, focus and input, inherited dependencies,
animation, bundled native loading, and the currently documented widgets and
low-level APIs. All remaining Noir-local correctness gates still apply;
documented limitations that require changes to the read-only OpenTUI dependency
do not block this repository’s PR closeout.

Full OpenTUI-React component and hook parity is post-1.0 work, not a core-framework
1.0 gate. P9-032 and P9-033 activate only when retained, reproducible measurement
violates an explicit workload budget.

Full-root layout and paint recording on dirty frames and transient native-text
preparation during display-list encoding are accepted core 1.0 costs, not performance guarantees.

This boundary does not claim a completed release, pub.dev publication, a stable
version or tag, platform runtime acceptance, or resolution of the documented
read-only native dependency limitations.
