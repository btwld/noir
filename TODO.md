# Release TODO — `1.0.0-alpha.1`

The single record of what remains before Noir is published. Update it only with
evidence from the exact reviewed tree.

Noir is **not** cleared for a tag, GitHub release, pub.dev publication, native
build, manual workflow dispatch, or public visibility until the open items
below are closed.

## Open — required before publishing

- [x] **Independent behavior and full-diff review** of the release tree, with
      no unresolved finding.
- [x] **Recovery bundle and clean-clone verification** recorded: clone the
      repository fresh, run the verification commands below, and confirm the
      bundled binaries verify against `native_manifest.json`.
- [x] **Manual real-terminal check** of hot reload. Ordinary verification is
      headless, so this is the only path that exercises a real TTY:
      `dart run scripts/hot_reload_driver.dart example/counter.dart`, edit a
      `build()` body, and confirm the repaint without a restart.
- [ ] **Repository visibility, tag, GitHub release, and the first manual
      pub.dev publication** — each a separate, deliberate decision. The
      repository is private today.

## Done — recorded against the reviewed tree

- [x] Fork identity, fork-only ABI, custom candidate builds, and legacy Go
      parity are absent from the tree.
- [x] Canonical nonzero `u32` handles, `u16` RGBA storage, `u32` attributes,
      cursor options, and render statuses are guarded at the Dart boundary.
- [x] High-level text painting uses one grapheme-safe direct-run path for full
      and source-clipped layouts.
- [x] The shipped health check is headless, portable ASCII, and validated from
      an isolated downstream package.
- [x] Automatic `push`/`pull_request` CI is staged, bounded, least-privilege,
      and immutable-action pinned. Manual dispatch and rerun remain controlled.
- [x] Format, strict analysis, architecture, ordinary-suite, asset,
      documentation, downstream-consumer, publish-dry-run, and diff checks pass
      on the reviewed tree: 1234 ordinary tests, 0 analyzer issues, 0 publish
      warnings, `native_manifest.json` plus six binaries verified.
- [x] Authorized Conductor-terminal checks render the counter, textarea, and
      widgets tour, then return to a usable shell without stack traces through
      both normal Escape disposal and unconsumed Ctrl+C interruption.
- [x] Staged CI on `main` is green across format/analyze, Ubuntu, macOS, and
      Windows.

## Verification commands

    dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ scripts/
    dart analyze --fatal-infos
    dart test test/architecture/ --concurrency=1
    dart test --concurrency=1
    dart run scripts/fetch_opentui_binaries.dart --verify-only
    dart pub publish --dry-run
    git diff --check

Real terminal, PTY/ConPTY, raw-mode, signal/termination, crash, sanitizer, and
leak checks stay outside ordinary verification and require explicit
authorization.

## Dependency boundary

- `external/opentui` is read-only at canonical commit
  `ad9a818d7a9d73f3386e92a445d0feb4b395c69e` (`v0.5.1`).
- The six tracked libraries are the unchanged official release assets. Dart
  linked builds bundle those files directly on Linux/Windows. On macOS, the
  official Mach-O has no load-command padding, so the build hook removes the
  optional `LC_SOURCE_VERSION` command from a disposable output copy before
  Dart performs its normal relocatable install-name rewrite and ad-hoc signing;
  the tracked official bytes and manifest hashes remain unchanged.
- `native_manifest.json` records the canonical repository, tag, commit, archive
  URL/hash/member, extracted-library hash, macOS 13.0 floor, and Linux glibc
  2.17 floor.
- Future source, gitlink, manifest, native artifacts, or ABI changes require a
  separate explicit dependency-strategy decision.

## Known limitations carried into the release

- The pinned native `bufferDrawText` encoder mishandles a run beginning with a
  source-level zero-width grapheme: observed examples emit UTF-8 continuation
  bytes as cells and advance before following text. Noir retains OpenTUI's
  source-correct zero-width layout semantics, so a leading or style-isolated
  zero-width grapheme can diverge from native paint until fixed upstream.
- The pinned native lifecycle has an exact-cursor restoration limitation on an
  observed macOS/iTerm path. Noir retains exception-safe cleanup and does not
  duplicate native ownership with an ANSI workaround.
- The official Linux release libraries retain absolute build/debug paths. This
  is visible upstream artifact metadata, not a Noir rebuild output.
- Decorated box content can escape a clipped viewport in some overflow cases.
- Some low-level native operation failures cannot be reported precisely to
  Dart.
- Hot reload is bounded by what the Dart VM can swap into a live isolate.
  `TuiApp.reassemble()` re-runs `build()`, layout, and paint bodies only; it
  never re-runs `main()` or `initState`, so changes to those, to a signature
  held by a frame on the stack, to an enum converted into a class, or to the
  bundled OpenTUI native library still require a full restart.
- `scripts/hot_reload_driver.dart` has no automated coverage. The reassemble
  seam it drives is proven by `test/hot_reload_e2e_test.dart`, which performs a
  real `reloadSources` against a spawned headless app and asserts that the
  source swap alone changes no rendered output while the extension call does.
  The driver itself is only exercised by the manual check listed above.
