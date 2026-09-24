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

    git clone --recurse-submodules https://github.com/btwld/noir.git
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
lifecycle hooks and the Signals integration. The root `pubspec.yaml` defines
the workspace and the Melos configuration.

Melos comes with that resolve. It is a workspace dev dependency, pinned to an
exact version:

    dev_dependencies:
      melos: 7.8.1

Run it as `dart run melos:melos <command>`; no global install is needed, and
a global one would shadow the pinned version. The pin is exact on purpose.
Melos locates the workspace through this dev dependency, and 7.8.1 is the
newest release that shares `cli_util ^0.4.x` with `ffigen`, a `noir` dev
dependency. A Pub workspace resolves once for every member, so a newer Melos
cannot be added without moving `ffigen` first.

`dart run melos:melos bootstrap` resolves the workspace and aligns the
constraints more than one package declares — the SDK range, `meta`, `matcher`,
`vm_service`, `lints`, and `test` — from the `melos` section of the root
`pubspec.yaml`. It only rewrites a constraint a package already declares in
the same section, never adds one, and must leave the tree clean:

    dart run melos:melos bootstrap && git diff --exit-code && git status --porcelain

## Required checks

Run focused tests while developing, then, from `packages/noir/`:

    dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ tool/
    dart analyze --fatal-infos
    dart test test/architecture/ --concurrency=1
    dart test --concurrency=1
    dart run tool/fetch_opentui_binaries.dart --verify-only
    dart run tool/release.dart check

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

Every one of those commands is also a Melos script, which runs it from the
right directory with no `cd`:

    dart run melos:melos run --list
    dart run melos:melos run verify

`verify` is the ladder above in order, ending with `release:check`.
Individual scripts are `format:noir`, `format:driver`, `format:signals`,
`analyze`, `analyze:driver`, `analyze:signals`, `test:noir`, `test:driver`,
`test:signals`, `test:architecture`, `native:verify`, `docs:frames`,
`docs:api`, `release:check`, `stage:companion`, `stage:driver`, and
`archive:noir`, `archive:driver`, `archive:signals` for the publish dry-runs.
`release:published` and `release:record` exist too, but they belong to a
release rather than to development: one gates a GitHub release, the other
rewrites `publication.json` after a publication is confirmed. A script is an
alias for the documented command, never a second definition of it, and CI
runs the same scripts.

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

A release is prepared by an ordinary reviewed pull request and performed by
pushing a tag. Nothing publishes on a merge to `main`; nothing publishes
without a required reviewer approving the `pub.dev` environment.

### What each tool owns

Pub owns resolution. The root `pubspec.yaml` declares the workspace, and one
`dart pub get` anywhere writes the single root `pubspec.lock` and the single
shared `.dart_tool/package_config.json` for every member. Melos never resolves
anything and never writes a lockfile.

Melos owns the parts Pub has no opinion about: cascading one version across
every sibling constraint, and running a documented command in the right member
directory. Publication does not go through Melos — see *Why publication is not
`melos publish`* below.

`tool/release.dart` owns the release rules themselves, so the workflows stay
thin callers and every rule is covered by `test/tools/release_cli_test.dart`
on ordinary CI rather than first running against a real tag.

### Coordinated versioning, while Noir is 0.0.x

All three packages move together today. That follows from the contracts, not
from taste: `noir_driver` and `noir_signals` each depend on `noir`, and both
are built and tested against exactly the Noir in the same commit. Releasing a
companion without restating which Noir it was verified against would ship a
claim nobody checked.

This is a narrower rule than it looks, and it has an end. Dart's caret is not
npm's: `pub_semver` raises the *minor* for a `0.y.z` version, so `^0.0.2`
means `>=0.0.2 <0.1.0` and already admits `0.0.3`. A companion is therefore
never *stranded* by a Noir patch. Once Noir reaches `0.1.0`, `^0.1.0` spans
every `0.1.x`, a companion can sit out a Noir patch release, and versioning
becomes independent. Revisit this section at that bump.

### Prepare the release

From the repository root, move every member in one step:

    dart run melos:melos version -V noir:<next> -V noir_driver:<next> -V noir_signals:<next> --no-changelog --no-git-commit-version --dependent-constraints --no-dependent-versions

That rewrites the three `version:` fields, both `noir:` constraints, and
Noir's `noir_driver:` dev dependency — six lines in three files — and nothing
else. Confirm at the prompt; do not pass `--yes`.

Each flag is load-bearing:

