# Noir

[Documentation](https://conceptadev.github.io/noir/) ·
[Examples](https://conceptadev.github.io/noir/examples/) ·
[API reference](https://pub.dev/documentation/noir/latest/)

Build terminal applications in Dart with declarative widgets and stateful
rebuilds. Noir provides a Flutter-like widget model, cell-based layout, focus,
keyboard and mouse input, and animation. OpenTUI renders the output through
bundled native libraries; Noir owns the Dart widget and resource lifecycles.

Noir is at an early 0.0.x stage. APIs and platform guarantees may change before
stable 1.0.

- Build interfaces with `StatelessWidget`, `StatefulWidget`, `BuildContext`,
  and `setState`.
- Compose layouts with `Row`, `Column`, `Container`, `Panel`, `Padding`,
  `SizedBox`, `Align`, `Flexible`, `Expanded`, `Stack`, `Positioned`, and
  `Wrap`.
- Decode and display PNG, JPEG, WebP, GIF, or raw RGBA images with terminal
  protocol negotiation and deterministic block-cell fallback.
- Handle text editing, selection, scrolling, keyboard focus, mouse input, and
  application-wide shortcuts.
- Opt into reusable widget lifecycle hooks and Signals reactive state with
  the companion `package:noir_signals` package.
- Present tabs, sliders, ASCII-art headings, rich static tables, source code,
  unified or split diffs, and GitHub-flavoured Markdown with native terminal
  links and explicit OSC52 selection copy.
- Drop to supported renderer, buffer, or raw FFI APIs when an application
  needs more control.

## Documentation

Start at **[conceptadev.github.io/noir](https://conceptadev.github.io/noir/)**
for tutorials, task guides, platform support, and the widget catalog. The site
updates automatically when documentation changes reach `main`.

- [Build your first app](https://conceptadev.github.io/noir/docs/getting-started/)
  — a runnable counter, from initial layout to state and user input.
- [Installation and platform requirements](https://conceptadev.github.io/noir/docs/installation/)
  — published packages, checkout dependencies, and supported systems.

Source guides and generated reference:

- [Runnable example catalog](https://github.com/conceptadev/noir/blob/main/packages/noir/example/README.md)
  — every shipped app, listed by the question it answers.
- [Build a task list](https://github.com/conceptadev/noir/blob/main/packages/noir_signals/doc/getting-started.md)
  — a five-lesson tutorial on lifecycle hooks and reactive state.
- [Generated API reference](https://pub.dev/documentation/noir/latest/) — every
  published class, member, and signature.
- [CONTRIBUTING.md](https://github.com/conceptadev/noir/blob/main/CONTRIBUTING.md)
  — repository setup, the framework test harnesses, and drive mode.

## Install

Use Dart 3.10 or later and a terminal on macOS, Linux, or Windows. The bundled
macOS libraries require macOS 13 or later. Install the published version:

    dart pub add noir

The source tree can be ahead of the latest published version. When
evaluating an unreleased API, use a path dependency:

    dependencies:
      noir:
        path: ../noir

The [repository](https://github.com/conceptadev/noir) is public. For a Git
dependency, pin an exact commit or release tag rather than a moving branch.
A public repository does not mean every checkout API is published on pub.dev;
the installation guide identifies which package versions are available.

## Quick Start

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

The complete version is available in [the hello example](https://github.com/conceptadev/noir/blob/main/packages/noir/example/hello.dart).

Stateful widgets persist a `State` object between supported rebuilds. Call
`setState` after changing local state:

```dart
import 'package:noir/noir.dart';

void main() => runTuiApp(const CounterApp(), enableMouse: true);

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  void _incrementCounter() => setState(() => _count++);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Count: $_count'),
      Button(
        label: 'Increase',
        autofocus: true,
        onPressed: _incrementCounter,
      ),
      const Text('Enter, Space, or click to increase. Ctrl+C to quit.'),
    ],
  );
}
```

Save either complete example as `bin/main.dart`, then run `dart run bin/main.dart`
in a terminal. The counter rebuilds its label after keyboard or mouse activation.
See [the counter example](https://github.com/conceptadev/noir/blob/main/packages/noir/example/counter.dart)
for a larger layout and additional shortcuts.

## Hot Reload During Development

Run a Noir entry point through the packaged development command, then save a
`.dart` file under `lib/` or beside the entry point to reload it:

```sh
dart run noir:run example/counter.dart
```

The runner keeps the app attached to the current terminal, asks the Dart VM to
swap the edited sources, and invokes Noir's `ext.noir.reassemble` extension to
rebuild, lay out, and repaint the retained widget tree. A compile error leaves
the last good app running; fix the source and save again to retry. Runner
diagnostics are written to `.dart_tool/noir/run.log` so they do not overwrite
the alternate-screen UI. Replace `example/counter.dart` with your package's
entry point; arguments after it are forwarded to the app unchanged.

A Noir entry point can declare `main(List<String> arguments)` like any Dart
console program. Applications that need flags or subcommands can depend on
`package:args`, parse and validate the arguments before calling `runTuiApp`,
then pass typed values through the root widget's constructor. Noir does not
re-export a command-line parser. Use `ArgParser` to configure one application
root and `CommandRunner` only when a command name selects a distinct startup
workflow. Hot reload does not rerun `main()`, so restart the process to launch
with different arguments.

## Widget Lifecycle Hooks

Hooks live in the optional companion package `noir_signals`, not in `noir`.
The companion is not published yet. Use a repository checkout to try it. The
[companion overview](https://github.com/conceptadev/noir/blob/main/packages/noir_signals/README.md)
has that setup. After publication, add `noir_signals` beside Noir, then import
`package:noir_signals/noir_signals.dart` together with
`package:noir/noir.dart`.

The companion includes state, effects, memoization, listenables, asynchronous
snapshots, animation, focus, editing, scroll, and viewport hooks, plus the
Signals reactive integration. Hooks use call order as identity.

The companion has its own
[task-list tutorial](https://github.com/conceptadev/noir/blob/main/packages/noir_signals/doc/getting-started.md),
[hooks reference](https://github.com/conceptadev/noir/blob/main/packages/noir_signals/doc/hooks.md),
[Signals reference](https://github.com/conceptadev/noir/blob/main/packages/noir_signals/doc/signals.md),
and an [example directory](https://github.com/conceptadev/noir/tree/main/packages/noir_signals/example)
with a [hooks counter](https://github.com/conceptadev/noir/blob/main/packages/noir_signals/example/counter.dart),
[task list](https://github.com/conceptadev/noir/blob/main/packages/noir_signals/example/task_list.dart),
and [file search](https://github.com/conceptadev/noir/blob/main/packages/noir_signals/example/file_search.dart).
This package's archive does not carry the companion files.

## Component Catalog

| Area | Public widgets and types |
| --- | --- |
| Layout | `Container`, `Panel`, `Row`, `Column`, `Flexible`, `Expanded`, `Stack`, `Positioned`, `Wrap`, `Align`, `Padding`, `SizedBox` |
| Overlay and menus | `OverlayPortal`, `OverlayPortalController`, `Modal`, `ModalController`, `MenuAnchor`, `MenuController` |
| Text and media | `Text`, `RichText`, linked `TextSpan`, `AsciiFont`, `Image`, `TerminalImage` |
| Input | `TextInput`, `Autocomplete`, `TextArea`, `Select`, `TabSelect`, `Slider`, `Checkbox`, `Switch`, `Button` |
| Scrolling and data | `ScrollBox`, `ListView`, `TreeView`, virtualized interactive `DataTable`, static rich `TextTable` |
| Documents | `CodeView`, `DiffView`, `UnifiedDiffParser`, `MarkdownView`, `SelectedText` |
| Feedback and chrome | `Divider`, `ProgressBar`, `Spinner`, `Badge`, `Theme`, `Icons` |

`Icons` is a catalog of named single-cell glyph strings, not a widget: a
terminal icon is a character, so `Text(Icons.plus)` is the whole API and there
is no `Icon`, `IconData`, or `IconTheme`. No non-ASCII member carries the
Unicode `Emoji` property, avoiding environment-dependent emoji presentation;
ASCII keycap bases such as `*` remain ordinary one-cell text when used alone.

`TextTable` complements rather than replaces `DataTable`: use `TextTable` for
a finite rich-text grid with wrapping and row-major text selection, and
`DataTable` for a windowed interactive data source with row selection and
sorting.
Likewise, `TabSelect` is the horizontal tab control, with fixed-cell widths by
default and label-sized tabs via `tabWidth: null`; the existing `Select` remains
the vertical list-of-options control.

`OverlayPortal` keeps overlay content as a logical descendant of the portal
while `runTuiApp` hosts one private root overlay. `Modal` adds centered
presentation, closed-loop focus, Escape dismissal, focus restoration, and a
pointer barrier; it stays unstyled, so compose visible dialog chrome with
`Panel`. `MenuAnchor` places an unstyled integer-cell menu relative to its
launcher and follows that launcher in the same frame after resize or movement.
It does not close on resize the way Flutter currently does. Outside pointer
events are consumed at render-tree priority so they cannot reach lower widgets;
`TuiApp.onMouse` may still observe the raw event. There is no public `Overlay` /
`OverlayEntry`, nested overlay, transform, `LayerLink`, animation, or cascade
API.

## Application Lifecycle and API Tiers

A Noir entry point is one line:

```dart
void main() => runTuiApp(const MyApp(), enableMouse: true);
```

`runTuiApp` mounts the root widget and returns a `TuiApp` handle
synchronously. Dart's event loop keeps the process alive after `main()`
returns — the stdin subscription and signal watchers own the lifetime — so
there is no future to await. A real terminal detects its own size and tracks
resizes; pass a custom canvas size only through `TuiBinding` in
`package:noir/noir_low_level.dart`.

To quit, call `TuiApp.exit(context)` from anywhere in the tree — in a key
handler, say — instead of threading a callback down from `main()`.

`TuiApp.exit` disposes the app — restoring the terminal and cancelling stdin,
signal, and timer subscriptions — and sets the process exit code; the event
loop then drains and the process ends on its own, with no `dart:io` exit call.
It is safe to call from inside an event handler and safe to call twice, since
a double keypress racing the teardown is ordinary. `TuiApp.of(context)` and
`TuiApp.maybeOf(context)` return the enclosing handle.

Keep the returned handle when you register application-wide input or toggle
terminal modes at runtime. `onKey`, `onMouse`, and `onPaste` install
app-priority handlers, and each returns an idempotent canceler.

`TuiApp.dispose()` is idempotent. It cancels every still-owned registration
before disposing the mounted app, input modes, and renderer resources. The
default POSIX signal handling performs cleanup for SIGINT, SIGTERM, and
SIGHUP. In raw input mode, an unconsumed Ctrl+C key follows the same interrupt
cleanup path and exits with status 130; an app or focused widget can consume it
first to override that default.

`headless: true` creates no owned terminal renderer and is exposed through
`TuiApp.isHeadless`. Renderer-backed mouse and Kitty keyboard mode controls
are unavailable in that mode, so `enableMouse: true` fails loudly there.

`TuiApp.reassemble()` invokes `State.reassemble()` on every retained state,
rebuilds the whole widget tree, and forces a full layout and paint pass
without recreating any `State`, terminal, or native resource. It is the
hot-reload hook: call it after a source swap succeeds. `runTuiApp` registers
it for you, so a development driver can invoke it over the VM service
extension `ext.noir.reassemble`; `registerHotReloadExtension(app)` stays
exported for custom hosts that mount their own app.

Noir has three supported import surfaces:

- `package:noir/noir.dart` — ordinary application and widget authoring.
- `package:noir/noir_low_level.dart` — advanced hosting, renderer/buffer
  access, and supported custom rendering.
- `package:noir/noir_ffi.dart` — ABI-unstable raw FFI access.

Concrete Element implementations and the recorder/display-list/compositor
backend remain framework-owned; they are not supported package surfaces.

The optional companion package `noir_signals` adds a fourth surface,
`package:noir_signals/noir_signals.dart`. It is a separate dependency built
only on Noir's high-level API; `noir` never depends on it.

## Examples

Start with [Main](https://github.com/conceptadev/noir/blob/main/packages/noir/example/main.dart), [Counter](https://github.com/conceptadev/noir/blob/main/packages/noir/example/counter.dart), or
[Components](https://github.com/conceptadev/noir/blob/main/packages/noir/example/components_demo.dart). The
[example catalog](https://github.com/conceptadev/noir/blob/main/packages/noir/example/README.md) lists every runnable app by the question
it answers, including focused controls, complete applications, animation,
advanced validation, and the tutorial checkpoints the documentation captures
its frames from.

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
| Insert / Delete / PageUp / PageDown | `insert`, `delete`, `pageUp`, `pageDown` |
| Function keys | `f1`–`f12` |
| Mouse SGR | `MouseEvent` with type, button, cell position, modifiers, and directional scroll magnitude |
| Bracketed paste | one `PasteEvent` per block through `app.onPaste` |
| xterm `modifyOtherKeys` | modified named and printable keys, including Ctrl+Enter |
| Kitty keyboard | modifiers and press/repeat/release metadata after `app.enableKittyKeyboard()` |

Unix sessions observe SIGWINCH; interactive Windows sessions check terminal
size every 100ms. A changed, positive size resizes the terminal buffer and lays
out the widget tree again.

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

The bundled macOS x64 and arm64 libraries require macOS 13.0 or later.
For linked macOS applications, Dart must rewrite the dylib install name for a
relocatable bundle. The official dylib has no load-command padding, so Noir
removes its optional source-version load command from a temporary hook output
copy before Dart rewrites and signs that copy. The six tracked release assets
remain byte-for-byte identical to the hashes in `native_manifest.json`.

Run the packaged diagnostic to check bundled native asset resolution without
writing terminal controls:

```bash
dart run noir:health_check
```

The diagnostic uses OpenTUI's native testing mode to exercise the bundled
native asset and headless buffer/render lifecycle. It does not validate real
terminal escape rendering.

Android, iOS, and web are not supported targets. See
[Third-Party Notices](https://github.com/conceptadev/noir/blob/main/packages/noir/THIRD_PARTY_NOTICES.md) for OpenTUI provenance and
license terms.

High-level Unicode cell measurement uses a compact pure-Dart range table
derived from the exact `uucode` revision pinned by OpenTUI v0.5.1 (Unicode
16.0) plus OpenTUI's width overrides. This keeps widget layout out of FFI while
matching the pinned native release's code-point and grapheme rules.

The URLs in `native_manifest.json` record immutable provenance for the
currently bundled artifacts. They are not an update instruction or a runtime
recovery path.

`OPENTUI_LIBRARY_PATH` is the exact development override for a compatible
custom library. It is not a search path and not a remedy for an incomplete or
corrupt package.

## Known Limitations

- Kitty, Sixel, and OSC52 acceptance depends on the terminal or multiplexer.
  Automated coverage verifies protocol selection, deterministic block fallback,
  clipping, sizing, and OSC52 argument/status behavior. Direct Kitty graphics,
  OSC52, and resize/crop have real-terminal evidence. Sixel, GNU Screen, and
  OSC52 through tmux remain unverified. Automatic image mode uses blocks under
  tmux; unavailable Sixel (including a missing pixel-resolution measurement)
  falls back to blocks. Forcing Kitty graphics through tmux is unsupported
  because the initial placement can overlap existing content until a resize.
  Use automatic image mode under tmux.
- Dart 3.10 supplies a macOS deployment target of 12 to native-asset hooks,
  while the bundled OpenTUI libraries require macOS 13. Because
  `dart build cli` does not expose a deployment-target override, Noir documents
  macOS 13 as its minimum and allows the normal build to proceed. On macOS 12,
  the native loader can therefore report the incompatibility at runtime rather
  than the hook rejecting the build earlier.
- High-level layout and painting keep multi-code-point graphemes intact and
  expand intersecting selection ranges to whole grapheme clusters.
  `DirectBufferAccess.getEncodedCellAt()` exposes guarded access to native
  encoded storage; packed grapheme words are not independently decodable
  Unicode scalars.
- OpenTUI v0.5.1's native `bufferDrawText` path mishandles a run whose first
  grapheme has source-level width zero: it can emit UTF-8 continuation bytes as
  cells and advance before the following text. Noir keeps the pinned source's
  correct zero-width layout semantics; leading zero-width graphemes, including
  ones isolated by a style boundary, can therefore diverge from native paint.
- A decorated box that straddles a clipped viewport edge paints its full
  border. Native `bufferDrawBox` writes transparent-background borders through
  an unchecked index, so it escapes even OpenTUI's own scissor rect. Boxes that
  miss the viewport entirely are dropped.
- Some low-level native operation failures cannot be reported precisely to
  Dart.
- On the observed macOS/iTerm path, the pinned alternate-screen lifecycle can
  return to main-screen row 1/column 1 instead of the launch cursor and
  overwrite prior shell rows. Callers must still dispose `TuiApp` so all owned
  resources and terminal modes are released.
- Hot reload is bounded by what the Dart VM can swap into a live isolate.
  `TuiApp.reassemble()` invokes `State.reassemble()` on every retained state
  and re-runs `build()`, layout, and paint bodies; it never re-runs `main()` or
  `initState`. Overriding `State.reassemble()` is the supported way to re-derive
  what an `initState` body computed. Changes to `main()`/`initState`, to a
  signature held by a frame on the stack, to an enum converted into a class, or
  to the bundled OpenTUI native library still require a full restart.
- The current Linux libraries retain absolute build/debug paths. They pass
  static integrity checks; this is visible upstream artifact metadata rather
  than a Noir rebuild output.
