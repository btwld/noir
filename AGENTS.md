# Noir contributor and agent guide

Start with [`GOALS.md`](GOALS.md), which defines the durable architecture
and quality bar. The top section of
[`packages/noir/CHANGELOG.md`](packages/noir/CHANGELOG.md) describes the
current candidate, `publication.json` records what is on pub.dev, and open
work lives in GitHub issues and pull requests.

## Repository layout

- `packages/noir/`: the `noir` package, with its tests, examples, bundled
  native artifacts, and development tooling in `tool/`.
- `packages/noir_driver/`: the optional drive-mode client package.
- `packages/noir_signals/`: the optional companion package.
- `website/`: the documentation site.
- `skills/`: agent skills for building with Noir and maintaining this
  repository.
- `external/opentui/`: the read-only OpenTUI submodule.

The root `pubspec.yaml` defines the Pub workspace and the Melos
configuration that owns the shared dependency versions and the scripts that
wrap the checks below. It declares no dependencies of its own beyond Melos,
and is never published.

## Purpose and architecture

Noir is a Flutter-like reactive terminal UI framework for Dart, backed by
OpenTUI.

> Widgets declare. Elements preserve identity. RenderObjects layout and record
> paint. The compositor talks to OpenTUI. The native layer owns FFI, memory,
> ABI, and binaries.

Keep each concern in its owning layer:

- Widgets express immutable configuration.
- Elements reconcile widgets and preserve `State` and inherited dependencies.
- Render objects perform layout, hit testing, and display-list recording.
- The compositor is the normal bridge from display lists to OpenTUI buffers.
- The native layer owns guarded bindings, loading, handles, and bundled assets.

No widget may call FFI directly. Render-object paint methods use
`PaintingContext`, not `Buffer`. Finalizers are safety nets; explicit lifecycle
methods remain the primary resource owner.

## Supported package surfaces

- `package:noir/noir.dart`: applications and widgets, including `TuiApp`.
- `package:noir/noir_low_level.dart`: supported advanced hosting and custom
  render-object protocols.
- `package:noir/noir_ffi.dart`: guarded but ABI-unstable raw bindings.
- `package:noir_driver/noir_driver.dart`: the optional drive-mode client
  under `packages/noir_driver/`. Applications add it as a `dev_dependency` to
  drive a Noir app as a live process and assert on painted frames. Noir ships
  the app half of drive mode; this package is the client.
- `package:noir_signals/noir_signals.dart`: the optional companion package
  under `packages/noir_signals/`. It owns the widget lifecycle hooks and the
  Signals integration, and is built only on Noir's high-level public surface.

Generated bindings, library discovery, concrete Element implementations, and
recording/compositing internals remain framework-owned.

## OpenTUI reference and ownership

`external/opentui` is a read-only submodule pinned to canonical OpenTUI v0.5.1.

Use these pinned sources when checking semantics:

- `external/opentui/packages/react` for declarative component patterns.
- `external/opentui/packages/core` for renderer, input, and buffer behavior.

Do not edit or advance the gitlink, create or push OpenTUI refs, run upstream
workflows, rebuild or replace bundled libraries, or change the native ABI,
manifest hashes, or provenance URLs without a separate explicit dependency
strategy decision. Record native-only findings as visible limitations.

## Change workflow

For a non-trivial change:

1. Audit compatibility drift and the affected ownership boundary.
2. Write an implementation contract with observable behavior and affected
   files.
3. Add a focused failing test and confirm that it fails for the intended
   reason.
4. Implement the smallest coherent change.
5. Obtain an independent behavior and diff review.
6. Run focused checks, architecture fitness tests, then the ordinary suite.
7. Commit only a coherent, verified slice.

Small documentation or comment corrections may use edit → focused checks →
commit, but must not introduce stale references. During the prerelease phase,
remove obsolete API shapes instead of adding compatibility shims.

## Authorized local verification

The repository is one Pub workspace. `dart pub get` at the root resolves both
packages together, and `dart analyze --fatal-infos` at the root covers every
package.

Melos is a workspace dev dependency, so `dart run melos:melos run <script>`
works after that resolve, with no global install. Each script wraps one
command below, verbatim, and runs it from the directory this section names;
`dart run melos:melos run --list` prints them. The commands themselves stay
the source of truth, and an architecture test holds every script to the
command it wraps. `melos bootstrap` is `dart pub get` plus a shared-constraint
sync, and must leave the tree clean.

Run these from `packages/noir/`, for the `noir` package:

    dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ tool/
    dart analyze --fatal-infos
    dart test test/architecture/ --concurrency=1
    dart test <focused test paths> --concurrency=1
    dart test --concurrency=1
    dart run tool/fetch_opentui_binaries.dart --verify-only
    dart run tool/capture_doc_frames.dart --check
    dart run tool/release.dart check
    dart pub publish --dry-run

