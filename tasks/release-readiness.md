# 1.0 release readiness

Target: `1.0.0-alpha.1`.

Status: canonical OpenTUI v0.5.1 migration and clean-private-`main` cutover are
in progress. Noir is not cleared for a tag, GitHub release, pub.dev
publication, native build, manual workflow dispatch, or public visibility.

## Current dependency boundary

- `external/opentui` is read-only at canonical commit
  `ad9a818d7a9d73f3386e92a445d0feb4b395c69e` (`v0.5.1`).
- The six tracked libraries are the unchanged official release assets. Dart
  linked builds bundle those files directly on Linux/Windows. On macOS, the
  official Mach-O has no load-command padding, so the build hook removes the
  optional `LC_SOURCE_VERSION` command from a disposable output copy before
  Dart performs its normal relocatable install-name rewrite and ad-hoc signing;
  the tracked official bytes and manifest hashes remain unchanged.
- `native_manifest.json` records the canonical repository, tag, commit,
  archive URL/hash/member, extracted-library hash, macOS 13.0 floor, and Linux
  glibc 2.17 floor.
- Future source, gitlink, manifest, native artifacts, or ABI changes require a
  separate explicit dependency-strategy decision.

## Alpha gates

- [x] Fork identity, fork-only ABI, custom candidate builds, and legacy Go
      parity are absent from the candidate tree.
- [x] Canonical nonzero `u32` handles, `u16` RGBA storage, `u32` attributes,
      cursor options, and render statuses are guarded at the Dart boundary.
- [x] High-level text painting uses one grapheme-safe direct-run path for full
      and source-clipped layouts.
- [x] The shipped health check is headless, portable ASCII, and validated from
      an isolated downstream package.
- [x] Automatic `push`/`pull_request` CI is staged, bounded, least-privilege,
      and immutable-action pinned. Manual dispatch and rerun remain controlled.
- [ ] Final format, strict analysis, architecture, ordinary-suite, asset,
      documentation, downstream-consumer, publish-dry-run, and diff checks are
      recorded against the reviewed tree.
- [ ] Independent behavior and full-diff review has no unresolved finding.
- [ ] The implementation branch and clean `main` staged CI runs are green.
- [ ] A verified recovery bundle and clean-clone verification are recorded.

## Retained limitations

- The pinned native `bufferDrawText` encoder mishandles a run beginning with a
  source-level zero-width grapheme: observed examples emit UTF-8 continuation
  bytes as cells and advance before following text. Noir retains OpenTUI's
  source-correct zero-width layout semantics, so a leading or style-isolated
  zero-width grapheme can diverge from native paint until fixed upstream.
- The pinned native lifecycle has an exact-cursor restoration limitation on an
  observed macOS/iTerm path. Noir retains exception-safe cleanup and does not
  duplicate native ownership with an ANSI workaround.
- The official Linux release libraries retain absolute build/debug paths.
  This is visible upstream artifact metadata, not a Noir rebuild output.
- Real terminal, PTY/ConPTY, raw-mode, signal/termination, crash, sanitizer,
  and leak checks are outside ordinary verification and were not authorized by
  this migration.
- The repository remains private. Public visibility, tags, releases, and the
  first manual pub.dev publication remain separate decisions.

## Completion record

Update this section only with evidence from the exact reviewed tree and clean
`main` clone. Do not carry forward historical fork-candidate evidence.
