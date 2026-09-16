# Contributing to Noir

Noir welcomes focused bug fixes, tests, documentation, and framework
improvements. Start with [`AGENTS.md`](AGENTS.md) for architecture and safety
rules. Open work lives in GitHub issues and pull requests.

## Setup

Prerequisites:

- Dart SDK 3.10.0 or later, below 4.0.0.
- Git.
- Platform tooling required by Dart native assets.

Clone the pinned OpenTUI reference with the repository:

    git clone --recurse-submodules https://github.com/conceptadev/noir.git
    cd noir
    dart pub get

If the repository was cloned without submodules:

    git submodule update --init --recursive

The submodule and bundled libraries are read-only under ordinary contribution
work. See [`AGENTS.md`](AGENTS.md#opentui-reference-and-ownership).

The repository is one Pub workspace. `dart pub get` at the root resolves the
`noir` package under `packages/noir/` and two optional companions:
`packages/noir_driver/`, the drive-mode client applications use to test a Noir
app as a live process, and `packages/noir_signals/`, which owns the widget
lifecycle hooks and the Signals integration. The root `pubspec.yaml` only
defines the workspace.

## Required checks

Run focused tests while developing, then, from `packages/noir/`:

    dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ tool/
    dart analyze --fatal-infos
    dart test test/architecture/ --concurrency=1
    dart test --concurrency=1
    dart run tool/fetch_opentui_binaries.dart --verify-only

When a change touches the driver package, also run, from
`packages/noir_driver/`:

    dart format --output=none --set-exit-if-changed lib/ test/ bin/
    dart analyze --fatal-infos
    dart test --concurrency=1

When a change touches the companion package, also run, from
`packages/noir_signals/`:

    dart format --output=none --set-exit-if-changed lib/ test/ example/
    dart analyze --fatal-infos
    dart test --concurrency=1

The `safe-process-spawning` tag covers ordinary isolated-process tests and is
included in the standard suite.

Package-consumer checks export Noir using Pub's archive file selection, then
analyze and run an application against the extracted package outside the
checkout. They cover native cell output, the packaged health check, a relocated
CLI bundle, and driven widget/input behavior. This catches files or dependencies
that work through a source path but are missing from the published archive.

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

Architecture tests in `packages/noir/test/architecture` are executable package boundaries,
not snapshots of old plans. Visual goldens use `.buffer.txt` plus style and
cursor sidecars by default. Prefer `BufferMatchers` for cell assertions.

`packages/noir/tool/mcp_inspector` is a separate package with its own format,
analyze, and test commands, and Noir's analysis options exclude it. Its
fixture servers live in `packages/noir/tool/mcp_fixtures`, which depends on
`package:mcp_dart` alone: a fixture that inherited Noir's native-assets build
hook would let `dart run` write hook progress onto the MCP protocol channel.
Two Noir tests keep both packages in the ordinary suite:
`test/tools/mcp_inspector_package_test.dart` runs their gates as subprocesses,
and `test/tools/mcp_inspector_drive_test.dart` drives the real screen against
the fixture servers.

For behavior changes:

1. Add a focused test that fails for the intended reason.
2. Implement the smallest coherent fix.
3. Run the focused test and related ownership tests.
4. Run the required checks above before requesting review.

## Driving an app

`NOIR_DRIVE=1` mounts any Noir entry point headlessly, painting into OpenTUI's
non-terminal testing renderer and publishing `ext.noir.driver.*` over the VM
service. Nothing in the app changes. `packages/noir_driver/` is the client:
its `drive` executable launches an app that way and reads commands from its
own stdin, interactively or from a pipe. Run it from `packages/noir/`, which
dev-depends on it, or from `packages/noir_driver/`:

    dart run noir_driver:drive example/counter.dart [--size 100x30] [--json]

    capture [--ansi|--plain|--cells]
    tree [depth]
    find key|type|text <exact value> | find focused
    wait key|type|text <exact value> | wait focused
    key <up|down|left|right|enter|tab|shift-tab|space|esc|backspace|home|end|delete|pgup|pgdn|ctrl-<a-z>>
    type <text...>
    click <x> <y> | click key|type|text <exact value> | click focused
    scroll <up|down|left|right> <x> <y>
    resize <WxH>
    reload
    watch on|off
    quit

Rendered frames and tree output go to stdout while status and errors go to
stderr. Use Dart 3.11 or later to keep build-hook progress out of scripted
captures:

    printf 'tree 10\nfind key increment\nclick key increment\ncapture --plain\nquit\n' | \
      dart run --verbosity=error noir_driver:drive example/counter.dart

On Dart 3.11 or later, pass `--verbosity=error` whenever frames are piped or
redirected. Dart 3.10 may still write build-hook progress to stdout despite
this flag, prepending it to the first captured row.

`package:noir_driver` exposes the same surface as a Dart client for scripts
and tests that assert against captures. `tree()` returns structured `DriverNode`
snapshots, and `DriverLocator.byKey`, `.byType`, `.byText`, and `.focused`
resolve exactly and case-sensitively on the client. Only `ValueKey<String>` is
a stable key locator; text comes directly from `Text` and `RichText` source
content, not painted Select, TabSelect, DataTable, or ListView glyphs. Type
locators are `runtimeType` strings, so `Select<String>` matches and `Select`
does not. Strict lookups and clicks reject ambiguous matches. A zero-match
error lists nearby keys or exact types from the same snapshot.

`descendantOf` and `at` narrow a locator without changing it, which is how
two nodes sharing a key become addressable:

    DriverLocator.byKey('confirm').descendantOf(DriverLocator.byKey('dialog-b'))
    DriverLocator.byType('Button').at(1)

`descendantOf` is proper descent at any depth: a node never matches as its own
ancestor, an intermediate node does not break the chain, and the ancestor
itself resolves strictly. `at` is document order and is the weakest locator
here, since a layout change silently re-points it. A narrowed miss names the
stage that emptied it — an ancestor that matched nothing, an ancestor that
excluded every match, or an index past the end — and lists what it had.

Composition is Dart-client only. The CLI grammar stays flat: it is the human
and pipe surface, and `find key X in key Y` would grow a parser for a need
that scripts express better in Dart.

The line-oriented CLI trims outer command whitespace, so use the Dart client
when an exact key, type, or text value itself starts or ends with whitespace.

CLI tree defaults to depth 2 so a human listing stays short; `find`, `wait`,
and `click` always snapshot the full tree. Use `tree 10` when you want to see
`increment` in the listing.

`waitForText` polls painted capture rows for a substring. `byText` / `find
text` match exact `Text` and `RichText` source, not those cells.

Put `ValueKey<String>` on the control or a Stateless/Stateful wrapper that
owns it. A key on a layout `RenderObjectWidget` such as `Padding` or `Column`
does not inherit a child's pointer route. A locator click uses that node's
own visible pointer route and does not borrow an ancestor or descendant
`hitPoint`.

Every locator operation fetches a fresh tree. Locator clicks use a currently
visible hit-tested cell from the production render-tree path, including
ScrollBox translation, clipping, Stack occlusion, and custom `RenderObject`
`HitTestTarget`s that join `HitTestResult.path` without being a `RenderBox`.
They do not auto-scroll; an offscreen, fully obscured, or non-pointer target
fails clearly. Neither the CLI nor client is a test harness: they drive a live
app process instead of mounting widgets, so the four harnesses above remain the
way to test widget behavior.

Keys and mouse reports are encoded to escape bytes on the client side and
injected through the production ANSI parser, so a driven interaction takes the
same path a real terminal would. This needs no TTY and no raw mode.

Input waits for the app to paint before returning, capped at `defaultSettle`
so a key an app ignores does not cost a full timeout. `sendKey`, `typeText`,
`click`, `clickLocator`, and `scroll` return whether a frame arrived and take
a `settle` override; the CLI notes a miss on stderr. A false return covers
both an ignored input and one the app is still working on, so a following
`capture` may show the pre-input frame. When an app can be slow to respond,
raise `settle` or assert through `waitForText` or `wait` instead of a bare
`capture`.

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
- Generated FFI files are never edited by hand; see
  [`packages/noir/FFIGEN.md`](packages/noir/FFIGEN.md).

## Changes and review

Keep commits small enough to review semantically. A useful commit message
states the outcome, for example:

    fix(input): restore inherited terminal modes exactly

Do not mention tools or assistants in commits, pull requests, changelog
entries, or product documentation. Do not mix native artifact changes with
ordinary Dart changes. A native dependency refresh requires its own explicit
decision and review.

## Releasing

`packages/noir/pubspec.yaml` carries the candidate version and the top section
of `packages/noir/CHANGELOG.md` describes it. `publication.json` records the
latest version of each package on pub.dev, or `null`; the website derives
every availability label from it and both manifests, so update it in the same
change as a publication.

Publish in this order, each package from its own directory:

1. `noir`, from `packages/noir/`, at the exact reviewed commit, after its
   merge-commit CI passed.
2. `noir_driver`, from `packages/noir_driver/`. First run
   `dart run tool/stage_companion_package.dart --verify ../noir_driver` from
   `packages/noir/`.
3. `noir_signals`, from `packages/noir_signals/`. First run
   `dart run tool/stage_companion_package.dart --verify` from `packages/noir/`
   to check the archive as an application outside this workspace resolves it.
4. A consumer that depends on the published versions with no local
   override, to confirm the hosted packages resolve together.

Tags, GitHub releases, repository visibility, and native artifact refreshes
are separate explicit decisions and are never part of an ordinary change.
