# 1.0 release readiness

Target: `1.0.0-alpha.1`.

Status: the source and package are a locally verified alpha candidate. They are
not cleared for public pub.dev publication, beta, or stable 1.0. Do not tag,
publish, create a GitHub release, enable workflows, or refresh native artifacts
from this checklist; each is a separate authorized operation.

Phase 2 candidate builds completed under the reviewed hybrid method in
[`2.0-native-build-contract.md`](2.0-native-build-contract.md) and the
[`2.1 implementation plan`](2.1-native-build-implementation-plan.md). Run
`20260812T135653Z-9e981ca2` used the pinned runner and
`llvm-strip --discard-all` normalization, passed all twelve builds and gates,
and designated six byte-identical root-pair candidates. Its evidence and
recovery material were hash-verified under `~/noir-release-recovery/`. The
candidate set is evidence only: no tracked native artifact, manifest, ABI,
generated binding, OpenTUI source, or gitlink was replaced.

## Alpha gates

- [x] Terminal input is acquired before native capability queries; inherited
      modes are restored exactly and every reply class is routed internally.
- [x] Incremental ANSI/control and bracketed-paste state has a bounded,
      recoverable drop policy.
- [x] Kitty input rejects non-scalar Unicode values.
- [x] Every guarded fixed-width FFI argument rejects values that would narrow,
      without making renderer disposal non-atomic.
- [x] Low-level TextBuffer native views are observably read-only.
- [x] The shipped health check is headless/control-clean and fails on cleanup
      errors.
- [x] Safe subprocess tests run in the ordinary suite; the restricted lifecycle
      wrapper has a unique explicit tag.
- [x] Package metadata, changelog, README, workflow templates, and tests agree
      on the alpha version and install story.
- [x] macOS 15.0 is recorded and verified as the bundled dylib floor.
- [x] Format, strict analysis, architecture tests, ordinary tests, manifest
      verification, package dry-run, dartdoc, Pana, actionlint, and diff checks
      pass.

## Public-distribution blockers

- Both Linux libraries contain absolute build/debug paths. Public publication
  should wait for an explicitly authorized reproducible artifact refresh or a
  deliberate artifact-provenance decision.
- `leoafarias/noir` is private. Anonymous users receive 404 responses for the
  repository, issue tracker, README examples, and notices linked by package
  metadata. Keep private Git/path distribution, or make a separate repository
  visibility and public-link decision before pub.dev publication.
