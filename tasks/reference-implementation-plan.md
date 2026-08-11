# Reference Implementation Refactor Plan

> **Standard:** see [`GOALS.md`](../GOALS.md) for the durable quality bar this plan moves us toward.
> **Agent entry point:** [`tasks/READ_HERE.md`](READ_HERE.md) — orchestration workflow, sub-agent roles, fitness functions, and live phase status.
> **Per-phase trackers:** [`tasks/phase-*.md`](.) — checklists agents tick off as work lands.
> **Status:** Phases 0-8 and the v1 Final Acceptance are complete; the reference-quality release commit is tagged `reference-implementation-v1`, and Phase 9 is active.
> **Companion plan:** [`tasks/plan.md`](plan.md) (parity scenes / harness) — runs alongside this one.

This file is a checked-in copy of the full reference-implementation review that
defined the target architecture and refactor phases. Treat it as the source of
truth for *what* needs to change (the deep "why" behind every phase). Treat
[`GOALS.md`](../GOALS.md) as the source of truth for *how* we work while it's
in flight. Treat [`tasks/READ_HERE.md`](READ_HERE.md) as the entry point and
[`tasks/phase-*.md`](.) as the live trackers — those are where execution
happens day-to-day.

`Current` in the original review below refers to its audited baseline, not
today's tree.

## Current lifecycle and API descendant

`runTuiApp` synchronously returns a private-constructor `TuiApp` that owns the
mounted application and its app-priority input registrations. Registration
cancelers and `TuiApp.dispose()` are idempotent; disposal cancels still-owned
registrations before the internal binding tears down the mounted tree and
terminal session. Headless applications own no terminal renderer.

The supported descendant has three tiers: `package:noir/noir.dart` for
ordinary application/widget authoring, `package:noir/noir_low_level.dart` for
advanced hosting and supported renderer/render-object protocols, and
`package:noir/noir_ffi.dart` for ABI-unstable raw FFI access. Concrete Element
implementations and the display-list/recorder/command/encoder/compositor
backend remain framework-owned rather than supported package surfaces.

## Execution status

- 2026-05-19: Phase 0 guardrails and blocker fixes landed in this workspace:
  buffer-import allowlist, public API lock, native lifecycle guard,
  `ObjectKey` identity semantics, inherited null-aspect dependency removal,
  `RenderParagraph.detach()`, Dart SDK floor `>=3.10.0`, and branch/PR CI.
- P0.6 remains deferred to Phase 4, where display-list painting removes the
  clipped scratch-renderer path instead of papering over it locally.
- 2026-05-19: Phase 1 three-barrel public API split landed.
  The internals barrel was deleted; `noir_low_level.dart` and
  `noir_ffi.dart` were added with stability-tier doc comments; and
  `internals_barrel_split_test.dart` locks the shape.
- 2026-05-19: Phase 1 closeout landed. Stale references to the deleted
  internals barrel were cleared from `lib/noir.dart` and `GOALS.md`;
  `no_stale_internals_refs_test.dart` and
  `low_level_symbol_monotonic_test.dart` were added with the baseline at
  `test/architecture/baselines/noir_low_level_symbols.txt`;
  `example/hello.dart` is now high-level-only; and the `parseAnsiBytes`
  backwards-compat wrapper was deleted per the no-BC rule.
- 2026-05-19: Phase 2A foundation primitives landed.
  `lib/src/foundation/{listenable,change_notifier,value_notifier,disposable}.dart`
  was added with `VoidCallback`. `ScrollController`,
  `Animation`/`AnimationController`, `FocusNode`, `ViewportController`, and
  `CursorController` migrated onto the shared primitives. Public typedefs
  `AnimationListener`, `FocusChangeListener`, and `ScrollListener` were
  removed with no retained aliases. Foundation tests cover add/remove,
  duplicate listeners, mutation-during-notification, dispose idempotence,
  `ValueNotifier` equality, and `Listenable.merge` including
  `removeListener` correctness.
- 2026-05-19: Phase 2B text editing controller migration landed. The
  temporary mutable text-editing bridge was deleted; `TextEditingController`,
  `TextEditingValue`, `TextSelection`, and `TextRange` now own text editing
  state. `TextInput` and `TextArea` migrated to controller/value semantics,
  render objects no longer receive mutable editing models, and visual goldens
  validate buffer/style/cursor sidecars.
- 2026-05-19: Phase 3 kernel split landed.
  `TerminalSession`, `SchedulerBinding`, `PipelineOwner`, `RenderView`,
  `InputDispatcher`, and the advanced `TuiBinding` own the internal lifecycle
  graph. `runTuiApp` returns the narrowed, owning `TuiApp` facade, and
  `createTuiTestApp` drives integration tests through the real ANSI parser,
  scheduler, binding, render root, and captured frame path.
- 2026-05-20: Phase 4 display-list painting landed.
  Render objects now record through `PaintingContext` / `TuiCanvas`;
  the private recorder/encoder/compositor backend applies those recordings to
  OpenTUI buffers; the render/widget `Buffer` import allowlist is empty; and
  clipped `TextBuffer` drawing no longer creates scratch `Renderer` instances.
- 2026-05-20: Phase 5 text system landed and is tagged `phase-5-complete`.
  `RenderParagraph` records `TextLayout` as a display-list operand instead of
  owning `TextBuffer`; `TextLayout` carries wrapped lines, style runs,
  `TextIndexMap`, and source-to-buffer mappings; and Unicode visual paths are
  covered for emoji, CJK, combining marks, ZWJ, multiline paste, selection, and
  `obscureText`.
- 2026-05-20: Phase 6 input semantics landed. The closeout commit is tagged
  `phase-6-complete` after the phase boundary commit. `KeyEvent` now carries
  logical keys, printable characters, modifiers, and press/repeat/release
  state; widgets consume semantic `Shortcuts` / `Actions` / `Intent` APIs; Tab
  and Shift+Tab route through `FocusTraversalPolicy`; and
  `TextInputConnection` owns built-in text-editing shortcuts/actions against
  `TextEditingController`.
- 2026-05-20: Phase 7 render-tree hit testing landed. Pointer dispatch now
  flows through `PointerRouter` and `RenderObject.hitTest` instead of
  paint-time regions; `MouseEvent.localPosition` carries target-local
  coordinates; `PointerManager` / `PointerHandle` / `updateRegion` were
  deleted; `Select` no longer walks the element tree for click rows; and
  `ScrollBox` wheel input is hit-test gated.
- 2026-05-20: Phase 8 native assets landed and is tagged `phase-8-complete`.
  Dart native assets now bundle `libopentui` through `hook/build.dart` /
  `CodeAsset`; `OPENTUI_LIBRARY_PATH` is the exact development override only;
  startup validates the OpenTUI ABI before renderer creation; and the deleted
  multi-location library locator cannot return.
