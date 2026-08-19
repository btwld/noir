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

## Framework contributor tests

The development repository has additional layout, buffer, input-driver,
integration, and golden-test infrastructure in its own repository test
helpers (`WidgetTester`, `BufferCapture`, `KeyDriver`, `createTuiTestApp`).
Those helpers are not package API: they are absent from the published archive,
and application tests cannot import them. When you are changing the framework
itself rather than an app built on it, follow the repository's contributor
guide — it names which harness to use for which kind of test and forbids
inventing a fifth one.
