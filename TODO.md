# Release TODO — `0.0.1-alpha.5`

The single record of Noir's publication and remaining release operations.
Update it only with evidence from the exact reviewed tree.

`0.0.1-alpha.4` is **published**. It shipped from exact `main` commit
`86dc43d6564ccc4723c37d2d24607eadf7dd7c67`, tagged
`v0.0.1-alpha.4`, through GitHub Actions run
[`33680362083`](https://github.com/conceptadev/noir/actions/runs/33680362083).
The public archive SHA-256 is
`833df9c82d5077913e3755b2f78d82d6f9625f0291b590be27315763ae60ed06`.
This distribution correction changes package contents and documentation
without changing Noir's public API shapes or runtime behavior, native ABI, or
bundled native artifacts.

`0.0.1-alpha.3` is **published**. It shipped from commit
`967820b47f3e8ad2c2ab94b84245f5e2f7d3b445`, built from a verified clean clone
of that exact commit and tagged `v0.0.1-alpha.3`. Unpublished `0.0.1-alpha.2`
was skipped: that work shipped first in `0.0.1-alpha.3`.

The repository stays private. A historical GitHub prerelease exists for
`v0.0.1-alpha.1`; alpha.3 and alpha.4 have no GitHub releases, and the next
GitHub release remains deferred to beta.1. Neither repository visibility nor
that next release is cleared by this publication.

## Released — `0.0.1-alpha.4`

Every gate below was closed on the exact tagged candidate
`86dc43d6564ccc4723c37d2d24607eadf7dd7c67`.

- [x] **Version and release record**: `pubspec.yaml`, `CHANGELOG.md`, live
      example copy, and durable limitation guidance agree on alpha.4.
      Historical alpha.3 records and recording fixtures remain pinned.
- [x] **Independent behavior and diff review**: the final review found no
      blocker, weakened test, or filler prose. Public barrels, native ABI and
      binaries, `native_manifest.json`, and the OpenTUI gitlink have no delta
      from alpha.3. Outside the relocated checkout-only Patch Manager, the
      remaining framework edits are a dartdoc qualifier removal and
      semantics-preserving collection-if rewrites.
- [x] **Exact-tree automated gates**: format and fatal-info analysis passed;
      203 architecture tests and the 2,211-test serial suite passed; all six
      binaries matched `native_manifest.json`; action lint and diff checks
      passed. Dartdoc reported zero errors and eight package-root link
      warnings. The clean 15 MB publish dry-run reported zero warnings and
      included `LICENSE-YOGA`.
- [x] **GitHub candidate gates**: release PR
      [#38](https://github.com/conceptadev/noir/pull/38) passed analysis,
      website build and browser smoke, Linux, macOS, and Windows checks. The
      exact merge commit passed the same platform CI in run
      [`33679453031`](https://github.com/conceptadev/noir/actions/runs/33679453031),
      and Pages deployed it in run
      [`33679452993`](https://github.com/conceptadev/noir/actions/runs/33679452993).
- [x] **Automated publishing configuration**: the authenticated pub.dev admin
      page confirmed GitHub Actions publishing for `conceptadev/noir`, tag
      pattern `v{{version}}`, and push events. The repository's pinned inline
      `publish.yml` trigger matches that configuration.
- [x] **Publish and verify**: annotated tag `v0.0.1-alpha.4` points to the exact
      reviewed commit. The repaired OIDC workflow passed both jobs and pub.dev
      attributes publication to its run, revision, and repository. The
      downloaded public archive matches the API hash above, declares alpha.4,
      includes a byte-identical `LICENSE-YOGA` and the Yoga v3.2.1 notice, and
      excludes repository-only scripts, tests, website, and release records.

## Published alpha.3 notice correction

A post-release archive audit confirmed that the published `0.0.1-alpha.3`
archive omitted Yoga v3.2.1's MIT license notice even though the bundled
OpenTUI native libraries compile Yoga sources. The published alpha.4 archive
includes the missing notice, but cannot change the already-published alpha.3
archive. Retracting alpha.3 was not part of this release.

## Released — `0.0.1-alpha.3`

Every gate below was closed on the exact candidate
`967820b47f3e8ad2c2ab94b84245f5e2f7d3b445`, with a clean worktree. Terminal
evidence is under `.context/terminal-evidence/20260902T005512Z-967820b/`.

- [x] **OpenTUI component parity (Phases 1–2)**: Image, ASCII-font licensing,
      Stack/Positioned, Wrap, TabSelect, Slider, TextTable, semantic
      hyperlinks, OSC52, document selection, CodeView, DiffView, MarkdownView,
      and the Patch Manager presentation migration shipped in this alpha.3
      tree. The historical phase-gate write-ups remain in the recorded
      baseline below.
- [x] **Independent behavior and full-diff review** of the pre-alpha.3
      parity work. Alpha.3 still needs its own exact-tree verification below.
- [x] **Parity external gates**: run under explicit authorization on the
      candidate. Passed: Kitty direct with the automatic protocol, OSC52
      acceptance, legacy Ctrl+A/C, the 80x24 to 30x12 to 80x24 resize and crop
      cycle, forced Kitty graphics direct, and the Kitty counter smoke with
      raw input, repaint, resize, and graceful exit. Forced Kitty graphics
      through tmux reproduced the documented limitation: the image sat 38 px
      high and overlapped the header, then placed correctly after the resize.
      **Accepted as residual, not run:** Sixel, GNU Screen, and OSC52 through
      tmux. The last was blocked because the clipboard guard could not
      snapshot a macOS Universal Clipboard item and failed closed rather than
      touch a clipboard it could not restore.
- [x] **Recovery bundle and clean-clone verification**: a fresh clone of the
      candidate with the pinned OpenTUI gitlink restored passed format,
      `analyze --fatal-infos`, 191 architecture tests, the 2,199-test serial
      suite, and verification of all six bundled binaries against
      `native_manifest.json`.
- [x] **Clean-tree publish dry-run**: zero warnings from the clean clone,
      with the intended 15 MB archive.
- [x] **Manual real-terminal check** of hot reload: passed on a real TTY.
      `dart run noir:run example/counter.dart`, the counter driven to `2`, then
      a `build()` body edited. The new text rendered and the counter still read
      `2`; a restart resets it to `0`, so the preserved state proves
      reassembly. `run.log` recorded `connected to the app VM service`,
      `watching`, then `reloaded`.
- [x] **Publish `0.0.1-alpha.3` to pub.dev**: published from the verified
      clean clone of the candidate. `0.0.1-alpha.2` was not published.
- [x] **Tag**: `v0.0.1-alpha.3` annotated on the candidate and pushed.
- [ ] **Repository visibility and next GitHub release** — each remains a
      separate, deliberate decision. The repository stays private through this
      alpha. A historical prerelease exists for `v0.0.1-alpha.1`; alpha.3 has
      no GitHub release, and the next one is deferred to beta.1.

## Done — recorded baseline (alpha.2 work ships first in alpha.3)

- [x] **Phase 1 Image automated gate**: `TerminalImage`, all five source
      forms, ownership/cancellation, fit modes, display-list/native drawing,
      pixel-resolution reporting, deterministic drive capture, and public
      guidance are implemented. On the combined parity tree, format,
      fatal-info analysis, 173 architecture tests, the 1685-test serial suite,
      native verify-only, and archive validation pass. The clean committed-tree
      publish dry-run validates the intended 15 MB archive with zero warnings.
- [x] **ASCII font licensing disposition**: the third-party font tables,
      generated copy, generator, and GPL notice were removed. `AsciiFont` now
      derives all seven visual families from Noir's original 5x7 printable-
      ASCII alphabet under the package's BSD-3-Clause license.
- [x] **Phase 2 automated gate**: `Stack`/`Positioned`, `Wrap`, `TabSelect`,
      `AsciiFont`, `Slider`, `TextTable`, semantic hyperlinks, OSC52 clipboard,
      grapheme-safe document selection, `CodeView`, unified/split `DiffView`,
      GitHub-flavoured `MarkdownView`, and the Patch Manager presentation
      migration are implemented. The 247 focused parity and boundary checks,
      all 163 Patch Manager regressions, all 173 architecture tests, and the
      1685-test full serial suite pass. Both FFI generators are byte-idempotent;
      the authored ASCII glyph source, ABI, all six bundled binaries, package
      contents, and diff whitespace validate.
- [x] **Independent behavior and full-diff review** of the pre-alpha.3
      parity candidate accepted the exact implementation and evidence
      snapshot with no unresolved blocker or material drift.
- [x] **Locator-based drive refinement**: drive mode retains its seven-method
      byte-input surface while adding parser-backed Shift+Tab/Home/End/Delete,
      structured exact-key/text/focus snapshots with private driver-owned text
      extraction, fresh client-side locators, visibility-safe locator clicks
      that credit both production `HitTestResult.path` `RenderObject` targets
      and RenderBox visit lineage, CLI grammar coverage, and keyed-control
      VM-service E2E coverage. A custom low-level `HitTestTarget` that is not
      a `RenderBox` shares the same cell for ordinary dispatch and locator
      clicks; the review blocker on that equivalence is closed. Interactive
      examples expose `ValueKey<String>` on primary controls, catalog drive
      smoke and keyed locator E2E cover the shipped entrypoints, and zero-match
      errors list nearby keys, exact runtime types, and a missing primary-focus
      hint. Clean-build CLI captures tolerate Dart hook status on the first
      JSON line, and input settles after its post-dispatch frame baseline even
      while the app animates. As-built docs lock own-route hit points,
      painted-vs-source text, CLI tree defaults to depth 2, and reject leftover
      ancestor-point and diagnostic-provider specs. On this tree, format and
      fatal-info analysis, 177 architecture tests, the 1738-test serial suite,
      and diff checks pass.
- [x] Package metadata, changelog, install guidance, contributor guidance, and
      release assertions agree on the current candidate version.
- [x] The build hook declares `native_manifest.json` and the selected bundled
      library as cache inputs, with a focused regression test.
- [x] The packaged `dart run noir:run` command owns the VM-service hot-reload
      loop for repository examples and downstream packages, with headless
      process coverage for argument forwarding, reload, rejection recovery,
      diagnostics, and exit-code propagation.
- [x] The published alpha.1 baseline is live as `noir 0.0.1-alpha.1`. At the
      recorded publication check, the public package API reported it as latest
      with archive SHA-256
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
- [x] For the published alpha.1 baseline, format, strict analysis, 157
      architecture tests, the 1272-test ordinary suite, downstream-consumer
      checks, native-asset verification, and diff checks passed on the committed
      candidate and clean clone. Documentation had zero warnings and errors,
      and both clean-tree publish dry-runs validated the intended 15 MB archive
      with zero warnings.
- [x] On the combined alpha.2 hooks-and-parity tree, 96 focused hook API,
      ownership, example, and downstream-consumer checks pass. The opt-in
      `package:noir/hooks.dart` surface (moved to `noir_signals` in alpha.5),
      guide, skill, example, and complete
      regression suite from `main` remain present alongside the parity work.
- [x] The pre-parity alpha.2 hook tree passed its authorized manual
      real-terminal hot-reload check. Because the combined parity candidate
      also changes terminal binding/session behavior, its exact-tree repeat
      remains an open gate above rather than reusing that earlier result.
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
- Forced Kitty graphics through tmux are unsupported. The initial placement
  can overlap existing content and remain displaced until a resize;
  `ImageProtocol.auto` uses block cells under tmux and is the supported path.
- The official Linux release libraries retain absolute build/debug paths. This
  is visible upstream artifact metadata, not a Noir rebuild output.
- A decorated box that straddles a clipped viewport edge paints its full
  border. `Buffer.clipped` drops boxes that miss the clip entirely, but the
  pinned `drawBox` writes transparent-background borders via an unchecked
  index (`canUseTransparentBorderFastPath`), so a straddling box escapes even
  OpenTUI's native scissor rect. Noir does not re-rasterize the box in Dart:
  that would duplicate native glyph, corner, and title placement rules.
- `RenderDecoratedBox` lays its child out with its own constraints rather than
  insetting them by the border, and paint-clips the child to the decoration's
  inner rect so a filling child cannot erase the border. Flutter's layout
  inset is deliberately not adopted: it would resize every bordered child and
  re-open the tight-box collapse that `Container`'s documented
  `max(padding, border)` rule (`lib/src/widgets/container.dart`) avoids.
  `Container` owns the layout side; `DecoratedBox` only guarantees the clip.
- The pinned native opacity stack does not fade ordinary text. `bufferDrawText`
  takes an ASCII fast path whenever the foreground and background are both
  fully opaque, writing cells directly and skipping the opacity funnel, so any
  value in `(0.0, 1.0)` paints identically to `1.0`; only `0.0` reads as
  transparent, through a separate early-out. Blending is observable through
  `bufferSetCellWithAlphaBlending` and `bufferFillRect`. `bufferPushOpacity` is
  bound on `noir_ffi` for availability, but an `Opacity` widget cannot be built
  on it alone. Both stacks also compose rather than replace — a nested scissor
  intersects, a nested opacity multiplies — and `drawFrameBuffer` reads the
  destination's stacks while ignoring the source's, so pushing opacity onto an
  offscreen layer has no effect.
- `example/bindings_validation.dart` requires a real terminal stdin lease by
  design and exits with code 70 under drive mode; it is the one example the
  drive tool cannot run.
- Some low-level native operation failures cannot be reported precisely to
  Dart.
- Hot reload is bounded by what the Dart VM can swap into a live isolate.
  `TuiApp.reassemble()` invokes `State.reassemble()` on every retained state
  and re-runs `build()`, layout, and paint bodies; it never re-runs `main()` or
  `initState`, so changes to those, to a signature held by a frame on the
  stack, to an enum converted into a class, or to the bundled OpenTUI native
  library still require a full restart. Overriding `State.reassemble()` is the
  supported way to re-derive what an `initState` body computed. A failing
  override is reported to the surrounding zone and does not cost the reload its
  rebuild or repaint.
- Drive mode (`NOIR_DRIVE=1`) is headless by construction. It exercises the
  same layout, paint, and ANSI-parser paths the ordinary suite trusts, but it
  never proves real terminal escape rendering or raw-mode input. A continuously
  animating app never reports `stable: true`, an in-app `TuiApp.exit` ends the
  driven session (the host follows the binding down), and `reload` inherits
  the `reassemble()` limits described above.
- The line-oriented drive CLI trims outer command whitespace, so an exact key,
  type, or text locator cannot itself begin or end with whitespace. The Dart
  client preserves those values exactly.
- Drive mode is covered in-process by `test/app/driver_test.dart` and against
  an unmodified consumer by `test/driver_e2e_test.dart`. Client encoders and
  capture parsing are covered by `test/driver_client_test.dart`, the CLI
  grammar by `test/noir_drive_cli_test.dart`, and shipped examples by
  `test/example/drive_catalog_test.dart`.
- The packaged hot-reload runner is covered downstream by
  `test/bin/run_test.dart`, including a real source swap, Noir reassembly,
  compile-error recovery, diagnostics, argument forwarding, and process exit.
  `test/hot_reload_e2e_test.dart` separately proves the underlying VM-service
  contract. Neither headless test validates alternate-screen rendering or
  real-terminal input; that remains the manual check listed above.

## Non-blocking follow-ups

- Decide the macOS deployment-target policy before beta or stable once Dart
  offers a supported way to request the package's native deployment floor.
- Execute downstream smoke tests on the three shipped OS/architecture
  combinations not exercised by the ordinary host-runner matrix.
- Add a lower-bound lane that runs analysis plus focused widget-hook and
  native-asset build-hook tests after `dart pub downgrade` when practical.