- 2026-05-20: Final Acceptance landed. `GOALS.md` §7, standards conformance,
  final drift, distribution, native lifecycle, and full mechanical gates passed;
  the release commit is tagged `reference-implementation-v1`.
- 2026-07-10: Phase 9 opened the post-v1 whole-repository review. Its live
  finding ledger, required/external/optional dispositions, and current
  acceptance state are owned by
  [`tasks/phase-9-post-v1-reference-review.md`](./phase-9-post-v1-reference-review.md).

## Hard rules

- No backwards-compat shims, deprecated aliases, or legacy barrels for the MVP
  refactor. Old API shapes are deleted, not wrapped.
- Flutter-like semantic compatibility is still a goal.
- Agent context teaches the desired architecture, not preserved old decisions;
  stale references are drift.
- No code is added against an obsolete contract once the new contract exists.
  New shapes do not coexist with old shapes through compatibility paths.
- The temporary text-editing bridge was deleted in Phase 2B. Do not
  reintroduce an internal mutable cursor model; use `TextEditingController`
  / `TextEditingValue`.
- OpenTUI is pinned and read-only for the active program.
  `external/opentui` is a read-only Git submodule. The configured fork URL
  records provenance; it does not authorize changes to that repository.
  Agents may initialize, inspect, and verify the pinned dependency, but must
  not edit or advance it, create or push OpenTUI refs, run OpenTUI workflows,
  rebuild or replace the six bundled libraries, or roll the native ABI,
  manifest, or provenance. Native-only findings remain visible, documented
  `read-only-upstream` limitations and do not block Noir-local PR closeout.
  Reversing the boundary requires a separate, explicit dependency-strategy
  decision.

---

Full reference-implementation review

Executive decision

I would not merge claude/check-main-commit-SpynD as the reference implementation yet.

I would treat it as a strong MVP/prototype branch that proves the direction is viable. It correctly moves the project toward a Flutter-like terminal framework: TuiApp, widgets, elements, render objects, focus, pointer routing, text input, select, scroll box, textarea, animation scaffolding, native FFI wrappers, and golden tests are all present. The branch README also explicitly frames the repo as a Flutter-like OpenTUI Dart framework, not just bindings.

But by reference-implementation standards, the branch still has blocking architectural and semantic issues:

Status: keep direction, do not freeze architecture.
Merge readiness: not yet.
Best next move: stabilize branch, then refactor kernel before adding more widgets.

The key problem is that the branch already builds many widgets, but the underlying primitive architecture is still MVP-grade:

Current branch:
Widget → Element → RenderObject → direct OpenTUI Buffer mutation
Reference implementation:
Widget → Element → RenderObject → PaintingContext/TuiCanvas → DisplayList → Compositor → OpenTUI

That difference determines whether the package can scale into an official framework.

---

1. Semantic brief

What this implementation is trying to be

This branch is trying to implement:

A Flutter-like reactive terminal UI framework for Dart,
using OpenTUI as the native terminal renderer.

That is the correct product direction.

The public export surface already exposes:

FFI types
Renderer
Buffer
Cursor
Input
TextBuffer
Widget framework
BuildContext
Element
RenderObject
RenderBox
FocusManager
Hit-test primitives
Layout widgets
Text
Input
Select
ScrollBox
TextArea
Animation primitives
Diagnostics

That means the branch is no longer merely "Dart bindings for OpenTUI." It is becoming a full framework.

Reference semantic target

The reference implementation should guarantee:

Widgets are immutable configuration.
Elements preserve identity and State.
BuildContext is an Element location.
InheritedWidget dependencies are tracked precisely.
RenderObjects own layout and paint.
Painting records terminal commands, not immediate native mutations.
The compositor owns OpenTUI buffer/native calls.
Text editing is controller/value/selection based.
Unicode cell width and grapheme indexing are first-class.
Focus and keyboard routing are semantic, not ad hoc.
Native resources are explicitly closed.
Native binaries are delivered through Dart native assets.

Flutter's own Widget API defines widgets as immutable descriptions that inflate into elements, and replacement is based on runtimeType and key. The branch mostly understands that, but several implementation details are still off.

---

2. Audit summary

| Area | Current branch | Reference verdict |
| --- | --- | --- |
| Product direction | Correct | Keep |
| Widget/Element/State shape | Good MVP | Harden |
| BuildContext | Good start | Needs mounted, stronger inherited semantics |
| InheritedWidget | Present | Has bug and missing app-level inherited primitives |
| RenderObject model | Present | Too directly coupled to OpenTUI Buffer |
| Pipeline | Missing | Must add PipelineOwner and RenderView |
| Painting | Direct buffer mutation | Replace with PaintingContext / display list |
| Text | Uses OpenTUI TextBuffer | Needs TextSpan, layout engine, index map |
| Text editing | Internal mutable cursor model | Needs TextEditingController / TextEditingValue |
| Unicode | Partial | Not reference-correct |
| Focus | Good MVP | Needs traversal + shortcuts/actions |
| Pointer | Region-based MVP | Needs render-tree hit testing |
| Scheduler | Microtask frame loop | Needs FPS-aware scheduler |
| FFI | Usable wrapper | Needs ABI check, singleton symbols, arena/batch path |
| Native distribution | Local binary locator | Needs Dart native assets |
| Dart style | Mostly okay | Needs class modifiers, API narrowing, docs cleanup |
| Tests | Strong direction | Needs semantic regression and Unicode/input/backend tests |

---

3. Critical blocking issues

These should be fixed before the branch is treated as the foundation.

P0.1 — Public export references a missing file

`lib/noir.dart` exports:

```dart
export 'src/widgets/raw_keyboard_listener.dart' show RawKeyboardListener;
```

I attempted to fetch `lib/src/widgets/raw_keyboard_listener.dart` at `claude/check-main-commit-SpynD`, and it was not found. Search only found it in the base commit, not the branch. Unless the connector missed the file, this will break `dart analyze` and package import resolution.

Fix

Either restore the file or remove the export. Do this before any deeper review.

---

P0.2 — ObjectKey has the wrong semantics

Current branch:

```dart
class ObjectKey<T> extends LocalKey {
  const ObjectKey(this.value);
  final T value;
  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is ObjectKey<T> &&
      other.value == value;
}
```

For Flutter-like semantics, `ObjectKey` must use object identity, not `==`. Flutter's `ObjectKey` documentation says it takes identity from the object and its constructor uses `identical` for equality.

