# Noir

Noir is a Flutter-like reactive terminal UI framework for Dart, powered by
OpenTUI. It combines declarative widgets, integer-cell layout, stateful
rebuilds, focus and input routing, animation, and bundled native rendering in
one package.

- Build interfaces with `StatelessWidget`, `StatefulWidget`, `BuildContext`,
  and `setState`.
- Compose layouts with `Row`, `Column`, `Container`, `Padding`, `SizedBox`,
  `Align`, `Flexible`, and `Expanded`.
- Handle text editing, selection, scrolling, keyboard focus, mouse input, and
  application-wide shortcuts.
- Drop to supported renderer, buffer, or raw FFI APIs when an application
  needs more control.

## Quick Start

Add Noir to a Dart application:

```bash
dart pub add noir
```

Import `package:noir/noir.dart` and mount a widget tree with `runTuiApp`:

```dart
import 'package:noir/noir.dart';

void main() => runTuiApp(const HelloApp());

class HelloApp extends StatelessWidget {
  const HelloApp({super.key});

  @override
  Widget build(BuildContext context) => Container(
    color: Color.rgb(0.05, 0.06, 0.1),
    padding: const EdgeInsets.all(2),
    child: const Column(
      spacing: 1,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Noir',
          style: TextStyle(
            color: Color.yellow,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text('Flutter-like widgets for terminal apps.'),
        Text('Press Ctrl+C to exit.'),
      ],
    ),
  );
}
```

The complete version is available in [the hello example](example/hello.dart).

Stateful widgets persist a `State` object between supported rebuilds. Call
`setState` after changing local state, and check `mounted` before updating from
an asynchronous callback:

```dart
import 'package:noir/noir.dart';

void main() => runTuiApp(const CounterApp());

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _count++);
    });
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(1),
    child: Column(
      spacing: 1,
      children: [
        const Text('Counter', style: TextStyle(color: Color.green)),
        Text('Count: $_count'),
      ],
    ),
  );
}
```

See [the counter example](example/counter.dart) for the package version.

## Application Lifecycle and API Tiers

`runTuiApp` mounts the root widget and returns a `TuiApp` handle synchronously.
Keep that handle when you register application-wide input or exit
programmatically. `onKey`, `onMouse`, and `onPaste` install app-priority
handlers, and each returns an idempotent canceler.

`TuiApp.dispose()` is idempotent. It cancels every still-owned registration
before disposing the mounted app, input modes, and renderer resources. Always
dispose the handle before a programmatic process exit. The default POSIX
signal handling also performs cleanup for SIGINT, SIGTERM, and SIGHUP.

`headless: true` creates no owned terminal renderer and is exposed through
`TuiApp.isHeadless`. Renderer-backed mouse and Kitty keyboard mode controls
are unavailable in that mode.

Noir has three supported import tiers:

- `package:noir/noir.dart` — ordinary application and widget authoring.
- `package:noir/noir_low_level.dart` — advanced hosting, renderer/buffer
  access, and supported custom rendering.
- `package:noir/noir_ffi.dart` — ABI-unstable raw FFI access.

Concrete Element implementations and the recorder/display-list/compositor
backend remain framework-owned; they are not supported package surfaces.

## Example Apps

- [Hello](example/hello.dart) — a minimal stateless application.
- [Counter](example/counter.dart) — stateful rebuilds with `setState`.
- [Layout basics](example/layout_basics.dart) — core layout and flex usage.
- [Layout demo](example/layout_demo.dart) — alignment, decoration, and richer
  flex combinations.
- [Inherited state](example/inherited_example.dart) — inherited dependencies
  and rebuild propagation.
- [Focus form](example/focus_form.dart) — focus management and text input.
- [Select](example/select_demo.dart) — keyboard and mouse option selection.
- [Scroll box](example/scrollbox_demo.dart) — clipped scrolling and
  scrollbars.
- [Text area](example/textarea_demo.dart) — multiline editing and submission.
- [Widgets tour](example/widgets_tour.dart) — the interactive widget set.
- [Chat demo](example/chat_demo.dart) — scrollback, input, asynchronous state,
  and animation.
- [Pulse animation](example/pulse_animation.dart) — `AnimationController` and
  ticker-driven updates.
- [Bindings validation](example/bindings_validation.dart) — interactive
  advanced renderer/buffer and ABI-unstable FFI validation in a terminal at
  least 120×40 cells.

The [example guide](example/README.md) includes the command for every app.

## Supported Keyboard and Mouse Input

| Input | Result |
| --- | --- |
| Printable ASCII / UTF-8 | `KeyEvent` with the typed character |
| Backspace (BS / DEL) | `LogicalKeyboardKey.backspace` |
| Tab | `LogicalKeyboardKey.tab` |
| Enter (CR / LF) | `LogicalKeyboardKey.enter` |
| Escape | `LogicalKeyboardKey.escape` |
| Ctrl + letter | `KeyEvent` with `KeyModifiers.ctrl` |
| Arrow keys | `arrowUp`, `arrowDown`, `arrowLeft`, `arrowRight` |
| Home / End | `home`, `end` |
| Delete / PageUp / PageDown | `delete`, `pageUp`, `pageDown` |
| Function keys | `f1`–`f12` |
| Mouse SGR | `MouseEvent` with type, button, cell position, modifiers, and directional scroll magnitude |
| Bracketed paste | one `PasteEvent` per block through `app.onPaste` |
| Kitty CSI-u | full Kitty modifiers after `app.enableKittyKeyboard()` |

SIGWINCH resizes the terminal buffer and lays out the widget tree again.

## Native Libraries

Noir ships bundled native libraries for supported desktop targets. The build
hook selects and SHA-256 verifies the bundled target before exposing it as a
Dart native asset. If a library is missing or its checksum mismatches, the
package is incomplete or corrupt and the build fails.

| Operating system | Architectures |
| --- | --- |
| macOS | `x64`, `arm64` |
| Linux | `x64`, `arm64` |
| Windows | `x64`, `arm64` |

Android, iOS, and web are not supported targets. See
[Third-Party Notices](THIRD_PARTY_NOTICES.md) for OpenTUI provenance and
license terms.

The URLs in `native_manifest.json` record immutable provenance for the
currently bundled artifacts. They are not an update instruction or a runtime
recovery path.

`OPENTUI_LIBRARY_PATH` is the exact development override for a compatible
custom library. It is not a search path and not a remedy for an incomplete or
corrupt package.

## Known Limitations

- Complex emoji, variation sequences, and other multi-code-point graphemes do
  not yet have exact cell-width and paint guarantees on every path. Selection
  and caret behavior inherits that limitation.
- Decorated box content can escape a clipped viewport in some overflow cases.
- Some low-level native operation failures cannot be reported precisely to
  Dart.
- On the observed macOS/iTerm path, the pinned alternate-screen lifecycle can
  return to main-screen row 1/column 1 instead of the launch cursor and
  overwrite prior shell rows. Callers must still dispose `TuiApp` so all owned
  resources and terminal modes are released.
- Interactive startup has a startup ordering window: native capability
  queries currently begin before the stdin driver acquires terminal input.
  Low-level validation reproduced the underlying canonical/echo mechanism,
  but high-level corruption has not been reproduced.
