# Noir Examples

These examples ship with Noir and use its supported package APIs. Run the
commands below from the package source directory, or adapt the same patterns in
your own application.

Run an example from the repository root:

```bash
dart run example/main.dart
```

## Example Catalog

| Example | Highlights |
| ------- | ---------- |
| `dart run example/main.dart` | Canonical entry point — minimal Flutter-like terminal app. |
| `dart run example/hello.dart` | Minimal renderer + widget pipeline smoke test. |
| `dart run example/counter.dart` | Flutter-inspired full-screen `setState` counter with a flat app bar, centered body, solid 7×3 action button, and Up/Down, `+`/`-`, Enter/Space, and click controls. |
| `dart run example/layout_basics.dart` | Basic `Container`, `Row`, `Column`, spacing, and flex usage. |
| `dart run example/layout_demo.dart` | Richer flex, alignment, decoration, and layout combinations. |
| `dart run example/image_demo.dart` | Embedded RGBA image sizing and deterministic drive-mode block fallback without network state. |
| `dart run example/parity_components_demo.dart` | `Stack`, `Positioned`, `Wrap`, `TabSelect`, `AsciiFont`, `Slider`, `TextTable`, `CodeView`, `DiffView`, and `MarkdownView` in one interactive app. |
| `dart run example/focus_form.dart` | Focus manager, keyboard routing, and shared input handling. |
| `dart run example/chat_demo.dart` | Chat-style scrollback, text input submit, async reply state, and loading animation. |
| `dart run example/inherited_example.dart` | Inherited dependency registration and rebuild propagation. |
| `dart run example/theme_demo.dart` | `Theme`/`ThemeData` token palette with `t` to swap presets across the whole subtree. |
| `dart run example/framework_primitives.dart` | `ValueNotifier`, `Shortcuts`/`Actions`, `GlobalKey`, styled `TextSpan`s, and localized pointer activation. |
| `dart run example/bindings_validation.dart` | Interactive alternate-screen validation of advanced renderer/buffer APIs and ABI-unstable FFI values; requires a terminal at least 120x40. |
| `dart run example/pulse_animation.dart` | `AnimationController`, ticker scheduling, and frame-driven updates. |
| `dart run example/like_reactor.dart` | Interactive `AnimationController` particle reactor with overlapping keyboard and mouse-triggered heart bursts. |
| `dart run example/select_demo.dart` | `Select` option list with keyboard and mouse selection. |
| `dart run example/scrollbox_demo.dart` | `ScrollBox` viewport clipping, scrollbar, and wheel/keyboard scrolling. |
| `dart run example/components_demo.dart` | `Checkbox`, `Switch`, `Button`, `Divider`, `ProgressBar`, `Spinner`, and `Badge` on one screen, with Tab traversal and `s` to stop the spinner. |
| `dart run example/data_table_demo.dart` | `DataTable` with fixed and flex columns, a windowed body, keyboard selection, and click-to-sort headers. |
| `dart run example/listview_demo.dart` | Windowed `ListView` in both modes — selectable and plain scroll — over 500 rows, with live builder-call counters. |
| `dart run example/textarea_demo.dart` | Multi-line `TextArea` editing with portable Ctrl+D submission. |
| `dart run example/widgets_tour.dart` | Combined Select, ScrollBox, and TextArea tour with Ctrl+D submission. |

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
  components, theme, and framework-primitives examples also accept `q`. Chat and TextArea accept
  `Esc`. The widget tour accepts both: `Esc` always, and `q` only while the
  TextArea is not focused. The inherited example uses `t` to switch palettes.
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