Current behavior makes `ObjectKey` too similar to `ValueKey`. That can incorrectly preserve or replace elements when two distinct model objects compare equal.

Fix

```dart
@override
bool operator ==(Object other) {
  return other.runtimeType == runtimeType &&
      other is ObjectKey<T> &&
      identical(other.value, value);
}
@override
int get hashCode => Object.hash(runtimeType, identityHashCode(value));
```

Add tests:

- `ObjectKey(modelA) != ObjectKey(modelB)` when `modelA == modelB` but `!identical`.
- `ValueKey(modelA) == ValueKey(modelB)` when `modelA == modelB`.

---

P0.3 — InheritedElement.removeDependent is semantically wrong for null aspects

Earlier branch code removes a dependent like this:

```dart
final removed = _dependents.remove(dependent);
if (removed != null) {
  dependent.didLoseDependency(this);
}
```

But normal inherited dependencies use a `null` aspect. Removing a map entry whose value is `null` returns `null`, so `didLoseDependency` does not run even though the dependent existed.

Flutter's inherited pattern depends on registered dependents rebuilding when the inherited widget changes.

Fix

```dart
void removeDependent(Element dependent) {
  final existed = _dependents.containsKey(dependent);
  _dependents.remove(dependent);
  if (existed) {
    dependent.didLoseDependency(this);
  }
}
```

Add tests:

- `dependOnInheritedWidgetOfExactType` registers dependency with null aspect.
- Dependency is removed when child no longer depends on it.
- Old inherited widget does not notify removed dependent.

---

P0.4 — TextInput.obscureText stores masked text

The pre-fix text input path applied the obscuring character before inserting
the user's printable key into the editing model. That meant password input
stored `"*****"` as the real value and fired `onChanged` with the masked value.

That is wrong. Obscuring is a paint concern, not an editing-state concern.

Fix

Store real printable input in the editing model and apply masking only while
painting.

Render masked text only:

```dart
final visualText = obscureText
    ? String.fromCharCodes(List.filled(graphemeCount, '*'.codeUnitAt(0)))
    : value;
```

Add tests:

- Typing `"abc"` into obscureText field calls `onChanged("abc")`.
- Painted buffer shows `"***"`.
- Controller/model value remains `"abc"`.

---

P0.5 — RESOLVED in Phase 5: RenderParagraph no longer owns native TextBuffer

The initial review found that `RenderParagraph` owned a native
`TextBuffer? _textBuffer` and therefore needed deterministic disposal. Phase 5
removed that ownership boundary instead: `RenderParagraph` records `TextLayout`
through the display list, and the display-list encoder materializes and
disposes transient native `TextBuffer` instances.

Regression coverage:

- `render_paragraph_text_layout_test.dart` verifies `RenderParagraph` records
  `TextLayout` and does not import/own `TextBuffer`.
- `render_paragraph_lifecycle_test.dart` verifies detach clears layout state
  without native text-buffer ownership.

---

P0.6 — Clipped TextBuffer rendering creates a scratch renderer during paint

Historical finding: the old clipped text-buffer path created a scratch renderer inside `_drawTextBufferCells()`, drew into it, read direct buffer access, copied cells, and destroyed the scratch renderer.

Resolved by Phases 4 and 5: painting now records display-list commands, and the display-list encoder clips text-buffer output without creating a `Renderer` during paint.

This is the strongest sign that the painting architecture needs to change.

Creating a native renderer during paint is not reference-quality. It risks:

- native allocation churn
- render-time latency spikes
- terminal side effects
- resources retained under exceptions
- poor scroll/text performance

Fix

Do not solve this locally inside `Buffer.clipped()`.

Move clipping into a display-list/compositor layer:

- Render object: `canvas.pushClip(...)`
- Compositor: clips draw commands or calls native clipped text-buffer draw

Short-term fallback:

- Use native text-buffer clip function directly.
- If unavailable, clip text before writing into TextBuffer.
- Never create Renderer during paint.

---

P0.7 — Branch SDK lower bound conflicts with future native assets

Current branch:

```yaml
environment:
  sdk: '>=3.9.0 <4.0.0'
```

Dart build hooks were introduced in Dart 3.10, and hooks can compile or download native assets. The docs also state that build hooks are automatically invoked during run, build, and test, and their assets are automatically bundled.

So if the official package uses native assets, the lower bound should become:

```yaml
environment:
  sdk: '>=3.10.0 <4.0.0'
```

If the project stays on `>=3.9.0`, it cannot use the current build-hook-native-asset model as the primary distribution path.

---

4. Architecture review

4.1 The branch has the correct macro-shape

Current `TuiApp` does the core MVP flow:

- create input manager
- create build owner
- create renderer
- setup terminal
- start stdin driver
- mount root widget
- schedule frame
- build dirty elements
- layout render tree
- paint into buffer
- render terminal frame
- restore terminal on dispose/signals

This is directionally correct.

4.2 But TuiApp is doing too much

`TuiApp` currently owns:

- native renderer lifecycle
- terminal setup
- stdin driver
- signal handling
- resize handling
- frame scheduling
- build phase
- layout phase
- paint phase
- render commit
- headless mode
- input dispatch callback

For a reference implementation, split this into:

- `TuiBinding` — global coordinator
- `TerminalSession` — native renderer, terminal modes, resize, suspend/resume, cleanup
- `SchedulerBinding` — frame timing, animation ticks, post-frame callbacks
- `BuildOwner` — dirty element rebuilds
- `PipelineOwner` — layout, paint, compositing queues
- `InputDispatcher` — key, mouse, paste, resize delivery
- `OpenTuiCompositor` — display-list → OpenTUI backend

`TuiApp` can remain as a convenience facade, but not the core kernel.

---

4.3 Render objects are too coupled to OpenTUI Buffer

Historical render contract: render objects accepted a `Buffer` plus integer
offsets and painted children directly into the native buffer wrapper.

Reference contract should be:

```dart
void paint(PaintingContext context, Offset offset);
```

Then only the compositor imports `Buffer`.

This is the single most important architecture correction.

---

4.4 There is no real PipelineOwner

Current `RenderObject` explicitly documents that the MVP does full-frame layout and paint every scheduled frame and has no per-node dirty tracking.

That is honest and fine for MVP. It is not enough for reference quality.

Add:

```dart
final class PipelineOwner {
  void scheduleLayout(RenderObject node);
  void schedulePaint(RenderObject node);
  void flushLayout();
  void flushPaint();
  void flushCompositing();
}
```

Then render objects should call:

```dart
markNeedsLayout();
markNeedsPaint();
```

and the pipeline should decide what actually runs.

---

4.5 RenderView is missing

Current `TuiApp._drawFrame()` finds the first descendant render object:

