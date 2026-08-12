# Testing applications built with Noir

Noir does not export a public widget-test harness. Package consumers should
test through supported package APIs and the application-facing seams they own.
Keep state transitions separate from terminal rendering where practical, then
add a small number of headless lifecycle and interactive integration checks.

## Headless lifecycle checks

`runTuiApp(..., headless: true)` mounts the normal widget and element tree
without creating an owned terminal renderer. It is useful for checking that an
application can mount, build, and dispose through the public lifecycle:

```dart
import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  test('mounts and disposes headlessly', () {
    final app = runTuiApp(const Text('ready'), headless: true);

    expect(app.isHeadless, isTrue);
    app.dispose();
  });
}
```

Headless mode deliberately has no renderer-backed mouse or Kitty keyboard mode
controls. It is a lifecycle seam, not a visual snapshot facility.

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

## Framework contributor tests

The Noir development repository has additional private layout, buffer,
input-driver, integration, and golden-test infrastructure. Those helpers are
not package API and are intentionally absent from the published archive.
Consult the contributor documentation in the
[development repository](https://github.com/leoafarias/noir) when changing
the framework itself.
