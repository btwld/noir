# Testing applications built with Noir

Noir does not export a public widget-test harness. Package consumers should
test through supported package APIs and the application-facing seams they own.
Keep state transitions separate from terminal rendering where practical, then
add a small number of headless lifecycle and interactive integration checks.

## Headless lifecycle checks

`runTuiApp(..., headless: true)` mounts the normal widget and element tree
without creating an owned terminal renderer. It is useful for checking that an
application can mount, build, and dispose through the public lifecycle. A
headless run uses the 80×24 default; a custom canvas without a terminal is
advanced hosting through `TuiBinding` in `package:noir/noir_low_level.dart`.

```dart
import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  test('mounts and disposes headlessly', () {
    final app = runTuiApp(const Text('ready'), headless: true);

    expect(app.isHeadless, isTrue);
    app.dispose();   // idempotent; safe to call again in a tearDown
  });
}
```

Headless mode deliberately has no renderer-backed mouse or Kitty keyboard mode
controls. It is a lifecycle seam, not a visual snapshot facility: it proves the
tree builds and tears down, not what the frame looked like.

## State and controller tests

Prefer independently testable state owners for behavior that does not require
layout or paint:

- `ValueNotifier<T>` for one observable value.
- `ChangeNotifier` for several related values or transitions.
- `TextEditingController` for text, selection, and editing commands.
- Plain Dart objects for domain rules and asynchronous work.

Pass those owners into widgets and test their values, notifications, and
callbacks directly. This keeps most tests deterministic and avoids tying
application behavior to terminal escape output.

## Input and interaction

Put application commands behind callbacks or small controller methods, then
have `onKey`, `onMouse`, `onPaste`, `Shortcuts`, or widget callbacks invoke
them. Unit-test the command behavior directly. Add an integration test around
the actual application only when parser, focus, layout, or renderer interaction
is the behavior under test.

Always dispose application handles, focus nodes, editing controllers,
notifiers, and animation controllers in the same ownership layer that created
them.

## Drive mode is not a test harness

`NOIR_DRIVE=1` mounts any app headlessly and exposes an `ext.noir.driver.*`
VM-service surface for capturing frames, inspecting the tree, and injecting
input — the main skill file's "See and drive a running app" section covers it.
It exists for *looking at and driving* a live app during development. Keep
automated assertions in ordinary tests against the state owners and seams
described above: the same frames are reachable in-process, faster, and without
a VM-service dependency.

For `Image`, drive mode deterministically materializes placements as block
cells, so captures can verify layout, replacement, and resize behavior. It is
headless and cannot establish whether a real terminal accepts Kitty or Sixel
escape output; those protocol checks require separately authorized live
terminal validation.

Driver cell captures include an additive `links` array parallel to every
captured row. Each entry is either the semantic URL painted in that cell or
null; native link IDs are deliberately hidden because they are allocation
details. Clients that only read `text`, colors, attributes, or cursor fields
remain compatible.

Document selection and OSC52 copying can be tested without a real terminal by
injecting parsed pointer/key events and a fake `Renderer` implementing
`ClipboardSupport`. Assert grapheme-safe UTF-16 `SelectedText`, callback order,
copy success/failure, and that empty-selection Ctrl+C remains unhandled. A
headless or drive assertion cannot prove that a user's terminal, tmux, or
Screen accepts OSC52; those are separately authorized live checks.

## Framework contributor tests

The development repository has additional layout, buffer, input-driver,
integration, and golden-test infrastructure in its own repository test
helpers (`WidgetTester`, `BufferCapture`, `KeyDriver`, `createTuiTestApp`).
Those helpers are not package API: they are absent from the published archive,
and application tests cannot import them. When you are changing the framework
itself rather than an app built on it, follow the repository's contributor
guide — it names which harness to use for which kind of test and forbids
inventing a fifth one.