```dart
Element.findDescendantRenderObject(root)
```

then lays it out and paints it.

Reference architecture should have a root render object:

```dart
final class RenderView extends RenderObject {
  final TerminalSession session;
  final OpenTuiCompositor compositor;
  RenderObject? child;
  void compositeFrame();
}
```

`RenderView` owns terminal constraints and frame composition. `TuiApp` should not search for an arbitrary descendant render object.

---

5. Widget and element review

What is good

The branch has:

- Widget
- StatelessWidget
- StatefulWidget
- State
- ProxyWidget
- RenderObjectWidget
- SingleChildRenderObjectWidget
- Element
- StatelessElement
- StatefulElement
- ProxyElement
- InheritedElement
- RenderObjectElement
- SingleChildRenderObjectElement
- MultiChildRenderObjectElement

That is the correct foundation.

Issues

5.1 Widgets should be explicitly immutable

Flutter's widget docs state that widgets are immutable descriptions and all widget fields must be final.

The branch mostly uses final fields, but not all widget classes are annotated consistently with `@immutable`. Key implementations use `@immutable`, but `Widget` itself does not appear to.

Recommendation:

```dart
@immutable
abstract class Widget {
  const Widget({this.key});
  final Key? key;
}
```

5.2 Dirty build scheduling is too weak

Current `BuildOwner` uses a `Queue<Element>` and drains in insertion order.

Reference behavior should:

- skip unmounted elements
- sort dirty elements by depth
- guard reentrant builds
- avoid duplicate scheduling
- run finalizeTree after build

Recommended:

```dart
void buildScope() {
  _dirtyElements.sort((a, b) => a.depth.compareTo(b.depth));
  while (_dirtyElements.isNotEmpty) {
    final dirty = List<Element>.from(_dirtyElements);
    _dirtyElements.clear();
    for (final element in dirty) {
      element._inDirtyList = false;
      if (!element.mounted) continue;
      element.rebuild();
    }
    _dirtyElements.sort((a, b) => a.depth.compareTo(b.depth));
  }
}
```

5.3 GlobalKey has a deliberately narrower terminal-framework contract

`GlobalKey` has at most one live binding, including across different owners,
and acts as an owner-wide unique lookup handle. It exposes read-only
`currentContext`, `currentWidget`, and typed `currentState` views, while each
`BuildOwner` registry owns tree-local placement validation and permanent
teardown. Ordinary same-parent keyed reconciliation preserves Element, State,
and RenderObject identity.

Unlike Flutter, this terminal framework does not support moving a keyed
subtree to a different parent. Both traversal orders reject before the
incoming child edge drops or replaces its current child. The framework does
not carry Flutter's forced-detach/`forgetChild` protocol, delayed duplicate
reservations, or a traversal-order-dependent inactive-retake subset.

Reference shape:

```dart
final class GlobalKeyRegistry {
  final Map<GlobalKey, Element> _elements = {};
  void register(GlobalKey key, Element element);
  void unregister(GlobalKey key, Element element);
  Element? lookup(GlobalKey key);
  void validatePlacement(
    GlobalKey key,
    Widget candidate,
    Element intendedParent, {
    Element? retainedElement,
  });
}
```

The placement validator accepts only an unclaimed key or the exact compatible
element retained by ordinary reconciliation under the same parent. A fresh
key/new subtree is required when equivalent UI moves to another parent.

---

6. Layout/rendering review

Good work

The branch improved multi-child render object handling. `MultiChildRenderObjectElement` now has hooks for `adoptChildRenderObject` and `dropChildRenderObject`, and `FlexRenderObjectElement` supplies flex metadata to `RenderFlex`.

That is much better than hardcoding flex behavior inside generic multi-child element logic.

Remaining issues

6.1 Parents call performBoxLayout() directly

Several render objects call child layout through `performBoxLayout()` rather than `layout()`. For example, `RenderProxyBox` calls:

```dart
child.performBoxLayout(childConstraints);
```

That bypasses any future layout bookkeeping.

Reference rule:

- Only a render object itself calls its own `performLayout`/`performBoxLayout`.
- Parents call `child.layout(constraints)`.

Fix now, before adding dirty layout queues.

6.2 Integer constraints are acceptable, but document their cell units

The branch uses integer `BoxConstraints` and `Size`.

That is fine for terminal cell layout, but it must be explicit. The reference
implementation kept Flutter-style public names (`BoxConstraints`, `Size`,
`Offset`, `Rect`) and documents that their units are terminal cells instead of
logical pixels.

If the internal model ever changes, preserve that clarity rather than adding a
second parallel geometry vocabulary.

6.3 Avoid magic infinity

The branch uses `999999` as an unbounded constraint sentinel.

Replace with:

```dart
static const int maxFiniteCellExtent = 1 << 30;
```

or introduce:

```dart
bool hasBoundedWidth;
bool hasBoundedHeight;
```

Do not hide infinity inside a magic number.

---

7. Painting and compositor review

Current state

The original MVP render objects bypassed a display list and mutated the
OpenTUI buffer wrapper themselves. The wrapper exposed draw text, fill rect,
draw box, set cell, direct access, text-buffer drawing, and clipped views.

This works.

Reference problem

Direct buffer painting prevents:

- display-list testing
- batched native commits
- repaint boundaries
- style interning
- frame packet encoding
- backend swapping
- headless canvas tests
- clean clipping semantics

Required reference implementation

Add:

```dart
final class PaintingContext {
  PaintingContext(this.canvas);
  final TuiCanvas canvas;
  void paintChild(RenderObject child, Offset offset);
}
final class TuiCanvas {
  void save();
  void restore();
  void clipRect(Rect rect);
  void fillRect(Rect rect, Color color);
  void drawTextLayout(TextLayout layout, Offset offset);
  void drawBox(Rect rect, BoxOptions options, Color borderColor, Color backgroundColor);
  TuiDisplayList finish();
}
final class OpenTuiCompositor {
  void commit(TerminalSession session, TuiDisplayList displayList);
}
```

Initial backend may translate commands into existing `Buffer` calls. The important point is that render objects stop importing `Buffer`.

---

8. Text review

What is good

`RenderParagraph` records `TextLayout`, which supports wrapping, max lines,
alignment, ellipsis, source mapping, and selection materialization in the
display-list encoder.

The branch includes characters, and `RenderParagraph._wrapText()` iterates grapheme clusters for wrapping.

That is a good start.

What is missing

8.1 No TextSpan / RichText

The current public `Text` widget is single-style text only.

A Flutter-like framework needs:

```dart
abstract class InlineSpan {}
final class TextSpan extends InlineSpan {
  const TextSpan({
    this.text,
    this.style,
    this.children = const [],
  });
  final String? text;
  final TextStyle? style;
  final List<InlineSpan> children;
}
```

