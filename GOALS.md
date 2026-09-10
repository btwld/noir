# Noir quality standard

This document is the durable standard for Noir. The current candidate is
described at the top of [`CHANGELOG.md`](CHANGELOG.md); open work lives in
GitHub issues and pull requests.

## Architectural invariant

> Widgets declare. Elements preserve identity. RenderObjects layout and record
> paint. The compositor talks to OpenTUI. The native layer owns FFI, memory,
> ABI, and binaries.

A change is reference-quality only when it preserves that boundary.

## Core-framework 1.0 scope

Core 1.0 covers:

- Widget, Element, State, and RenderObject lifecycle and reconciliation.
- Integer-cell layout, display-list painting, text, focus, and input.
- Explicitly owned terminal images and idiomatic Dart reference components
  that preserve the framework's retained render pipeline.
- Inherited dependencies, animation, and application lifecycle.
- The documented high-level, low-level, and guarded raw FFI package surfaces,
  plus the optional `noir_signals` companion package for hooks and Signals.
- Bundled native loading for the supported desktop targets.

Capability parity does not mean adopting OpenTUI React's component or hook
implementation, or its internal renderable hierarchy. Noir's Dart-native
opt-in hooks remain a separate supported surface in the `noir_signals`
companion package. Full-root layout and paint
recording on dirty frames and grapheme-run encoding during display-list
composition are accepted initial costs, not performance guarantees.
Optimization work begins only after retained, reproducible measurement breaks
an explicit workload budget.

## Quality requirements

- Semantics follow Flutter where Noir intentionally mirrors Flutter and the
  pinned OpenTUI React/core sources where rendering or input behavior is
  concerned.
- Native ownership is explicit. Every native resource has a deterministic,
  idempotent cleanup path; finalizers are fallback protection only.
- Visual text logic is grapheme- and cell-aware. It does not index display
  text with `String.length` or `text[i]`.
- Public validation works in release mode. Assertions are not the only guard
  for externally supplied values.
- Public value objects snapshot mutable inputs when mutation would break
  equality, hashing, layout, or invalidation.
- Tests assert promised results, ordering, and cleanup—not merely that a call
  returns.
- Documentation examples compile against the current API and state limitations
  without promises the implementation does not keep.
- No stale branch, commit, pull-request, tag, package-publication, or phase
  history is presented as current repository state.
- Shipped widgets and example chrome obey the terminal component language
  below. A screen that looks like a GUI card forced onto a grid is wrong
  even if the tests pass.

## Terminal component language

The terminal is a cell grid. A box-drawing glyph occupies one full cell and
sits in the visual center of that cell, so every rule already shows about
half a cell of air on each side. That air is optical. It is not missing
padding, and it is not a vertical-alignment bug.

### Cell rules

1. The unit is one cell. Sizes, gaps, and insets are integers.
2. The border cell is the inset. Content starts on the first inner row and
   column. `Container` maxes explicit padding with border thickness.
3. A region's name lives on the top edge (`Border.title`). An inner title
   `Text` is a second header.
4. Content is top-start. Unused rows mean the box is too tall, not that
   the stack should be centered.
5. Height is chrome plus content, or a viewport. Leftover empty rows
   inside a fixed card are a composition error.
6. One surface per region. Do not wrap a self-painting widget in a second
   filled bordered box.
7. Chrome uses theme tokens. Content color stays a literal only when
   color is the subject.
8. 80x24 is the floor. Extra cells stay empty at the trailing edge.

### Reference card

Hello is the reference. Title on the border, body on the next row,
shrink-wrapped:

```
+-- Layout --------------------------+ +-- State ---------------------------+
|Row, Column, Container, Expanded    | |StatelessWidget and StatefulWidget  |
+------------------------------------+ +------------------------------------+
```

### Component bar

| Widget | Terminal expectation |
|---|---|
| `Container` / `DecoratedBox` / `Padding` | Integer insets. Border + padding max, they do not stack. |
| `Row` / `Column` | `spacing` is whole cells between children only. Start on the main axis. |
| `Expanded` / `Flexible` / `SizedBox` / `Align` / `ConstrainedBox` | Cell extents. Do not vertically center card copy. |
| `Stack` / `Positioned` / `Wrap` | Whole-cell overlays and wrapping runs. Clip stack overflow by default. |
| `Text` / `RichText` | Grapheme- and cell-aware. Clamp overflow in tables and one-line fields. |
| `AsciiFont` | Natural multi-row glyph box with seven generated treatments of Noir's built-in alphabet. |
| `Theme` / `ThemeData` | Flat tokens. `dark` is the unthemed look. |
| `Panel` | One bordered region. Title on `Border.title`; shrink-wrap unless `width` / `height` define a viewport. `focused` adds accent chrome and a structural marker but owns no focus. |
| `Modal` | Unstyled centered behavior boundary. Trap Tab focus, restore the opener, block outside pointers, and use `Panel` for visible chrome. |
| `Divider` | One-cell band of `ThemeData.border`. Specimen, not a page rule. |
| `Badge` | One row. Horizontal pad 1. |
| `ProgressBar` | One row. Eighth-cell steps. |
| `Spinner` | One cell. Unmount to stop. |
| `Button` | One row, fill not border. Horizontal pad 1. |
| `Checkbox` / `Switch` | One row. Narrow ASCII glyphs. |
| `TextInput` | One row. No chrome pad. |
| `Autocomplete` | Controlled field plus one attached state or option surface. Async search and option data stay caller-owned. |
| `TextArea` | `height` is exact rows unless `maxHeight` enables bounded visual-row growth; wrapping is opt-in. |
| `Select` | `height` is visible options. Highlight mutes when unfocused. |
| `TabSelect` | Fixed-width or label-sized horizontal tabs with an optional underline and description row. |
| `Slider` | One-cell track on its cross axis; value is caller-controlled. |
| `ListView` | Same highlight rules. `selectedIndex == null` is plain scroll. |
| `TreeView` | Virtualized visible preorder over stable caller IDs. The controller owns expansion/selection; the item builder owns label overflow. |
| `DataTable` | Header is one row; body is a `ListView`. No spacer under the header. |
| `TextTable` | Finite rich grid. `DataTable` remains the windowed interactive table. |
| `CodeView` / `DiffView` / `MarkdownView` | Bounded selectable viewports; copy only on explicit Ctrl+C. |
| `ScrollBox` | One overflowing child. Scrollbar in the last column. Chronological tail following is controller-owned and opt-in. |
| `Focus` / `FocusScope` | Focused lists use `selectedBackground`. Accent border marks keyboard ownership. |
| `PointerListener` | `MouseEvent.localPosition` only. |
| Example `DemoScaffold` | Surface fills the terminal. Title inset 2, 1. Not a public `Scaffold`. |

