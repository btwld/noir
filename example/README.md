# Noir Examples

These examples ship with Noir and use its supported package APIs. Run the
commands below from the package source directory, or adapt the same patterns in
your own application.

Run an example from the repository root:

```bash
dart run example/main.dart
```

For a first pass, run `main`, then `counter`, `layout_basics`,
`components_demo`, and `chat_demo`. The rest of the catalog is grouped by the
question each example answers; it is not a required sequence.

## Start here

| Run | Learn |
| --- | --- |
| `dart run example/main.dart` | The canonical minimal application entry point. |
| `dart run example/hello.dart` | The smallest stateless widget and renderer composition. |
| `dart run example/counter.dart` | Stateful updates plus keyboard and pointer activation. |
| `dart run example/hooks_counter.dart` | The same state pattern through opt-in `HookWidget` and `useState`. |

## Core concepts

| Run | Learn |
| --- | --- |
| `dart run example/layout_basics.dart` | `Container`, `Row`, `Column`, spacing, and flex. |
| `dart run example/layout_demo.dart` | A scrollable, static specimen sheet for alignment and nested flex layouts. |
| `dart run example/inherited_example.dart` | Inherited dependencies and visible rebuild propagation. |
| `dart run example/theme_demo.dart` | Whole-subtree `ThemeData` token changes; press `t` to swap presets. |
| `dart run example/framework_primitives.dart` | Notifiers, shortcuts/actions, `GlobalKey`, rich text, and local pointer coordinates. |
| `dart run example/image_demo.dart` | Embedded RGBA sizing and the deterministic drive-mode fallback. |

## Controls and data

| Run | Learn |
| --- | --- |
| `dart run example/components_demo.dart` | A two-palette sheet for `Panel`, `Modal`, `Autocomplete`, `TreeView`, Checkbox, Switch, Button, Divider, ProgressBar, Spinner, and Badge. |
| `dart run example/focus_form.dart` | Structural focus cues, validated text input, Enter submission, and a clickable Save action. |
| `dart run example/select_demo.dart` | Keyboard and pointer selection. |
| `dart run example/scrollbox_demo.dart` | Viewport clipping, scrollbars, keyboard paging, and wheel input. |
| `dart run example/listview_demo.dart` | Selectable and plain virtual lists over 500 rows. |
| `dart run example/data_table_demo.dart` | Windowed rows, selection, and keyboard or pointer sorting. |
| `dart run example/textarea_demo.dart` | Multi-line editing and portable Ctrl+D submission. |
| `dart run example/widgets_tour.dart` | Select, ScrollBox, and TextArea in one interaction flow. |
| `dart run example/dialog_demo.dart` | A public `Modal` confirmation flow with `Panel` chrome, a pointer barrier, closed-loop focus, and focus restoration. |
| `dart run example/autocomplete_demo.dart` | Public controlled `Autocomplete` behavior composed with example-owned debounce, stale-response protection, and package data. |
| `dart run example/file_picker_demo.dart` | A public `Modal` and generic `TreeView` composed with application-owned paths, preview copy, and guarded Open behavior. |

### Component sheet controls

The component sheet starts on Controls. Shift+Tab reaches the category strip;
Left/Right switches among Controls, the public `Panel` foundation states,
`Modal` behavior, and Data. Data shows ready/loading/empty/error
`Autocomplete` states beside collapsed/expanded/selected `TreeView` states.
The modal specimen demonstrates Cancel, Confirm, closed-loop Tab focus, and
blocked background pointer input. Press `Ctrl+T` to apply the alternate palette
to the same tree, `Ctrl+S` to stop or restart the spinner, and `Ctrl+Q` to quit.

## Complete apps

| Run | Learn |
| --- | --- |
| `dart run example/chat_demo.dart` | A replay-driven, continuous full-page agent transcript with streaming blocks, tools, suggestions, decisions, session/model/mode controls, and chronological tail following. |
| `dart run example/pub_search.dart` | A live pub.dev browser with completion, filters, paging, and package detail. Requires network access. |

### Agent chat controls

The chat example is deterministic and offline. Its UI consumes a
product-neutral semantic backend, so the replay backend drives the same
reducer and public Noir widget tree that any other backend would. Enter sends, a
distinguishable Ctrl+J inserts a newline, `/` filters replay commands, `@`
filters the supplied project paths, Tab accepts a suggestion, and Up/Down at an
editor boundary walk prompt history.

Shift+Tab cycles permission mode, Ctrl+M opens the model picker,
and Ctrl+R opens the `TreeView` session picker. Ctrl+O focuses the full-page
conversation scroll surface and shows its structural focus cue without moving
the viewport; PageUp/PageDown move it. The header, history, suggestions,
composer, and footer share that one tail-following page, so short conversations
stay near the terminal top and long conversations scroll as a continuous stream.
Escape or Ctrl+C interrupts active work; while idle, it exits. Permission and
question requests use a focus-trapping
`Modal` and return focus to the unchanged composer draft. The entrypoint enables Kitty keyboard
reporting so modified letter chords remain distinguishable. Edit decisions carry an explicit semantic patch, so
the approval preview and expanded tool detail reuse `DiffView`; arbitrary tool
text remains plain text and is never classified by tool-name or output
heuristics.

## Motion

| Run | Learn |
| --- | --- |
| `dart run example/pulse_animation.dart` | Fractional-cell progress and a pauseable reversing `AnimationController`. |
| `dart run example/like_reactor.dart` | Deterministic particles, overlapping bursts, and bounded animation lifecycle. |

## Advanced and reference