Then:

```dart
Text.rich(
  TextSpan(
    children: [
      TextSpan(text: 'Error: ', style: TextStyle(fontWeight: FontWeight.bold)),
      TextSpan(text: 'file not found'),
    ],
  ),
)
```

8.2 Unicode indexing is not reference-correct

The branch still uses code-unit or string-index logic in multiple places:

- Deleted text-editing bridge: `String.length`, `substring`
- `TextInput`: `displayText[i]`
- `TextArea`: `line[colIdx]`
- `Select`: `name.length` / `description.length`
- `TextBuffer.setCell`: `char.codeUnitAt(0)`

That breaks on:

- emoji
- CJK wide characters
- combining marks
- ZWJ sequences
- variation selectors
- accented characters

Required primitive:

```dart
final class TextIndexMap {
  TextIndexMap(String text);
  int utf16ToGrapheme(int utf16Offset);
  int graphemeToUtf16(int graphemeIndex);
}
```

The cell and native-byte axes originally sketched here were removed in the
Phase 9 round-3 simplification review: cell math is owned by
`grapheme_metrics.dart`, and no consumer ever read the native-byte axis.

Reference rule:

> No visual text width or cursor movement may use `String.length` or `text[i]`.

8.3 TextBuffer lifecycle must be explicit

`TextBuffer` has deterministic `dispose()` plus a finalizer fallback.

That is good. But any render object that owns a `TextBuffer` must dispose it in `detach()`.

---

9. Text editing review

Original state

The branch added a pure Dart internal text-editing bridge with lines, cursor
line/column, insert/delete, newline, and movement operations.

`TextInput` and `TextArea` use it.

Reference issue

This is not yet Flutter-like enough.

The public primitive should be:

```dart
final controller = TextEditingController(text: 'hello');
TextInput(
  controller: controller,
  focusNode: focusNode,
)
```

Required classes:

```dart
final class TextEditingValue {
  const TextEditingValue({
    this.text = '',
    this.selection = const TextSelection.collapsed(offset: 0),
    this.composing = TextRange.empty,
  });
  final String text;
  final TextSelection selection;
  final TextRange composing;
}
class TextEditingController extends ValueNotifier<TextEditingValue> {
  TextEditingController({String? text});
  String get text;
  set text(String value);
  TextSelection get selection;
  set selection(TextSelection value);
  void clear();
}
```

Phase 2B deleted that bridge. Public widgets are controller-driven.

Required tests

- Programmatic `controller.text` update repaints field.
- Keyboard input updates `controller.value`.
- Controller listener fires once per editing transaction.
- Selection survives rebuild.
- `obscureText` masks rendering only.
- Paste applies as one transaction.

---

10. Input/focus/pointer review

10.1 StdinInputDriver is a strong addition

The parser handles:

- printable ASCII
- UTF-8
- backspace
- tab
- enter
- escape
- ctrl letters
- CSI arrows
- Home/End
- Delete/PageUp/PageDown
- function keys
- SGR mouse
- bracketed paste
- Kitty CSI-u
- DCS/OSC/APC/PM capability responses

The test coverage for this parser is also strong, including capability-response suppression, mouse, function keys, paste, and Kitty CSI-u.

Keep this.

10.2 InputManager is too narrow

Current `InputManager` is no longer a one-key-handler / one-mouse-handler MVP
object. It now has priority-ordered key, mouse, and paste subscriptions with
consumption semantics. That is a useful stepping stone, but it is still a
low-level event bus owned outside the binding/kernel structure.

A reference framework needs an `InputDispatcher` owned by the binding/session
graph. It should absorb or replace the current priority subscription semantics
without leaving a second dispatch path behind, and it should explicitly model
the framework layers that participate in input:

- global shortcuts
- focus manager
- text input connection
- raw listeners
- pointer router
- paste handlers
- terminal capability responses

Replace with:

```dart
final class InputDispatcher {
  void addKeyListener(KeyListener listener);
  void removeKeyListener(KeyListener listener);
  void dispatchKeyEvent(TuiKeyEvent event);
  void dispatchMouseEvent(TuiMouseEvent event);
  void dispatchPasteEvent(PasteEvent event);
}
```

10.3 Focus input semantics

Phase 6 completed the MVP focus/input gap: `FocusManager` now works with
semantic `KeyEvent` values, explicit `KeyEventResult` outcomes,
`FocusTraversalPolicy`, and `Shortcuts` / `Actions` / `Intent`.

Remaining advanced parity:

- `FocusOrder`
- broader custom/nested traversal-policy coverage
- richer user-authored shortcut composition examples

Complex widgets no longer parse raw key names directly. `Select` and
`ScrollBox` consume semantic intents, and text editing routes through
`TextInputConnection`.

Reference implementation should route semantic intents:

- `MoveSelectionUpIntent`
- `MoveSelectionDownIntent`
- `ActivateIntent`
- `DismissIntent`
- `NextFocusIntent`
- `PreviousFocusIntent`

10.4 Pointer routing now uses render-tree hit testing

Phase 7 deleted the MVP pointer region path. Widget pointer dispatch now flows
through `PointerRouter`, which subscribes through `InputDispatcher`, hit-tests
the current render root, and delivers events along the render-tree hit-test
path.

Reference behavior now present:

- `RenderBox.hitTest` rejects out-of-bounds positions and walks children in
  reverse paint order.
- `HitTestEntry.localPosition` carries target-local coordinates.
- `MouseEvent.localPosition` exposes the local position to `PointerListener`
  callbacks while `x` / `y` remain absolute parser coordinates.
- `Select` maps click rows from `localPosition`; it no longer walks the element
  tree or computes absolute Y.
- `ScrollBox` wheel delivery is hit-test gated and its child hit testing
  applies viewport clipping plus scroll translation.
- Native hit-grid APIs remain low-level renderer/FFI primitives only, not a
  widget pointer dispatch fallback.

Remaining advanced parity:

- pointer capture
- drag ownership
- hover state
- gesture abstraction

Reference primitive:

```dart
final class HitTestResult {
  final List<HitTestEntry> path = [];
}
final class HitTestEntry {
  final HitTestTarget target;
  final Offset localPosition;
}
abstract interface class HitTestTarget {
  void handleEvent(MouseEvent event, HitTestEntry entry);
}
```

---

11. FFI/native review

11.1 FFI wrapper is useful but too allocation-heavy

The wrapper repeatedly does:

- `utf8.encode(...)`
- `alloc<Uint8>(length)`
- copy bytes in Dart loop
- call native

