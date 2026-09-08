# Noir documentation website

This directory contains Noir's browser documentation. It is a separate
Next.js and Nextra application with its own dependencies, lockfile, and build
commands; nothing here is part of the published Dart package.

The site is written for Dart and Flutter developers evaluating Noir or
building terminal applications. It should get a new reader to a running
example quickly, explain the framework's retained architecture, and make the
four supported package surfaces easy to distinguish.

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
npm run lint
npm run typecheck
npm run build
npm run test:smoke
```

## GitHub Pages

The configured private Pages site is
<https://cuddly-adventure-1v2ez7p.pages.github.io/>. The
`.github/workflows/pages.yml` workflow builds `main` and deploys only the
generated `website/out` artifact. In the repository settings, Pages uses
**Source: GitHub Actions**.

GitHub supplies the deployed base path to the build. The current private URL
uses the root path; to verify compatibility with a public `/noir` project path,
run:

```sh
cd website
NOIR_WEBSITE_BASE_PATH=/noir npm run build
NOIR_WEBSITE_BASE_PATH=/noir npm run test:smoke
```

`npm run build` performs a Next.js static export and writes the Pagefind index
into `website/out/_pagefind`. The `out` directory is generated deployment
output and is not committed. Pushes to `main` deploy automatically; the manual
workflow trigger exists for an intentional deployment from another ref.

## Recorded examples

The homepage and getting-started guide use the same self-hosted asciicast from
the shipped counter example. Regenerate it from the repository root after an
intentional visual or interaction change:

```sh
dart run scripts/record_noir_demo.dart \
  --recipe scripts/recordings/counter.json --force
```

The player shows a static poster until the reader presses Play. Normal-motion
sessions loop after that explicit action; reduced-motion sessions play once.
The recording preserves NoirDriver cells, styles, cursor state, and production-
parser input. It is not evidence of raw-mode cleanup or a particular terminal
emulator.

## Documentation ownership

The **Build a task list** page and its six screenshots are generated from
`packages/noir_signals/doc/getting-started.md` and its `images/` directory.
Edit those sources, then run `node scripts/sync-signals-guide.mjs` from
`website/`. Development startup, type-checking, and production builds also run
the sync. Commit the regenerated `src/content/docs/signals-task-list.mdx` and
`public/demos/signals-task-list/` images with the source changes. While the dev
server is already running, rerun the sync after editing the source guide.
The generated page sets `sourceUrl` to the canonical Markdown. The MDX page
wrapper uses that URL for **View source on GitHub**; other pages keep Nextra's
default source path.

Each fact should have one primary home:

- The repository `README.md` owns the package introduction, installation,
  public API tiers, and concise platform status.
- `example/README.md` owns the runnable example catalog.
- `packages/noir_signals/example/README.md` owns the companion example index.
- `packages/noir_signals/doc/getting-started.md` owns the task-list walkthrough
  shared by the companion archive and the website.
- `packages/noir_signals/doc/hooks.md` owns the exact hooks contract shipped
  with the companion package.
- Dartdoc owns API signatures and member-level behavior.
- This website owns tutorials, task guides, concepts, and browser reference
  pages.
- `GOALS.md`, `TODO.md`, and `CONTRIBUTING.md` own architecture, release
  evidence, and contributor process.

Link to the primary source when a second copy would drift. Repeat a fact only
when the reader needs it in place, such as a platform limitation beside an
affected feature.

## Writing and evidence

Keep the voice direct and specific. Use Flutter terms only where Noir
intentionally follows Flutter, and describe terminal or OpenTUI behavior in
Noir's own terms. Code must compile against the current public API. A rendered
frame must be a real capture or clearly labelled expected output.

Noir is a prerelease. The site must not imply that an unreleased API is stable
or that a restricted terminal or native release gate passed when `TODO.md`
says otherwise. The source tree can also be ahead of the latest pub.dev
package, so version-sensitive claims need an explicit source.

Do not invent testimonials, adoption numbers, performance benchmarks, or other
claims without a recorded source.

The visual system is **Ink and Signal**. Its tokens, page compositions,
accessibility requirements, and visual treatment of captured and expected
frames are in [DESIGN.md](DESIGN.md).

## Documentation structure

The site uses Nextra Docs Theme 4 on Next.js, with the Noir styles in
`src/app/globals.css` and tokens documented in `DESIGN.md`. Content stays in
`src/content/`; the shared catch-all route renders it through Nextra. The
`src/content/docs/index.mdx` overview owns `/docs`.

The overview and sidebar follow [Diátaxis](https://diataxis.fr/): tutorials
for learning by building, how-to guides for specific tasks, explanation for
understanding the framework, and reference for lookup. Keep complete code
checkpoints and expected output in tutorials; link to lifecycle and ownership
contracts when the reader needs more detail. Documentation body text uses
system sans; serif page and section headings retain the Noir identity.