Exempt: `counter`, `like_reactor`, `inherited_example`, `bindings_validation`.
`layout_*` and `chat_demo` keep their own frames.

### Catalog pass

Apply the bar to every cataloged example. Framework widgets that already
match stay. Example chrome stays example-local.

| Piece | Action |
|---|---|
| `DemoScaffold` | Keep application-specific page chrome example-local. |
| `Panel` | Use the public themed region; title on `Border.title`, shrink-wrapped unless it contains a viewport. |
| `Modal` | `dialog_demo` and `file_picker_demo` use the public behavior boundary; `components_demo` shows it with `Panel` chrome under both palettes. |
| `hello` | Reference two-up. |
| `Button` / `Badge` / `Checkbox` / `Switch` / `ProgressBar` / `Spinner` | Present in `components_demo` inside titled panels. |
| `Divider` | One specimen rule inside the controls panel. |
| `TextInput` | `focus_form` fields are titled panels of height 3. |
| `Autocomplete` | `autocomplete_demo` composes the public controlled field/list behavior with example-owned debounce and stale-response protection; `components_demo` shows ready/loading/empty/error states under both palettes. |
| `Select` | `select_demo` and `widgets_tour`: titled panel. |
| `ListView` | `listview_demo`: one titled panel per list. |
| `TreeView` | `file_picker_demo` composes the public generic tree with application-owned paths, preview copy, and Open behavior; `components_demo` shows collapsed/expanded/selected states under both palettes. |
| `ScrollBox` | `scrollbox_demo` / `widgets_tour`: titled viewport. |
| `TextArea` | `textarea_demo` / `widgets_tour`: titled viewport. |
| Agent transcript | `chat_demo`: offline replay and an opt-in bounded Claude CLI text/tool subset feed the same semantic reducer; one continuous, full-page follow-tail surface owns header, transcript, composer, and compact tool presentation, while public `Modal`/`TreeView` compositions own decisions and pickers. Semantically typed diff previews remain explicit. Replay stays canonical for approvals, questions, saved-session catalogs, and deterministic checks. |
| `DataTable` | No header/body `Divider`. `data_table_demo` in a titled panel. |
| Phase-2 parity components | `parity_components_demo` demonstrates every new non-image component. |
| `Theme` | `theme_demo` and the component sheet re-skin public `Panel`, `Modal`, `Autocomplete`, and `TreeView` compositions without component sub-themes. |
| `Focus` / `PointerListener` | `focus_form`. |
| `framework_primitives` | Scaffold only. |
| Exempt | listed above. |

## Dependency boundary

`external/opentui` and the six checked-in native libraries are read-only under
ordinary Noir work. Verification is allowed; edits, rebuilds, artifact
replacement, gitlink movement, ABI changes, and provenance changes require a
separate explicit dependency-strategy decision.

The pinned native implementation has a known exact-cursor restoration
limitation on an observed macOS/iTerm path. Noir must still perform
exception-safe best-effort cleanup and keep the limitation visible; it must not
duplicate native ownership with an ANSI save-slot workaround.

## Release gates

### Alpha

An alpha may ship when:

- all documented alpha blockers are closed by focused regression tests;
- format, strict analysis, architecture tests, and the ordinary suite pass;
- native artifacts match the checked-in manifest;
- the publish archive has no warnings and contains only intentional files;
- workflows are immutable-reference pinned and pass static linting;
- README, changelog, version, platform floor, and install instructions agree;
- unresolved native or stable-quality risks are explicit.

An alpha is an API and integration preview. It does not promise production
stability or full platform acceptance.

### Beta

A beta additionally requires closure of correctness findings designated for
beta, current candidate testing on supported Linux, macOS, and Windows
targets, and an explicit decision on any native artifact provenance issue.

### Stable

Stable 1.0 additionally requires closure or deliberate API disposition of
stable-contract findings, beta soak evidence, analysis of the exact publish
archive in a clean consumer, and an explicit decision on the pinned native
terminal-restoration limitation.

Passing tests alone does not advance the release level. The release-readiness
record must link the evidence and list every accepted residual risk.

## Verification principles

- Fitness functions enforce mechanical boundaries; review verifies semantics.
- Tests are added before production fixes for behavior changes.
- A failure path must preserve the primary error while attempting all cleanup.
- No backwards-compatibility shim is added during prerelease cleanup.
- A release, tag, publication, manually dispatched workflow, or native artifact
  change is a separate authorized operation. Automatic push/pull-request CI is
  ordinary verification.
