# Noir documentation website

This directory contains Noir's browser documentation. It is a separate Next.js
and Nextra application with its own dependencies, lockfile, and build commands.
Nothing here is part of the published Dart package.

The site is written for Dart developers who are evaluating Noir or building a
terminal application. It should get a new reader to a running app quickly, then
let them learn reactive state, finish a task, or look something up without
reading the other three paths first.

## Work locally

Use Node 20.9 or later:

```sh
cd website
npm ci
npm run dev
```

Before committing a website change, run:

```sh
npm run format:check
npm run sync:check
npm run lint
npm run typecheck
npm run build
npm run test:smoke
```

## Generated content

`npm run sync` (also run by `dev`, `typecheck`, and `build`) regenerates
everything the site must not maintain twice:

| Output                                | Derived from                                                                              |
| ------------------------------------- | ----------------------------------------------------------------------------------------- |
| `src/generated/availability.ts`       | `publication.json` (published versions) and both `pubspec.yaml` files (manifest versions) |
| `src/generated/checkpoints.ts`        | `example/tutorials/first_app/step_01.dart` and `step_02.dart`                             |
| `src/generated/frames.ts`             | `src/generated/terminal-frames.json`                                                      |
| `src/content/docs/signals-task-list/` | The five lesson Markdown files that ship with `noir_signals`                              |
| `public/demos/signals-task-list/`     | `packages/noir_signals/doc/images/`                                                       |

The script fails the build instead of publishing stale output. It rejects a
`publication.json` entry that is not a version, a captured frame whose source
file has changed, a first-app tutorial that no longer shows its checkpoint
verbatim, and lesson Dart that is not in the lesson's runnable checkpoint.

Commit the regenerated files with the source change. Rerun the sync after
editing a source while the dev server is already running.

`npm run sync:check` compares the derived files, generated lesson regions, and
copied screenshots without writing them. It fails when an output is stale,
missing, or obsolete. PR validation and Pages deployment run this check before
typecheck or build can refresh the files. Run `npm run sync` to update them.

## Captured terminal frames

Static frames come from the checkpoints they document. Regenerate them from
`packages/noir/` after an intentional change:

```sh
dart run tool/capture_doc_frames.dart
```

`--check` recaptures without writing, and fails when the committed artifact is
out of date. Scenes live in `packages/noir/tool/recordings/doc_frames.json`. A frame is
headless drive-mode evidence: it proves layout, painted cells, and parsed
input, not that a particular terminal emulator agrees.

## Recorded examples

The examples index uses a self-hosted asciicast of the shipped counter.
Regenerate it from `packages/noir/` after an intentional visual or
interaction change:

```sh
dart run tool/record_noir_demo.dart \
  --recipe tool/recordings/counter.json --force
```

The player shows a static poster until the reader presses Play. Normal-motion
sessions loop after that explicit action; reduced-motion sessions play once.

## GitHub Pages

The public documentation site is <https://conceptadev.github.io/noir/>. The
`.github/workflows/pages.yml` workflow builds `main` and deploys only the
generated `website/out` artifact. In the repository settings, Pages uses
**Source: GitHub Actions**.

GitHub supplies the deployed `/noir` base path to the build. Verify the same
project path locally:

```sh
cd website
NOIR_WEBSITE_BASE_PATH=/noir npm run build
NOIR_WEBSITE_BASE_PATH=/noir npm run test:smoke
```

`npm run build` performs a Next.js static export and writes the Pagefind index
into `website/out/_pagefind`. The `out` directory is generated deployment
output and is not committed. Pushes to `main` that change the website or its
canonical manifests, publication record, examples, or companion documentation
deploy automatically. The manual workflow trigger remains available for an
intentional deployment.

## Ownership

[DESIGN.md](DESIGN.md) holds the page templates, the content-ownership table,
the navigation rules, and the visual system. Read it before adding a page or a
component.

In short: link to the primary source when a second copy would drift, and repeat
a fact only where the reader needs it in place, such as a platform limitation
beside the affected feature.

## Writing and evidence

Keep the voice direct and specific. Use Flutter terms only where Noir
intentionally follows Flutter, and describe terminal or OpenTUI behavior in
Noir's own terms. Code must compile against the current public API. A rendered
frame must be a real capture or clearly labelled expected output.

Noir is a prerelease. The site must not imply that an unreleased API is stable,
or that a restricted terminal or native release gate passed when the changelog says
otherwise. The source tree can be ahead of the latest pub.dev package, so
version-sensitive claims come from the generated availability data.

Do not invent testimonials, adoption numbers, performance benchmarks, or other
claims without a recorded source.