- Pub.dev does not allow automated publishing for a package's first version.
  The first Noir version requires a separately authorized manual publication;
  the checked-in trusted-publisher workflow applies only to later versions.
  See [pub.dev automated publishing](https://dart.dev/tools/pub/automated-publishing).

## Other retained limitations

- The pinned native lifecycle can restore the main screen at the wrong cursor
  position on an observed macOS/iTerm path. Noir still owns exception-safe
  best-effort cleanup. Exact terminal-byte/cursor acceptance has not been run.
- The six native artifacts, hashes, URLs, ABI, and submodule pin are read-only
  in this preparation pass.
- GitHub Actions were explicitly enabled solely to validate the bounded
  pull-request CI. The `Native build wrapper` job for recipe commit
  `bf60a1b214e4824ad371160a79bff3c2cd0b3f8c` passed in 28 seconds; the overall
  existing workflow remains red because its Ubuntu and Windows ordinary-suite
  jobs retain unrelated platform failures. No release or publication workflow
  was dispatched. The GitHub-release workflow remains manual and accepts only
  an existing, version-matching tag. The official setup-dart publisher is
  pinned at its outer reusable-workflow commit, but that upstream workflow
  currently uses a mutable checkout action and floating SDK internally.
- Pathologically fragmented near-limit paste input remains memory-bounded but
  can repeat copying and parsing work.

## Beta gates

- Close the retained beta correctness findings in text/grapheme painting,
  editing boundaries, trailing-newline layout, resize visibility, animation
  callback isolation, and capability detection.
- Run the current release candidate on supported Linux, macOS, and Windows
  targets, including macOS 15.0 or later.
- Resolve or explicitly accept the Linux artifact-provenance issue.

## Stable gates

- Close or deliberately redesign the retained public-contract findings around
  immutable value inputs, decoration promises, direct buffer semantics,
  exception-safe UTF-8 replacement, and scroll callback semantics.
- Complete a beta soak.
- Analyze the exact publish archive from a clean downstream consumer.
- Make an explicit dependency-strategy decision for the pinned native
  cursor-restoration limitation.

## Phase 2 candidate evidence

Successful run `20260812T135653Z-9e981ca2` records:

- Noir recipe commit `bf60a1b214e4824ad371160a79bff3c2cd0b3f8c`, tree
  `be05c0198b25ce10f803fee3958184ddcc5571e8`, and recipe digest
  `bc688ab8861588e4cd067163519821d0086b07a95cb182f0a1b014dd736a08a0`;
- OpenTUI commit `ddbc9edf81a1fa89961135ab0481df15054ed4b0` and tree
  `3d35a9ef9a77ca7e1768d2fbe7191522fe7f59cc`;
- runner image digest
  `sha256:2ef1eeb6c3278e45d9e0e75518dcce4ba41e2bb48a792a4bd258d772e60595c8`
  and runner archive SHA-256
  `79ce1abe9850024270af6d78471a337260a0dd69af87f1667e03228a72c8291a`;
- local evidence at
  `.context/native-build-runs/20260812T135653Z-9e981ca2/evidence` and the
  externally preserved mirror at
  `~/noir-release-recovery/20260812T135653Z-9e981ca2`;
- evidence-inventory SHA-256
  `c3a48dc7297c425cbd783dcf8ea4d89838bcf37660d57ada3da446fa243f293b`
  and mirror-verification report SHA-256
  `282f4bc0d304ee713110aff7ba307b6cce67ba2d356fcfe16bfa7827cefc26db`;
  all 151 mirrored files were independently rehashed successfully; and
- bounded GitHub Actions run `31564383894`, job `94013215756`, passed without
  building, publishing, or uploading native candidates.

Matched normalized candidates:

```text
x86_64-linux     5549d0e11d817cda414870702e9bb3042b4c8c8f65309491635a1d1ab5dd757b
aarch64-linux    84d8c12a161b900e67eb2a2d2b32d08c2a4b5b5d1f1c8244e892bc0ae922947b
x86_64-macos     13a8f9d133f064b7f77cd7d3b01b7f6552e64a038b05af00b461ff87d5c27dd2
aarch64-macos    3bf6535cdd01860662dc2a1a592c9f38ce0a3e5880e563abcd02a3a30207db4a
x86_64-windows   e7a99c2c50b3e0d4ef9b483509b5fadbf01095fa0d867505a52b17788ae64a0e
aarch64-windows  feaa2c7ab9cedf554de5492dcf4f127e241edd4f62893d69602e74b2c8c731de
```

Both roots passed static format/architecture inspection, the exact required
export inventory, path scans, macOS 15.0 floors, ABI 2 host health, package
snapshot health, and compiled packaged-CLI health. The protected-path record
proves identical before/after hashes for the tracked manifest, six bundled
libraries, ABI contract, bindings, native symbol inventory, and OpenTUI
gitlink. `trackedArtifactsReplaced` is `false`.

## Phase 1 final candidate evidence

The private preparation commit, tree, recovery bundle, source archive,
inventory, native hashes, tool versions, and dated Phase 1 checks are recorded
in [`1.0-preparation-evidence.md`](1.0-preparation-evidence.md).

Repository and content review:

- Baseline `dbf4d30ebfd9a119f1b0306a30d9900561e8de2e`: all 593 tracked entries
  inventoried and reviewed across runtime, tests, native assets, documentation,
  agent configuration, workflows, and package configuration.
- No assistant attribution, placeholder comment marker, tracked secret, CRLF
  file, empty tracked file, broken symlink, or broken local Markdown target was
  found. Obsolete phase/session plans and the vendored generic OpenTUI skill
  were removed; restricted parity fixtures retain their historical internal
  identifiers because their signal/lifecycle test was not authorized.
- Native gitlink, binaries, hashes, ABI, and provenance URLs were unchanged.

Behavior and package verification:

- Formatting and `dart analyze --fatal-infos`: clean across 310 Dart files.
- Architecture suite: 148 passing.
- Ordinary suite: passing with only the two opt-in Go parity cases skipped when
  `GO_SNAPSHOT_CMD` is absent. The restricted process-lifecycle wrapper was not
  selected.
- Lower-bound dependency resolution: strict analysis and the full ordinary
  suite pass. `frontend_server_client: ^4.0.0` prevents `pub downgrade` from
  selecting a test runner incompatible with the supported Dart 3.10 SDK.
- Safe Dart-versus-Go primitive/widget parity: 3 passing.
- Native manifest: all 6 binaries, checksums, target architectures, exports,
  and macOS 15.0 deployment metadata verified.
- Packaged health check and a `dart build cli` bundle both ran successfully on
  the review host using the copied native asset and emitted no terminal control
  bytes.
- Clean-snapshot publish dry-run: 2 MB archive, intentional file set, 0
  warnings. Dartdoc: 3 libraries, 0 warnings, 0 errors. Pana: 160/160 with
  97.5% API documentation coverage.
- Actionlint 1.7.12, ShellCheck, gitleaks, stale-reference scans, and
  `git diff --check`: clean.

Not run:

- Real terminal, PTY, raw-mode, visual-session, signal/termination, crash,
  sanitizer, leak, tracked-artifact refresh, tag, release, or publication
  operations.
- Live execution on Linux, Windows, macOS x64, or a second macOS version.
