# Release TODO — `0.0.1-alpha.1`

The single record of Noir's publication and remaining release operations.
Update it only with evidence from the exact reviewed tree.

Noir is **not** cleared for a tag, GitHub release, native build, manual workflow
dispatch, or public repository visibility until the applicable open items below
are closed. The pub.dev publication recorded below is complete.

## Open — remaining release operations

- [x] **Independent behavior and full-diff review** of the current candidate,
      with no unresolved finding.
- [x] **Recovery bundle and clean-clone verification** recorded: the committed
      candidate and pinned OpenTUI gitlink were restored into a fresh checkout,
      the verification commands below passed, and all six bundled binaries
      verified against `native_manifest.json`.
- [x] **Clean-tree publish dry-run** completed with zero warnings and the
      intended 15 MB archive contents, both in the workspace and clean clone.
- [x] **Manual real-terminal check** of hot reload. Ordinary verification is
      headless, so this is the only path that exercises a real TTY:
      `dart run scripts/hot_reload_driver.dart example/counter.dart`, edit a
      `build()` body, and confirm the repaint without a restart.
- [x] **Publish the current candidate to pub.dev** as a separate deliberate
      action after the candidate checks above are complete.
- [ ] **Repository visibility, tag, and GitHub release** — each remains a
      separate, deliberate decision. The repository is private today.

## Done — candidate preparation and recorded baseline

- [x] Package metadata, changelog, install guidance, contributor guidance, and
      release assertions agree on the current candidate version.
- [x] The build hook declares `native_manifest.json` and the selected bundled
      library as cache inputs, with a focused regression test.
- [x] The current manual pub.dev publication is live as `noir 0.0.1-alpha.1`.
      The public package API reports it as latest with archive SHA-256
      `71f8c0f029ec11d6e891161f375aa41a9ca86cf325740e249466c817659a2338`.
      The downloaded archive matches that hash, declares the exact version,
      contains both hook cache-input declarations, and excludes the release
      TODO, contributor-agent guidance, and GitHub workflow.
- [x] The first manual pub.dev publication is live as `noir 0.0.1-alpha.0`.
      The public package API reports the exact version and archive SHA-256
      `0b771ba4f2645f0f2375cfc208252b8195c8f7caf172a7b933ed49aa3a5ae666`.
      The downloaded public archive contains no internal documentation, tests,
      skills, workspace state, external source, or `2026`-named paths.
- [x] Fork identity, fork-only ABI, custom candidate builds, and legacy Go
      parity are absent from the tree.
- [x] Canonical nonzero `u32` handles, `u16` RGBA storage, `u32` attributes,
      cursor options, and render statuses are guarded at the Dart boundary.
- [x] High-level text painting uses one grapheme-safe direct-run path for full
      and source-clipped layouts.
- [x] The shipped health check is headless, portable ASCII, and validated from
      an isolated downstream package.
- [x] Automatic `push`/`pull_request` CI is analysis-gated, bounded,
      least-privilege, and immutable-action pinned. Platform suites run in
      parallel after the gate; manual dispatch and rerun remain controlled.
- [x] Format, strict analysis, 157 architecture tests, the 1272-test ordinary
      suite, downstream-consumer checks, native-asset verification, and diff
      checks pass on the committed candidate and clean clone. Documentation has
      zero warnings and errors, and both clean-tree publish dry-runs validate
      the intended 15 MB archive with zero warnings.
- [x] Authorized Conductor-terminal checks render every cataloged entrypoint.
      Post-change VS Code checks exercised Select keyboard selection, ScrollBox
      navigation, the inherited `t` toggle, a sustained pulse run, and
      framework-primitives Enter/Space activation. The Flutter-style counter's
      broader live sequence was `0 -> 1 -> 0 -> 1 -> 0 -> 1 -> 2 -> 3` across
      Up, Down, `+`, `-`, Enter, Space, and a real left click for the final
      `2 -> 3` transition. Its polish pass compared the original and final VS
      Code frames, confirming a middle-row title, flat app bar without a bottom
      rule, and one solid 7x3 action surface. Up advanced `0 -> 1`; a real left
      click on a non-glyph corner cell advanced `1 -> 2` exactly once. Initial
      and incremented polished frames were captured, and Ctrl+C restored a
      usable shell without a stack trace. Parser-backed widget checks separately
      prove Select click selection, ScrollBox wheel movement, the inherited
      ocean/white-to-forest/yellow notification, pulse completion/reversal, and
      the framework-primitives local-pointer path. Direct pointer observation
      is recorded for the counter only; the Select, ScrollBox, and
      framework-primitives pointer assertions remain automated.
- [x] Analysis-gated CI on `main` is green across format/analyze, Ubuntu,
      macOS, and Windows.

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

- Dart 3.10 supplies native-asset hooks with a macOS deployment target of 12,
  while the bundled libraries require macOS 13. The normal CLI build has no
  target-version override, so Noir documents macOS 13 and permits the build;
  macOS 12 can fail later when loading the native library.
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
  Observed via a drive-mode sweep: `example/layout_demo.dart` paints stray
  border fragments below its footer at 80x24.
- `RenderDecoratedBox` lays its child out with its own constraints rather than
  insetting them by the border, so when content fills the box it paints over
  the border cells. Observed: `example/focus_form.dart` at 24x8 merges the
  outer bottom border with an inner field's top border on one row. Flutter
  insets the child by the decoration's border; adopting that changes layout
  for every bordered container and needs its own reviewed pass.
- `example/bindings_validation.dart` requires a real terminal stdin lease by
  design and exits with code 70 under drive mode; it is the one example the
  drive tool cannot run.
- Some low-level native operation failures cannot be reported precisely to
  Dart.
- Hot reload is bounded by what the Dart VM can swap into a live isolate.
  `TuiApp.reassemble()` re-runs `build()`, layout, and paint bodies only; it
  never re-runs `main()` or `initState`, so changes to those, to a signature
  held by a frame on the stack, to an enum converted into a class, or to the
  bundled OpenTUI native library still require a full restart.
- Drive mode (`NOIR_DRIVE=1`) is headless by construction. It exercises the
  same layout, paint, and ANSI-parser paths the ordinary suite trusts, but it
  never proves real terminal escape rendering or raw-mode input. A continuously
  animating app never reports `stable: true`, an app whose own quit path calls
  `io.exit` ends the driven session, and `reload` inherits the `reassemble()`
  limits recorded below.
- `scripts/noir_drive.dart` has no automated coverage. The drive-mode seam it
  drives is proven by `test/app/driver_test.dart` and
  `test/driver_e2e_test.dart`, which spawns an unmodified consumer app under
  `NOIR_DRIVE=1` and drives it over the VM service, and the client encoders and
  capture parsing are proven by `test/driver_client_test.dart`. The CLI command
  grammar itself is only exercised by running it.
- `scripts/hot_reload_driver.dart` has no automated coverage. The reassemble
  seam it drives is proven by `test/hot_reload_e2e_test.dart`, which performs a
  real `reloadSources` against a spawned headless app and asserts that the
  source swap alone changes no rendered output while the extension call does.
  The driver itself is only exercised by the manual check listed above.

## Non-blocking follow-ups

- Decide the macOS deployment-target policy before beta or stable once Dart
  offers a supported way to request the package's native deployment floor.
- Execute downstream smoke tests on the three shipped OS/architecture
  combinations not exercised by the ordinary host-runner matrix.
- Add a lower-bound lane that runs analysis and focused hook tests after
  `dart pub downgrade` when practical.