For example, `bufferDrawText`, `bufferDrawBox`, and cursor style handling all follow this pattern.

That is acceptable for MVP.

Reference implementation needs:

- `NativeFrameArena`
- `PersistentUtf8Text`
- `StyleInterner`
- `FramePacketBuilder`
- `DisplayListEncoder`

Dart's C interop docs describe `dart:ffi` as the library for calling native C APIs and reading/writing native memory. The package should use FFI, but the public widget pipeline should not perform many FFI calls per paint pass.

11.2 Native symbols should be singleton-loaded

`Renderer` and `TextBuffer` each create `OpenTuiBindings()` instances, and the renderer finalizer also creates a new `OpenTuiBindings()` before destroying.

Reference design:

```dart
final class OpenTuiNativeLibrary {
  static final OpenTuiNativeLibrary instance = OpenTuiNativeLibrary._();
  late final DynamicLibrary library;
  late final OpenTuiBindings symbols;
  void validateAbi();
}
```

Avoid repeatedly opening/resolving the dynamic library.

11.3 Finalizer should be fallback only

`Renderer` uses a finalizer to destroy the native renderer if `dispose()` is forgotten.

That is useful, but terminal cleanup cannot depend on GC. The explicit lifecycle should be:

```dart
final tuiApp = runTuiApp(app);
// Later, when application-owned shutdown is requested:
tuiApp.dispose();
```

`runTuiApp` and `TuiApp.dispose()` are synchronous. The returned facade owns
the mounted app, its app-priority registrations, and terminal-session cleanup;
ordinary applications do not acquire or shut down a global binding.
Finalizers should only release otherwise-retained resources, not restore
terminal state.

11.4 ABI validation landed in Phase 8

The reference implementation now checks the Dart-facing ABI version and
resolves every address in the canonical 60-export guarded surface before
creating renderers. The package must not load an arbitrary `libopentui` and
hope the function layout matches.

ABI metadata/error functions (all four are required members of that inventory;
startup invokes only the first two before address-only validation):

```c
uint32_t otui_dart_abi_version(void);
const char* otui_dart_build_info(void);
const char* otui_dart_last_error(void);
void otui_dart_clear_error(void);
```

Runtime:

```dart
void validateAbi() {
  final version = symbols.otuiDartAbiVersion();
  final buildInfo = symbols.otuiDartBuildInfo();
  if (version != expectedAbiVersion) {
    throw OpenTuiAbiMismatchException(...);
  }
  symbols.resolveRequiredSymbols();
}
```

`resolveRequiredSymbols()` resolves the complete canonical inventory without
creating a renderer, allocating a TextBuffer, mutating terminal state, or
calling the error channel. The dynamic development override uses named
`DynamicLibrary` lookups; the bundled code asset uses exactly typed
`Native.addressOf` expressions for the same ordered names.

---

12. Native distribution review

The current distribution contract uses bundled-only Dart native-asset
loading:

- `hook/build.dart` selects the target `CodeAsset` and SHA-256 verifies the
  checked-in library before exposing it.
- A missing library or checksum mismatch fails as an incomplete or corrupt
  package.
- Manifest URLs are provenance-only metadata for maintainers to refresh the
  checked-in assets.
- `OPENTUI_LIBRARY_PATH` is the exact development override for a compatible
  custom library, not a production search path or corrupt-package remedy.
- Runtime ABI validation precedes normal renderer creation, and architecture
  guards keep the deleted multi-location locator from returning.

Commit `72657aa` superseded and removed the former manifest download and
source-build fallback; those paths remain historical context rather than the
current distribution design.

---

13. Dart best-practice review

13.1 Use class modifiers intentionally

Dart recommends class modifiers like `final`, `interface`, and `sealed` to communicate extension/implementation intent.

Recommended classification:

```dart
// User-subclassable framework base classes.
abstract class Widget {}
abstract class StatelessWidget extends Widget {}
abstract class StatefulWidget extends Widget {}
abstract class State<T extends StatefulWidget> {}
// Closed value types.
final class Size {}
final class Offset {}
final class TextEditingValue {}
final class TerminalCursor {}
// Abstract contracts.
abstract interface class Listenable {}
abstract interface class Disposable {}
abstract interface class TextInputClient {}
// Closed command hierarchies.
sealed class TuiDrawCommand {}
final class FillRectCommand extends TuiDrawCommand {}
```

Do not make everything `final`; users must subclass widgets and states. But low-level resource wrappers should generally be `final class`.

13.2 Narrow the public API

Effective Dart says public declarations are a commitment and recommends making declarations private unless they are intended public API.

P9-038 finalized a curated three-tier descendant:

```
noir.dart              ordinary application/widget API
noir_low_level.dart    advanced hosting and supported rendering protocols
noir_ffi.dart          ABI-unstable guarded raw FFI
```

The current `noir.dart` exports the ordinary authoring surface, including:

- `runTuiApp`
- Widget/State/BuildContext
- layout widgets
- text widgets
- input widgets
- focus/shortcuts/actions
- controllers and foundation values
- geometry, styling, semantic input values, and `TuiCanvas`

It does not export generated bindings. Concrete Element implementations and
the recorder/display-list/compositor backend remain private framework
implementation rather than supported surfaces.

13.3 Remove explicit `library opentui;`

`lib/noir.dart` starts with:

```dart
library opentui;
```

Effective Dart style says not to explicitly name libraries. Also, the branch's own analysis rules enable `unnecessary_library_directive`.

Use:

```dart
/// Public OpenTUI Dart framework API.
library;
```

or no directive unless library annotations/docs are needed.

13.4 Documentation exists but is often low signal

The branch enables `public_member_api_docs`. That is good for an official package, but some docs are filler:

```dart
/// Value.
final T value;
```

Reference docs should explain semantics, not just satisfy the lint.

Bad:

```dart
/// Value.
```

Good:

```dart
/// The object whose equality value is used to preserve widget identity.
```

For `ObjectKey`, after fixing semantics:

```dart
/// The object whose identity is used to preserve widget identity.
```

13.5 Analysis config is ambitious but may be noisy

The branch uses `strict-casts`, `strict-inference`, `strict-raw-types`, `public_member_api_docs`, and many style lints.

That is fine for a reference implementation, but some rules may work against maintainability:

- `prefer_expression_function_bodies`
- `cascade_invocations`
- `require_trailing_commas`
- `public_member_api_docs`

These are not bad rules, but they can create churn while the architecture is still changing. The `dcm:` section is also present, but the branch does not show a DCM dependency in `pubspec.yaml`.

Recommendation:

- Keep `strict-casts` / `strict-inference` / `strict-raw-types`.
- Keep `type_annotate_public_apis`.
- Keep `public_member_api_docs` only after public API split.
- Remove or relax purely stylistic rules during kernel refactor.
- Add DCM as a dev dependency if the `dcm` block is required.

