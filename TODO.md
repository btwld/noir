# Release TODO — `0.0.1-alpha.3`

The single record of Noir's publication and remaining release operations.
Update it only with evidence from the exact reviewed tree.

Noir is **not** cleared for publication, a tag, GitHub release, native build,
manual workflow dispatch, or public repository visibility until the applicable
open items below are closed. The previous pub.dev publications recorded below
are complete; `0.0.1-alpha.2` is not published.

This alpha.3 development tree is not eligible to land or release until the
reviewed alpha.2 candidate completes the blocking operations below. The
alpha.2 evidence remains recorded verbatim; alpha.3 verification must be added
from its own exact candidate tree rather than reusing those results.

## Blocking prerequisite — alpha.2 OpenTUI component parity program

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
- [ ] **Parity external gates**: obtain explicit authorization before direct
      Kitty, Sixel, tmux, Screen, OSC52, resize/crop, or other real-terminal
      checks, then record the results from the exact candidate tree.

## Blocking prerequisite — remaining alpha.2 release operations

- [x] **Independent behavior and full-diff review** of the alpha.2 parity
      candidate accepted the exact implementation and evidence snapshot with
      no unresolved blocker or material drift.
- [ ] **Recovery bundle and clean-clone verification**: restore the committed
      alpha.2 candidate and pinned OpenTUI gitlink into a fresh checkout, run
      the verification commands below, and verify all six bundled binaries
      against `native_manifest.json`.
- [ ] **Clean-tree publish dry-run** with zero warnings and the intended
      archive contents, repeated from the clean clone.
- [ ] **Manual real-terminal check** of hot reload. Ordinary verification is
      headless, so this is the only path that exercises a real TTY:
      `dart run noir:run example/counter.dart`, edit a `build()` body, and
      confirm the repaint without a restart. Runner diagnostics are recorded
      in `.dart_tool/noir/run.log`.
- [ ] **Publish `0.0.1-alpha.2` to pub.dev** as a separate deliberate action
      after the candidate checks above are complete.
- [ ] **Repository visibility, tag, and GitHub release** — each remains a
      separate, deliberate decision. The repository is private today.

## Done — alpha.2 candidate preparation and recorded baseline

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
      `package:noir/hooks.dart` surface, guide, skill, example, and complete
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
- `scripts/noir_drive.dart` has no automated coverage. The drive-mode seam it
  drives is proven by `test/app/driver_test.dart` and
  `test/driver_e2e_test.dart`, which spawns an unmodified consumer app under
  `NOIR_DRIVE=1` and drives it over the VM service, and the client encoders and
  capture parsing are proven by `test/driver_client_test.dart`. The CLI command
  grammar itself is only exercised by running it.
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