| Run | Learn |
| --- | --- |
| `dart run example/parity_components_demo.dart` | A dense, reference-only inventory of the phase-two component surface. Start with the focused control demos above. |
| `dart run example/bindings_validation.dart` | Advanced renderer/buffer and ABI-unstable FFI validation. Requires a real terminal at least 120×40. |

### Pub Search controls

The pub search example starts with a live search for `noir`. After three
characters, the query waits 300 ms and performs a fresh pub.dev name and topic
completion lookup; it does not retain completion results or in-flight lookups.
The live catalog returns at most twelve package names and four topics; injected
test catalogs may return more so the UI can exercise overflow. A completion
failure stays silent so typeahead never replaces search results or the search
error panel. Names and topics are suggested (topics include a package count).
Press Enter to search or inspect the highlighted package. In a result or empty
surface, Tab moves through the query, Sort, Filter, and then results when they
exist. Enter, Space, or a click on `Sort: TOP ▾` or `Filter: ANY ▾` opens a
launcher-anchored menu; `s` and `f` do the same from the result list.
Use arrows to preview a choice and Enter or a click to apply it, or Tab/Escape
to cancel. `n`/`p` move between result pages. Confirming a topic suggestion
applies that topic to the next search. In package detail, Left/Right, `1`–`4`,
or a click on a section tab switch between Overview, Versions, Dependencies,
and Health. Report section summaries and advisory details render as GitHub-
flavoured markdown inside the Health `ScrollBox`, with section chrome
separated from the report body. Up/Down, PageUp/PageDown,
Home/End, and the mouse wheel scroll the active section. `/` returns to the
query; Escape returns to results and then exits.

The executable always constructs the live `PubApiCatalog`; there is no offline
data mode. The adapter is isolated behind `PubCatalog` so tests can inject a
fake and keep async, empty, error, retry, paging, and stale-response behavior
deterministic without network access. Drive locators for the example are
`query`, `sort`, `filter`, `tabs`, and `detail`.

### Composition example controls

The dialog example opens from `Review deploy`. Tab and Shift+Tab stay inside
the confirmation while it is visible, Escape cancels, and either button or a
click completes the action. Its transparent full-terminal pointer barrier
keeps the undimmed deployment screen visible without letting it receive input.

The autocomplete example starts with the deterministic query `noi`. Type to
replace or refine the query, wait for the application-owned debounce, then Tab
into the attached suggestions. Arrows move the highlight, Enter or a click
chooses, and Escape first clears suggestions and then exits. The controller
demonstrates request generations so an older asynchronous response cannot
replace a newer query.

The file picker opens on launch with an in-memory project tree, so it never
reads the host file system. Up/Down move through visible rows, Right expands a
folder, and Left collapses it or moves to its parent. Enter toggles a folder;
Tab reaches Cancel and Open. Escape closes the picker and restores focus to
`Open a file`.

## Drive mode

Interactive examples expose stable `ValueKey<String>` values on the control a
driver would click or wait for. A headless drive session against
`example/counter.dart` can then use exact locators:

```
tree 10
find key increment
click key increment
capture --plain
quit
```

A `tree` listing is depth-limited unless you pass a larger depth; `find`
always searches the whole snapshot. Put each key on the control itself or a
small wrapper widget, not on a layout box around it. Type locators match
`runtimeType` exactly (`Select<String>`, not `Select`). Text locators read
`Text` and `RichText` source, not painted Select or table glyphs.
`example/bindings_validation.dart` needs a real terminal stdin lease and
exits 70 under drive mode.

## Tips

- Use a wide terminal for the layout demos to reduce clipping. Chat, the
  focus form, Like Reactor, and the widget tour also need more than a
  40×12 pane to show every region.
- Dart checks Noir's native-asset build hook before a run and may print
  `Running build hooks...`. To hide routine compiler/hook status while keeping
  errors visible, run `dart run --verbosity=error example/counter.dart`; this
  still runs and verifies the native asset whenever Dart invalidates the
  build-hook cache.
- `runTuiApp(..., headless: true)` returns a `TuiApp` whose `isHeadless` is
  `true` and creates no owned terminal renderer. Renderer-backed mouse and
  Kitty keyboard mode controls are unavailable in that mode.
- Every example is a one-line entry point — `void main() => runTuiApp(const
  MyApp());` — and quits by calling `TuiApp.exit(context)` from its key
  handler, so no example threads an `onQuit` callback or calls `dart:io`'s
  `exit`. Mouse reporting is requested with `runTuiApp(..., enableMouse:
  true)`.
- Examples exit with `Ctrl+C` through the default terminal-session shutdown.
  The layout, parity-components, Select, ScrollBox, ListView, DataTable,
  components, theme, and framework-primitives examples also accept `q`. Agent
  chat uses `Esc` or Ctrl+C to interrupt active work and exits on the same key
  while idle. TextArea accepts `Esc`. The widget tour accepts both: `Esc`
  always, and `q` only while the TextArea is not focused. The inherited example
  uses `t` to switch palettes.
- Quit wrappers around a real control use `Focus(canRequestFocus: false)` so
  Tab stays on the field, list, or viewport.
- `TextArea` accepts Ctrl+Enter when a terminal reports the modifier. The
  multiline examples also bind Ctrl+D so submission works in terminals that
  encode Ctrl+Enter as an ordinary Enter.

Tree inspection is an advanced-tier API:

```dart
import 'package:noir/noir_low_level.dart';

final lines = WidgetInspectorService.instance.describeTree();
```

For installation, lifecycle guidance, supported input, native targets, and
known limitations, see the [package README](../README.md).