Dart's static-analysis docs show analyzer severities can be configured in `analysis_options.yaml`, so tune rule severity intentionally instead of turning everything on globally.

---

14. Tests review

Good

The branch has a strong direction:

- golden tests
- buffer capture
- style/cursor sidecars
- input parser tests
- widget behavior tests
- integration smoke tests
- Go parity tooling

`BufferCapture` renders through real OpenTUI buffer access and captures characters, foreground/background colors, attributes, and cursor state.

`GoldenTester` supports text buffer goldens plus style and cursor sidecars.

This is good and should be kept.

Missing reference tests

Add these gates.

Widget identity

- State survives same runtimeType + same key.
- State resets when key changes.
- ValueKey uses value equality.
- ObjectKey uses identity.
- UniqueKey never matches another UniqueKey.

Inherited dependencies

- `dependOnInheritedWidgetOfExactType` registers dependency.
- `getElementForInheritedWidgetOfExactType` does not register dependency.
- `updateShouldNotify` false does not rebuild.
- Dependency removal works for null aspect.

Text Unicode

- emoji cursor movement
- CJK width
- combining mark movement
- ZWJ sequence
- selection across multi-cell graphemes
- paste multiline Unicode

Native lifecycle

- `Renderer.dispose` is idempotent.
- `TextBuffer.dispose` is idempotent.
- `RenderParagraph` records `TextLayout`; the encoder disposes transient native
  `TextBuffer` materialization.
- Renderer finalizer is not required for normal cleanup.

Pipeline

- `setState` schedules one frame.
- Multiple `setState` calls in one microtask collapse into one frame.
- Animation frames respect target FPS.
- No active ticker means no frame loop.

Integration / end-to-end

- `runTuiApp` mounts a widget, runs one frame, and produces a captured buffer matching expectations.
- ANSI byte sequences fed into stdin reach `KeyEvent` / `MouseEvent` handlers with correct parsing, including Kitty CSI-u, SGR mouse, and bracketed paste.
- Scheduler advances frames only when a ticker or invalidation exists.
- Resize propagates from terminal to `RenderView` constraints to the next paint.

Pointer

- Pointer events provide local coordinates.
- Overlapping widgets hit topmost/last-painted target.
- ScrollBox receives wheel only when hit.
- Select click uses local hit test, not absolute tree walk.

Native assets

- `hook/build.dart` emits correct `CodeAsset`.
- ABI mismatch throws clear error.
- `OPENTUI_LIBRARY_PATH` override works.
- Hook-aware AOT CLI bundle (`dart build cli`) includes and loads the bundled
  native library.

---

15. Reference implementation plan

Phase 0 — Blocker fixes

Do these first.

1. Restore/remove `raw_keyboard_listener` export.
2. Fix `ObjectKey` identity equality.
3. Fix `InheritedElement.removeDependent` null-aspect bug.
4. Fix `TextInput` obscureText storage.
5. Remove direct `RenderParagraph` TextBuffer ownership; compositor/encoder
   owns any transient native materialization.
6. Make `Buffer.clipped` share invalidation with parent Buffer.
7. Remove scratch Renderer creation from clipped TextBuffer paint.
8. Add regression tests for all of the above.

Acceptance:

- `dart analyze` passes.
- `dart test` passes.
- No missing export.
- No semantic bug remains untested.

---

Phase 1 — Public API split

DONE (2026-05-19) — see Execution status above. The three-barrel target
landed with same-session closeout.

Create:

```
lib/noir.dart
lib/noir_low_level.dart
lib/noir_ffi.dart
```

Rules:

- `noir.dart` does not export generated bindings.
- `noir_ffi.dart` is explicitly ABI-unstable.
- Low-level renderer/buffer API is separated from widget API.

Acceptance:

- Examples import only `package:noir/noir.dart` unless intentionally low-level.
- Generated bindings are not part of main public API.

---

Phase 2 — Foundation

Split into Phase 2A (listenables foundation, DONE 2026-05-19) and Phase 2B
(controllers + text editing, DONE 2026-05-19). See the orchestration plan for
the split rationale.

Add:

- `Listenable`
- `ChangeNotifier`
- `ValueNotifier`
- `Disposable`
- `TextEditingValue`
- `TextEditingController`
- `TextRange`
- `TextSelection`

Refactor:

- `ScrollController extends ChangeNotifier`
- `FocusNode extends ChangeNotifier` or uses common listener primitive
- `AnimationController` uses common listener primitive
- `TextInput`/`TextArea` become controller-driven

Acceptance:

- `TextInput` controller works.
- Programmatic text updates repaint.
- User input updates controller.
- Controller disposal semantics are clear.

#### Phase 2B execution plan

**Design decisions.**

1. **Rendering highlight ranges are `TextHighlight`.**
   `lib/src/rendering/text_highlight.dart` defines a styled paint range with
   `start`, `end`, `foregroundColor`, and `backgroundColor`. The name
   `TextSelection` is reserved for the editing layer, where it matches
   Flutter's selection model. Consumers, public export, and public API
   allowlist point at `TextHighlight` with no semantic change.
2. **`TextEditingValue` uses UTF-16 offsets.** This matches Flutter. Grapheme
   aware navigation lives in `TextEditingController` helpers and widget key
   handlers until Phase 5 introduces `TextIndexMap`.
3. **Widget migration is hybrid.** `TextInput` and `TextArea` accept an
   optional controller. If absent, they create and dispose an internal
   controller. `onChanged` remains a simple-case callback and is not a
   backwards-compat shim. Supplying both `controller` and `value` is an
   assertion failure.

**Sub-task breakdown.**

| ID | Task | Files | Depends on |
|---|---|---|---|
| 2B.1 | Establish rendering `TextHighlight` naming | `lib/src/rendering/text_highlight.dart`; consumers; `lib/noir.dart`; `test/architecture/public_api_test.dart` | - |
| 2B.2 | Add `TextRange` and editing `TextSelection` | `lib/src/foundation/text_range.dart`, `text_selection.dart`; exports; allowlist; foundation tests | 2B.1 |
| 2B.3 | Add `TextEditingValue` | `lib/src/foundation/text_editing_value.dart`; exports; allowlist; foundation tests | 2B.2 |
| 2B.4 | Add `TextEditingController` | `lib/src/foundation/text_editing_controller.dart`; exports; allowlist; controller tests | 2B.3 |
| 2B.5 | Migrate `TextInput` to controller-driven editing | `lib/src/widgets/input.dart`; widget tests | 2B.4 |
| 2B.6 | Migrate `TextArea` to controller-driven editing | `lib/src/widgets/text_area.dart`; widget tests | 2B.4 |
| 2B.7 | Delete the text-editing bridge | remove the deleted bridge file; remove exports and remaining imports | 2B.5 + 2B.6 |