- `-V <package>:<version>` for **every** member, not the
  `melos version <package> <version>` positional form. The positional form
  scopes the run to one package, which makes the others *ignored packages with
  pending changes*; Melos then refuses to version anything that depends on
  one, and `noir` dev-depends on `noir_driver`. It prints a warning, changes
  nothing, and still exits `0`. Naming every member leaves nothing ignored,
  which is also why no `--diff` workaround is needed.
- `--no-dependent-versions` keeps the cascade to constraints. A dependent's
  own `version:` is a release decision, never a side effect.
- `--no-changelog`, because each `CHANGELOG.md` is a hand-written release
  contract that tests assert by content.
- `--no-git-commit-version`, which also implies `--no-git-tag-version`. A
  release tag publishes to pub.dev for real.

Then do the deliberate half by hand: author each changelog section, move the
version the architecture test pins, and update the version the dialog example
shows. `publication.json` does not move here — it records pub.dev, and
nothing is published yet.

Before opening the pull request:

    dart run melos:melos run release:check

It reports any package whose constraint on a sibling excludes the sibling it
ships beside, and any changelog that does not lead with its own manifest
version. Nothing else reports either: inside a workspace Pub binds siblings to
the local checkout without ruling on the declared constraint, and
`stage_companion_package.dart --verify` replaces the `noir` dependency with a
path override before its dry-run. `release:check` is part of `verify`, so CI
runs it on the release pull request.

### Tag conventions

Every release tag is `<package>-v<version>`:

    noir-v0.0.4
    noir_driver-v0.0.1-alpha.2
    noir_signals-v0.0.1-alpha.2

One convention serves three consumers. It is pub.dev's documented
recommendation for a repository that publishes more than one package, it is
byte-identical to the tag `melos version` and `melos publish` build, and it
tells the publish workflow which package a tag is asking for. The unprefixed
`v0.0.2`-style tags used before 0.0.3 name no package and no longer trigger
anything.

### Publish

Push the tags **one at a time, Noir first**, and wait for each run to finish:

    git tag noir-v0.0.4 && git push origin noir-v0.0.4
    # wait for the run to publish, then:
    git tag noir_driver-v0.0.1-alpha.2 && git push origin noir_driver-v0.0.1-alpha.2
    git tag noir_signals-v0.0.1-alpha.2 && git push origin noir_signals-v0.0.1-alpha.2

One at a time for three reasons. GitHub creates no tag events at all when more
than three tags arrive in one push. `dart pub publish` resolves dependencies
as part of its own validation, so a companion cannot validate until the Noir
it requires is actually being served. And a companion run started before Noir
finishes spends its wait budget and then fails — correctly, but for nothing.

That last case is a wasted run, never a wrong publication: the ordering gate
is what enforces the order, not the queue. Each tag gets its own concurrency
group so one release can never cancel another.

Each push runs `.github/workflows/publish.yml`, one ordered chain:

1. **preflight** resolves the tag to a package and checks it against that
   package's manifest; asks pub.dev whether every workspace dependency is
   already served at a version this package's constraint admits, waiting up to
   ten minutes for a Noir published moments earlier to surface, and **fails**
   rather than publishing a package no consumer could resolve; skips the rest
   when the version is already on pub.dev; and otherwise runs `release:check`,
   the whole `verify` ladder, the native-asset verify, and that package's
   `dart pub publish --dry-run`.
2. **test-package** (Noir only) deletes the checkout's native assets, restores
   the packaged copy, and runs the health check and a CLI bundle on Linux,
   macOS and Windows. Publication cannot be undone, so the last proof that the
   shipped bytes load runs before the upload, not after it.
3. **publish** stops at the `pub.dev` environment until a required reviewer
   approves, then publishes with `dart pub publish --force` over OIDC.
4. **announce** (Noir only) calls `release.yml` to cut the GitHub release with
   the bundled-artifact archive attached.
5. **record** proposes the `publication.json` update.

The decision in step 1 comes before the work in steps 1–2 on purpose: both of
its answers make verification pointless, and a re-pushed tag should not pay
for a thirty-minute ladder to discover it had nothing to do.

### The announcement never races the publication

`release.yml` has no trigger of its own. It used to run on `noir-v*` in
parallel with `publish.yml`, which meant a GitHub release could go public
while a reviewer had not yet approved the `pub.dev` environment, or after the
upload failed outright — announcing a version nobody could install.

It is now a reusable workflow that `publish.yml` calls with
`needs: [preflight, publish]` and no `always()`, so ordinary skip semantics
stop it unless the upload actually succeeded. It also asks pub.dev directly,
through `dart run tool/release.dart published <package>`, before it writes
anything. The second gate is not redundant: it is what protects the
`workflow_dispatch` path, which has no `needs` to inherit.

