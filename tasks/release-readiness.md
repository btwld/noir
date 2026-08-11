# 1.0 release readiness

Target: `1.0.0-alpha.1`.

Status: the source and package are a locally verified alpha candidate. They are
not cleared for public pub.dev publication, beta, or stable 1.0. Do not tag,
publish, create a GitHub release, enable workflows, or refresh native artifacts
from this checklist; each is a separate authorized operation.

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
- GitHub Actions remain disabled. The GitHub-release workflow is manual and
  accepts only an existing, version-matching tag. The official setup-dart
  publisher is pinned at its outer reusable-workflow commit, but that upstream
  workflow currently uses a mutable checkout action and floating SDK internally.
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

## Final candidate evidence

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
  sanitizer, leak, native rebuild, artifact refresh, workflow, tag, release,
  or publication operations.
- Live execution on Linux, Windows, macOS x64, or a second macOS version.
