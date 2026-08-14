# Noir contributor and agent guide

Start with [`TODO.md`](TODO.md). It records the open release items, the
authorized checks, and the known limitations. [`GOALS.md`](GOALS.md) defines
the durable architecture and quality bar.

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

    dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ scripts/
    dart analyze --fatal-infos
    dart test test/architecture/ --concurrency=1
    dart test <focused test paths> --concurrency=1
    dart test --concurrency=1
    dart run scripts/fetch_opentui_binaries.dart --verify-only
    dart pub publish --dry-run

`safe-process-spawning` tests are ordinary subprocess checks and run in the
standard suite.

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

## Current release boundary

The target is a core-framework `0.0.1-alpha.0` candidate, not a stable 1.0
claim. The live gates and known native limitations are in
[`TODO.md`](TODO.md).