### Record the publication

After the publish job succeeds, the workflow opens a pull request that rewrites
`publication.json` from what pub.dev serves and regenerates
`website/src/generated/availability.ts` from it. pub.dev is the source of
truth, `publication.json` caches it, and the availability labels derive from
that cache — so a release abandoned halfway can never leave a label claiming a
version nobody can install. To do it by hand:

    dart run melos:melos run release:record
    cd website && npm run sync

The workflow opens that pull request with `GITHUB_TOKEN`, not an app or
personal token. Its checks are created but held: GitHub puts workflow runs
from a pull request a token opened into an approval-required state, and a
maintainer releases them with **Approve and run** on the pull request. Nothing
needs pushing to it, and no extra credential exists to leak — the same rule
that holds those runs is what stops this job from re-triggering itself.

### When something fails

A published version is permanent and a pushed release tag is a public
reference, so recovery never moves either. In every case below the tag stays
exactly where it is.

| What failed | What to do |
| --- | --- |
| preflight, test-package, or the dry run | Nothing shipped. Fix it on `main`, then cut the *next* version. Do not move the tag. |
| the reviewer declined, or the run was cancelled | Nothing shipped. Same as above. |
| `dart pub publish` itself | Nothing shipped. Re-run the failed jobs from the run page once the cause is fixed. |
| the upload succeeded but a later job failed | **Re-run failed jobs** from the run page. That reuses the successful `publish`, so the failed job runs again against it. |
| the announcement failed, or was never cut | Run `release.yml` by **workflow_dispatch** with the tag. It asks pub.dev first, so it refuses if the version is not actually there. |
| the wrong content was published | Publish a corrected higher version. Within seven days of publication you may also retract the bad one on pub.dev, which hides it from new consumers without deleting it. |
| `publication.json` drifted | `dart run melos:melos run release:record`, then `npm run sync` in `website/`. |

Re-running the *whole* run, or re-pushing the tag, is not the same thing and
is usually not what you want: `preflight` then finds the version already
published and skips `publish`, which skips `announce` with it. You get a
green run and no GitHub release. `record` is the one job that survives a
skipped publish, deliberately, because reconciling the record is exactly what
a re-run is often for. To cut a release for a version that is already out,
use the `workflow_dispatch` row above.

Re-pushing a deleted tag is never the recovery path. pub.dev matches the tag
that triggered a run against the version being published, and a moved tag
makes every earlier reference to it a lie.

### Why publication is not `melos publish`

`melos publish` picks its own order, and for this workspace it picks the wrong
one. `sortPackagesForPublishing` feeds both `dependencies` and
`dev_dependencies` into one graph. Noir dev-depends on `noir_driver` for two
checkout-only tools and `noir_driver` depends on Noir, so that graph has a
cycle; Melos falls back to sorting the cycle by name length, and offers to
publish `noir_driver` before `noir`. A dry run shows it plainly:

    Package Name    Registry         Local
    noir_driver     0.0.1-alpha.0    0.0.1-alpha.1
    noir            0.0.2            0.0.3
    noir_signals    0.0.1-alpha.0    0.0.1-alpha.1

Publishing in that order ships a `noir_driver` that requires a Noir nobody can
get yet. `tool/release.dart` treats only runtime dependencies as ordering
edges, so a checkout-only dev dependency cannot invert the order, and it
enforces the rule against pub.dev instead of trusting a sorted list.

### One-time settings

These live outside the repository and are not part of any pull request.

On GitHub, create an environment named `pub.dev` with required reviewers and
**Prevent self-review**. Do this *before* the first tag: GitHub silently
creates an environment the first time a workflow names one, with no
protection rules at all, so an unconfigured `pub.dev` environment is an
approval gate that approves everything.

On pub.dev, under `pub.dev/packages/<package>/admin`, each of `noir`,
`noir_driver`, and `noir_signals` needs automated publishing enabled for
repository `conceptadev/noir`, the tag pattern `<package>-v{{version}}`, and
Require GitHub Actions environment set to `pub.dev`. The two settings work
together: GitHub decides whether a human approved, and pub.dev refuses a
token whose claim does not carry that environment — so the boundary cannot be
moved by editing a workflow file.

pub.dev's own guidance suggests one workflow file per package. This
repository uses one file that derives the package from the tag instead.
Everything pub.dev actually checks — repository, tag pattern, environment —
still holds, because a tag names exactly one package and only that package is
published; three near-identical files would be three places to drift.

Repository visibility and native artifact refreshes remain separate explicit
decisions and are never part of an ordinary change.
