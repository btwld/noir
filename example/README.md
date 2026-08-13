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
| `dart run example/counter.dart` | Interactive `setState` rebuilds via Up/Down and `+`/`-`. |
| `dart run example/layout_basics.dart` | Basic `Container`, `Row`, `Column`, spacing, and flex usage. |
| `dart run example/layout_demo.dart` | Richer flex, alignment, decoration, and layout combinations. |
| `dart run example/focus_form.dart` | Focus manager, keyboard routing, and shared input handling. |
| `dart run example/chat_demo.dart` | Chat-style scrollback, text input submit, async reply state, and loading animation. |
| `dart run example/inherited_example.dart` | Inherited dependency registration and rebuild propagation. |
| `dart run example/bindings_validation.dart` | Interactive alternate-screen validation of advanced renderer/buffer APIs and ABI-unstable FFI values; requires a terminal at least 120x40. |
| `dart run example/pulse_animation.dart` | `AnimationController`, ticker scheduling, and frame-driven updates. |
| `dart run example/select_demo.dart` | `Select` option list with keyboard and mouse selection. |
| `dart run example/scrollbox_demo.dart` | `ScrollBox` viewport clipping, scrollbar, and wheel/keyboard scrolling. |
| `dart run example/textarea_demo.dart` | Multi-line `TextArea` editing with portable Ctrl+D submission. |
| `dart run example/widgets_tour.dart` | Combined Select, ScrollBox, and TextArea tour with Ctrl+D submission. |

## Tips

- Use a wide terminal for the layout demos to reduce clipping.
- `runTuiApp(..., headless: true)` returns a `TuiApp` whose `isHeadless` is
  `true` and creates no owned terminal renderer. Renderer-backed mouse and
  Kitty keyboard mode controls are unavailable in that mode.
- Examples exit with `Ctrl+C` through the default terminal-session shutdown.
  The layout examples also accept `q` through their widget-owned quit callback.
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