`capture_doc_frames.dart` drives the documented tutorial checkpoints in
headless drive mode and compares the result with the committed frames the
website publishes. `--check` never writes; omit it to refresh them.

`release.dart` owns the release rules the publish and release workflows
apply, so those workflows stay thin callers and the rules are covered by
`test/tools/release_cli_test.dart` on every ordinary run. `check` is part of
the `verify` ladder and reads only local files. Its other commands —
`resolve-tag`, `preflight`, and `record` — read pub.dev, and `record` is the
only one that writes anything; run it only after a publication is confirmed.
Publishing itself is never a local step: it happens when a maintainer pushes
a `<package>-v<version>` tag and a required reviewer approves the `pub.dev`
environment. [`CONTRIBUTING.md`](CONTRIBUTING.md) owns that procedure.

Run these from `packages/noir_driver/`, for the drive-mode client:

    dart format --output=none --set-exit-if-changed lib/ test/ bin/
    dart analyze --fatal-infos
    dart test --concurrency=1
    dart pub publish --dry-run

Run these from `packages/noir_signals/`, for the companion package:

    dart format --output=none --set-exit-if-changed lib/ test/ example/
    dart analyze --fatal-infos
    dart test --concurrency=1
    dart pub publish --dry-run

Each package publishes in place from its own directory. To check the
companion the way an application outside this workspace resolves it, run this
from `packages/noir/`:

    dart run tool/stage_companion_package.dart --verify

The script stages a standalone copy outside the checkout, points its `noir`
dependency at `packages/noir`, and runs the dry-run there. Pass a companion
path to stage another member:

    dart run tool/stage_companion_package.dart --verify ../noir_driver

`safe-process-spawning` tests are ordinary subprocess checks and run in the
standard suite.

For a website change, run these from `website/`:

    npm run format:check
    npm run lint
    npm run typecheck
    npm run build
    npm run test:smoke

`npm run sync` regenerates the derived documentation content; `build`, `dev`,
and `typecheck` run it first. Commit its output with the source change.
[`website/DESIGN.md`](website/DESIGN.md) owns the page templates, content
ownership, and navigation rules.

Automatic GitHub Actions runs for `push` and `pull_request` are ordinary
verification. Do not manually dispatch or rerun a workflow unless the user
explicitly asks.

Do not run any of the following without exact authorization:

- real terminal, raw-mode, PTY, ConPTY, iTerm, or visual-session automation;
- deliberate crashes, fatal signals, process-kill tests, leak profilers,
  sanitizers, Valgrind, or resource-exhaustion probes;
- native builds, artifact refreshes, ABI fault injection, or publication;
- tag, release, or manual workflow operations.

Parser fakes, headless renderers, package-consumer subprocesses, architecture
source scans, and temporary Git fixtures are ordinary checks unless they
deliberately exercise a restricted behavior.

## Widget and test rules

- Focus-owning widgets use `FocusNodeOwnerStateMixin`.
- Text editing uses `TextEditingController`.
- Pointer mapping uses render-tree hit testing and
  `MouseEvent.localPosition`.
- Painting outside local bounds uses `PaintingContext` /
  `TuiCanvas.clipRect`.
- `RenderProxyBox.child=` remains idempotent.
- Real rendering is implemented by `RenderObjectWidget` and `RenderBox`.
- Visual goldens include style and cursor sidecars unless intentionally
  text-only.
- Use `WidgetTester` for layout, `BufferCapture` for one rendered frame,
  `KeyDriver` for parsed synthetic input, and `createTuiTestApp` for binding
  integration. Do not invent a fifth harness.
- Prefer `BufferMatchers` for cell-level assertions.

## Companion package boundaries

`packages/noir_driver/` is an optional client package, not part of Noir's
archive. It depends on `package:noir/noir.dart` plus `vm_service` and
`matcher`, and never on Noir private libraries, the low-level or FFI barrels,
or native access. Noir's manifest carries it as a `dev_dependency` only, used
by the two checkout-only documentation tools under `packages/noir/tool/`, and
never as a runtime dependency. No shipped Noir source imports it.

`packages/noir_signals/` is an optional companion package, not part of Noir's
archive. Its production code imports only `package:noir/noir.dart` and the
public `signals_core` surface: no Noir private libraries, no low-level or FFI
barrels, and no native access. Noir never depends on it, and Noir's manifest
carries no Signals dependency. Its checkout-only test helpers stay out of the
published archive.

## Current release boundary

The target is the current core-framework release candidate, not a stable
1.0 claim. Its exact version is the one in `packages/noir/pubspec.yaml`, its
changes are the top section of
[`packages/noir/CHANGELOG.md`](packages/noir/CHANGELOG.md), the versions on pub.dev
are in `publication.json`, and known native limitations are on the
website's platform limitations page. The release procedure is in
[`CONTRIBUTING.md`](CONTRIBUTING.md).
