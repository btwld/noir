# noir_driver

Drive a [Noir](https://pub.dev/packages/noir) terminal app headlessly, as a
real process, and read back what it actually painted.

No TTY. No raw mode. No change to the app's own `main()`.

## How it works

`package:noir` ships drive mode: with `NOIR_DRIVE=1` in its environment,
`runTuiApp` mounts the app into a headless binding that paints into OpenTUI's
non-terminal testing renderer and publishes an `ext.noir.driver.*` VM-service
surface. This package is the client on the other end.

Keys and mouse reports are encoded to escape bytes here and injected through
the app's production ANSI parser, and locator clicks resolve through the
production render tree's hit testing — so a driven interaction takes the path
a real terminal would.

## Install

```sh
dart pub add --dev noir_driver
```

## Use it from a test

```dart
import 'package:noir_driver/noir_driver.dart';
import 'package:test/test.dart';

void main() {
  test('the counter counts', () async {
    final driver = await NoirDriver.launch('bin/app.dart');
    addTearDown(driver.quit);

    await driver.clickLocator(const DriverLocator.byKey('increment'));

    expect(await driver.capture(), DriverFrameMatchers.containsText('Count: 1'));
  });
}
```

A failed assertion prints the frame:

```
Expected: a frame painting "Count: 2"
  Actual: <Instance of 'DriverFrame'>
   Which: no row contains it.
          captured 20x3 frame:
            0 |   Noir Counter
            1 |    Count: 1
            2 |
```

## Locators

`DriverLocator.byKey`, `.byType`, `.byText`, and `.focused` match exactly and
case-sensitively against a freshly fetched tree. `find` is strict: it rejects
both zero matches and ambiguity, and a miss lists what the tree does contain.

When two nodes legitimately share a key, narrow instead of guessing:

```dart
DriverLocator.byKey('confirm').descendantOf(DriverLocator.byKey('dialog-b'))
DriverLocator.byType('Button').at(1)
```

An ancestor must resolve uniquely. Ambiguous ancestry throws from lookups and
waits, including `waitForAbsent`; it never counts as a missing target.

Only `ValueKey<String>` is a key locator. Text locators read `Text` and
`RichText` source, not painted cells — `waitForText` is the painted-cell wait.
Type locators are `runtimeType` strings, so `Select<String>` matches and
`Select` does not.

A locator click uses the match's own visible pointer route and never borrows an
ancestor's or descendant's. It does not auto-scroll: an offscreen, fully
obscured, or non-pointer target fails clearly rather than passing on a cell a
user could not reach.

## Waiting

Input waits for the app to paint before returning, capped short so a key the
app ignores does not cost a full timeout:

```dart
final painted = await driver.sendKey('enter');            // default window
await driver.sendKey('enter', settle: Duration(seconds: 2));
```

A `false` return means no frame arrived in time — which covers both an ignored
input and one the app is still working on — so a following `capture` may show
the pre-input frame. When an app can be slow, raise `settle` or assert through
`waitForText` or `waitFor`.

## From the command line

```sh
dart run noir_driver:drive bin/app.dart --size 100x30
```

Commands are read from stdin, one per line, interactively or from a pipe:

```sh
printf 'capture --ansi\nkey up\ncapture --ansi\nquit\n' |
  dart run --verbosity=error noir_driver:drive bin/app.dart
```

`capture [--ansi|--plain|--cells]`, `tree [depth]`, `find`/`wait` with a
locator, `key`, `type`, `click`, `scroll`, `resize`, `reload`, `watch on|off`,
and `quit`. Frames go to stdout and status to stderr, so a piped run captures
exactly the rendered output.

## What this is not

It drives a live app process rather than mounting widgets, so it does not
replace Noir's in-process test harnesses — use those for widget behavior.

Its output is real Noir rendering through OpenTUI's non-terminal testing
renderer. That is not evidence of raw-mode cleanup, nor of Kitty, Sixel,
OSC52, tmux, or Screen behavior in a named terminal emulator.

Known limits: a continuously animating app never reports `stable: true`, and
capture keeps working anyway; an app whose own quit path calls `exit` ends the
session; `reload` inherits `reassemble()`'s limits, so `main()` and `initState`
bodies still need a restart; and `DriverFrame.lines` is right-trimmed, so
trailing-space bugs need `captureCells`.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
