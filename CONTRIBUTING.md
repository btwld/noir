# Contributing to Noir

Noir welcomes focused bug fixes, tests, documentation, and framework
improvements. Start with [`AGENTS.md`](AGENTS.md) for architecture and safety
rules and [`TODO.md`](TODO.md) for the open release items and workflow.

## Setup

Prerequisites:

- Dart SDK 3.10.0 or later, below 4.0.0.
- Git.
- Platform tooling required by Dart native assets.

Clone the pinned OpenTUI reference with the repository:

    git clone --recurse-submodules https://github.com/leoafarias/noir.git
    cd noir
    dart pub get

If the repository was cloned without submodules:

    git submodule update --init --recursive

The submodule and bundled libraries are read-only under ordinary contribution
work. See [`AGENTS.md`](AGENTS.md#opentui-reference-and-ownership).

## Required checks

Run focused tests while developing, then:

    dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ scripts/
    dart analyze --fatal-infos
    dart test test/architecture/ --concurrency=1
    dart test --concurrency=1
    dart run scripts/fetch_opentui_binaries.dart --verify-only

The `safe-process-spawning` tag covers ordinary isolated-process tests and is
included in the standard suite.

Automatic push/pull-request CI is ordinary verification. Do not manually
dispatch or rerun a workflow without exact authorization.

## Tests

Use the existing harness that owns the behavior:

| Harness | Purpose |
| --- | --- |
| `WidgetTester.pumpWidget` | Layout and widget lifecycle |
| `BufferCapture.capture` | One rendered frame and visual assertions |
| `KeyDriver` | Synthetic parsed input behavior |
| `createTuiTestApp` | End-to-end binding/parser integration |

Architecture tests in `test/architecture` are executable package boundaries,
not snapshots of old plans. Visual goldens use `.buffer.txt` plus style and
cursor sidecars by default. Prefer `BufferMatchers` for cell assertions.

For behavior changes:

1. Add a focused test that fails for the intended reason.
2. Implement the smallest coherent fix.
3. Run the focused test and related ownership tests.
4. Run the required checks above before requesting review.

## Driving an app

`NOIR_DRIVE=1` mounts any Noir entry point headlessly, painting into OpenTUI's
non-terminal testing renderer and publishing `ext.noir.driver.*` over the VM
service. Nothing in the app changes. `scripts/noir_drive.dart` launches an app
that way and reads commands from its own stdin, interactively or from a pipe:

    dart run scripts/noir_drive.dart example/counter.dart [--size 100x30] [--json]

    capture [--ansi|--plain|--cells]
    tree [depth]
    key <up|down|left|right|enter|tab|esc|backspace|pgup|pgdn|ctrl-<a-z>>
    type <text...>
    click <x> <y>
    scroll <up|down|left|right> <x> <y>
    resize <WxH>
    reload
    watch on|off
    quit

Rendered frames and tree output go to stdout while status and errors go to
stderr, so a scripted run captures exactly what the app painted:

    printf 'capture --ansi\nkey up\ncapture --ansi\nquit\n' | \
      dart run scripts/noir_drive.dart example/counter.dart

`scripts/driver/noir_driver.dart` exposes the same surface as a Dart client for
scripts that assert against captures. Neither is a test harness: they drive a
live app process instead of mounting widgets, so the four harnesses above
remain the way to test widget behavior.

Keys and mouse reports are encoded to escape bytes on the client side and
injected through the production ANSI parser, so a driven interaction takes the
same path a real terminal would. This needs no TTY and no raw mode.

Known limits: a continuously animating app never reports `stable: true`, and
capture keeps working anyway; an app whose own quit path calls `exit` ends the
session; and `reload` inherits the documented `reassemble()` limits, so
`main()` and `initState` bodies still need a restart.

## Style and documentation

- Format all Dart with `dart format`.
- Keep imports grouped as Dart SDK, package imports, then relative imports.
- Prefer `final`, trailing commas, and `const` where they improve clarity.
- Document public guarantees and terminal-specific behavior.
- Keep examples compilable and use symbols exported by the documented barrel.
- Do not claim gradients, images, shadows, shapes, performance, platform
  support, or terminal fidelity that tests do not establish.
- Generated FFI files are never edited by hand; see [`FFIGEN.md`](FFIGEN.md).

## Changes and review

Keep commits small enough to review semantically. A useful commit message
states the outcome, for example:

    fix(input): restore inherited terminal modes exactly

Do not mention tools or assistants in commits, pull requests, changelog
entries, or product documentation. Do not mix native artifact changes with
ordinary Dart changes. A native dependency refresh requires its own explicit
decision and review.
