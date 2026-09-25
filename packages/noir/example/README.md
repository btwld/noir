# Noir examples

These examples ship with Noir and use its supported package APIs. Run them
from `packages/noir/` in a repository checkout:

```sh
dart run example/main.dart
```

Start with `main`, `counter`, `layout_basics`, or `components_demo`, then pick
the example closest to the behavior you need. Complex interactive entrypoints
describe their keybindings and special requirements in the file header.

## Start here

| Run | Learn |
| --- | --- |
| `dart run example/main.dart` | The canonical minimal application entrypoint. |
| `dart run example/hello.dart` | A small stateless widget tree with shared example chrome. |
| `dart run example/counter.dart` | Stateful updates through keyboard and pointer activation. |

## Tutorial checkpoints

`tutorials/first_app/` holds the two checkpoints of the
[first-app tutorial](https://github.com/btwld/noir/blob/main/website/src/content/docs/getting-started.mdx):
`step_01.dart` prints `Count:`, and `step_02.dart` is the same file after the
label edit. The published documentation captures its frames from these exact
files, so the code a reader copies and the output they see always agree.

```sh
dart run example/tutorials/first_app/step_01.dart
```

## Hooks and Signals companion

These examples live in the optional `noir_signals` package and are available
from a repository checkout. Run `dart pub get` at the repository root first.
Browse their [example directory](https://github.com/btwld/noir/tree/main/packages/noir_signals/example)
for source files and commands from the companion directory.
Follow the [task-list walkthrough](https://github.com/btwld/noir/blob/main/packages/noir_signals/doc/getting-started.md)
for step-by-step code changes, screenshots, and complete runnable checkpoints.

| Source | Run from the repository root | Learn |
| --- | --- | --- |
| [Counter](https://github.com/btwld/noir/blob/main/packages/noir_signals/example/counter.dart) | `dart run packages/noir_signals/example/counter.dart` | `SignalWidget` and `useState` for local state. |
| [Task list](https://github.com/btwld/noir/blob/main/packages/noir_signals/example/task_list.dart) | `dart run packages/noir_signals/example/task_list.dart` | `useSignal`, `useComputed`, retained input, and completion/filter actions. |
| [File search](https://github.com/btwld/noir/blob/main/packages/noir_signals/example/file_search.dart) | `dart run packages/noir_signals/example/file_search.dart` | An owned model observed with `SignalValueBuilder`. |

## Core concepts

| Run | Learn |
| --- | --- |
| `dart run example/layout_basics.dart` | `Container`, `Row`, `Column`, spacing, and flex. |
| `dart run example/layout_demo.dart` | Alignment and nested flex layouts in a scrollable specimen. |
| `dart run example/inherited_example.dart` | Inherited dependencies and visible rebuild propagation. |
| `dart run example/theme_demo.dart` | Whole-subtree `ThemeData` changes. |
| `dart run example/framework_primitives.dart` | Notifiers, shortcuts/actions, `GlobalKey`, rich text, and local pointer coordinates. |
| `dart run example/image_demo.dart` | Embedded RGBA sizing and deterministic drive-mode fallback. |

## Controls and data

| Run | Learn |
| --- | --- |
| `dart run example/components_demo.dart` | Public controls and composed component states under two palettes. |
| `dart run example/focus_form.dart` | Structural focus cues, validated input, submission, and pointer activation. |
| `dart run example/select_demo.dart` | Keyboard and pointer selection. |
| `dart run example/scrollbox_demo.dart` | Viewport clipping, scrollbars, paging, and wheel input. |
| `dart run example/listview_demo.dart` | Selectable and plain virtual lists over 500 rows. |
| `dart run example/data_table_demo.dart` | Windowed rows, selection, and sorting. |
| `dart run example/textarea_demo.dart` | Multi-line editing and portable Ctrl+D submission. |
| `dart run example/widgets_tour.dart` | Select, ScrollBox, and TextArea in one interaction flow. |
| `dart run example/dialog_demo.dart` | A focus-trapping `Modal` confirmation flow with focus restoration. |
| `dart run example/autocomplete_demo.dart` | Controlled autocomplete with debounce and stale-response protection. |
| `dart run example/file_picker_demo.dart` | A `Modal` and `TreeView` over application-owned file data. |

## Complete apps

| Run | Learn |
| --- | --- |
| `dart run example/chat_demo.dart` | A deterministic agent transcript plus an explicit, isolated Claude CLI mode. |
| `dart run example/pub_search.dart` | A live pub.dev browser with completion, filters, paging, and package detail; requires network access. |

## Motion

| Run | Learn |
| --- | --- |
| `dart run example/pulse_animation.dart` | Fractional-cell progress and a pauseable reversing `AnimationController`. |
| `dart run example/like_reactor.dart` | Deterministic particles, overlapping bursts, and bounded animation lifecycle. |

## Advanced and reference

| Run | Learn |
| --- | --- |
| `dart run example/parity_components_demo.dart` | A dense inventory of document, selection, table, and parity components. |
| `dart run example/bindings_validation.dart` | Renderer, buffer, and ABI-unstable FFI validation; requires a real terminal at least 120×40. |

## Drive mode

Interactive examples put stable `ValueKey<String>` values on controls a
driver can click or await. A headless session against the counter can use:

```text
tree 10
find key increment
click key increment
capture --plain
quit
```

`tree` is depth-limited unless you pass a larger depth; `find` searches the
whole snapshot. Put keys on a control or small wrapper, not on a layout box.
Type locators match `runtimeType` exactly (`Select<String>`, not
`Select`). Text locators read `Text` and `RichText` source rather than painted
Select or table glyphs.

`example/bindings_validation.dart` needs a real terminal stdin lease and exits
with code 70 under drive mode.

Tree inspection is part of the supported advanced API:

```dart
import 'package:noir/noir_low_level.dart';

final lines = WidgetInspectorService.instance.describeTree();
```

## Running notes

- Wide terminals reduce clipping in the layout demos. Chat, the focus form,
  Like Reactor, and the widget tour also need more than a 40×12 pane to show
  every region.
- Dart may print `Running build hooks...` before a run. On Dart 3.11 or later,
  `dart run --verbosity=error example/counter.dart` hides routine status while
  keeping errors visible. Dart 3.10 may still print build-hook progress despite
  this flag. This still runs and verifies the native asset whenever Dart invalidates the
  build-hook cache.
- Examples exit through `TuiApp.exit(context)` or Noir's default Ctrl+C
  handling; they do not call `dart:io`'s `exit`.
- `runTuiApp(..., headless: true)` returns a `TuiApp` whose `isHeadless` is
  `true` and creates no owned terminal renderer. Renderer-backed mouse and
  Kitty keyboard controls are unavailable in that mode.

For installation, lifecycle guidance, supported input, native targets, and
known limitations, see the [package README](../README.md).