**Mid-phase verification gate.** Before migrating widgets:

- `dart test test/foundation/`
- `dart test test/architecture/public_api_test.dart`
- Confirm the low-level barrel baseline did not grow; foundation primitives
  export from `lib/noir.dart`, not `lib/noir_low_level.dart`.

**End-of-phase audit gate.**

- All seven sub-tasks landed.
- Grep for the deleted text-editing bridge class name returns zero hits in
  `lib`, `test`, `example`, and `bin`.
- `lib/noir.dart` exports `TextRange`, editing `TextSelection`,
  `TextEditingValue`, and `TextEditingController`; it no longer exports
  the deleted bridge.
- `dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/`
  passes.
- `dart analyze --fatal-infos` passes.
- `dart test test/architecture/` passes.
- `dart test` passes.

---

Phase 3 — Kernel split

Add the internal/advanced lifecycle kernel:

- `TuiBinding`
- `TerminalSession`
- `SchedulerBinding`
- `PipelineOwner`
- `RenderView`
- `InputDispatcher`
- public `runTuiApp` returning the owning `TuiApp` facade

Refactor `TuiApp` into the only ordinary-application lifecycle handle.

Acceptance:

- `runTuiApp` synchronously mounts and returns the high-level owning facade.
- Headless mode reports itself and owns no terminal renderer.
- Signal cleanup still works.
- Resize updates MediaQuery.
- Animation does not busy-loop.
- App/session `Renderer` creation goes through `TerminalSession`; the
  `Buffer` scratch-renderer path remains explicitly deferred to Phase 4.

---

Phase 4 — Display-list painting

Replace the deleted Buffer-based render-object paint contract with:

```dart
void paint(PaintingContext context, Offset offset);
```

Expose `PaintingContext` to supported custom render objects and the
non-constructible `TuiCanvas` paint vocabulary to application decorations.
Keep the recorder, display list, command hierarchy, encoder, and compositor
private to the framework.

Acceptance:

- Render objects no longer import `core/buffer.dart`.
- Only compositor/backend imports `Buffer`.
- Existing goldens pass.
- Clipping no longer requires scratch renderer.

---

Phase 5 — Text system

Add:

- `TextSpan`
- `RichText`
- `TextLayout`
- `TextIndexMap`
- `TextLayoutEngine`
- `PersistentUtf8Text`

Refactor:

- `RenderParagraph` uses `TextLayout`.
- `TextInput`/`TextArea` use `TextIndexMap`.
- Selection/cursor movement are grapheme/cell-correct.

Acceptance:

- Emoji, CJK, combining marks, and multiline selection tests pass.
- No visual text logic uses `String.length` or `text[i]`.

---

Phase 6 — Input semantics

Add:

- `LogicalKeyboardKey`
- `ShortcutActivator`
- `Shortcuts`
- `Actions`
- `Intent`
- `Action`
- `FocusTraversalPolicy`

Refactor:

- `Select` uses `MoveSelection` intents.
- `TextInput` / `TextArea` use `TextInputConnection`.
- Tab / Shift+Tab use focus traversal.

Acceptance:

- Widgets no longer hardcode all key strings.
- Raw key parsing stays only in input driver/low-level layer.

---

Phase 7 — Render-tree hit testing

Add:

- `HitTestResult`
- `HitTestEntry`
- `HitTestTarget`
- `PointerRouter`

Refactor:

- `PointerListener` uses render-tree hit testing.
- `Select` no longer walks element tree manually.
- `ScrollBox` wheel events use local hit result.

Acceptance:

- Overlapping pointer targets route correctly.
- Pointer local coordinates are tested.
- Native hit grid is optional optimization only.

---

Phase 8 — Native assets

The landed Phase 8 contract uses bundled-only native-asset selection.

Add:

- `hook/build.dart`
- native artifact manifest
- SHA-256 verification
- `CodeAsset` output
- native-assets runtime binding strategy
- ABI validation
- `OPENTUI_LIBRARY_PATH` as the exact development override
- architecture guard deleting the old locator/search path

Acceptance:

- The hook selects the bundled target without manual native setup.
- A missing library or checksum mismatch fails loudly as an incomplete or
  corrupt package.
- Hook-aware AOT CLI bundle (`dart build cli`) can load the bundled native
  library.
- ABI mismatch error is clear.
- The old locator/search path is guarded against reintroduction.

Commit `72657aa` superseded and removed the historical manifest download and
source-build fallback from the hook.

---

Phase 9 — Post-v1 whole-repository review

Phase 9 is active and tracked in
[`tasks/phase-9-post-v1-reference-review.md`](./phase-9-post-v1-reference-review.md).
It audits the changed post-v1 tree through an evidence-led finding loop:
required Noir-local work must land, while findings that can only be corrected
by changing the pinned read-only OpenTUI dependency remain visible,
nonblocking `read-only-upstream` limitations. Optional performance or
restricted terminal evidence must not masquerade as core completion. The
separate parity/harness roadmap remains owned by
[`tasks/plan.md`](./plan.md). Current operation authorization comes from
`AGENTS.md`; ordinary hermetic checks are mandatory. OpenTUI source, gitlink,
ABI, binary, manifest, and workflow mutations are outside this program rather
than a future Phase 9 execution lane.

---

16. Final acceptance gate

The v1 final acceptance gate is tracked in
[`tasks/final-acceptance.md`](./final-acceptance.md), which is complete and
records the tagged `reference-implementation-v1` checklist result.
Current-tree acceptance after the substantial post-v1 changes is owned by the
active Phase 9 tracker. Keep future cleanup notes in the active phase or a new
phase file rather than reintroducing a stale unchecked checklist here.

---

Final recommendation

Keep the branch, but do not keep scaling it in its current shape.

The best path is:

1. Fix P0 bugs.
2. Split public API.
3. Add foundation/controller primitives.
4. Split `TuiApp` into `TuiBinding` + owners.
5. Introduce display-list painting.
6. Move OpenTUI `Buffer` usage into compositor only.
7. Fix Unicode/text editing properly.
8. Add native assets.
9. Then resume widget parity.

This branch has the right ambition and many useful pieces. The reference implementation should preserve those pieces but enforce this invariant:

> Widgets declare.
> Elements preserve identity.
> RenderObjects layout and record paint.
> Compositor talks to OpenTUI.
> Native layer owns FFI, memory, ABI, and binaries.

That is the architecture I would standardize around.
