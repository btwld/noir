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

## Documentation ownership

Each fact should have one primary home:

- The repository `README.md` owns the package introduction, installation,
  public API tiers, and concise platform status.
- `example/README.md` owns the runnable example catalog.
- `doc/hooks.md` owns the exact hooks contract shipped with the package.
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
