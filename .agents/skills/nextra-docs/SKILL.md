---
name: nextra-docs
description: Build, migrate, review, or maintain documentation websites with current Nextra and the Nextra Docs Theme. Use for Nextra setup, Next.js App Router and MDX structure, custom documentation landing pages, navigation and page maps, theme layout composition, Pagefind search, Nextra upgrades, or diagnosing stale Pages Router and theme.config conventions.
---

# Nextra Docs

Build Nextra documentation sites from the current official contract. Treat Nextra
and Next.js conventions as version-sensitive; verify them before changing a site.

## Start with evidence

1. Read the repository instructions and inspect the existing package manager,
   lockfiles, Next.js version, Nextra version, routing tree, `next.config.*`,
   `mdx-components.*`, content directories, and deployment configuration.
2. For Noir, read `TODO.md` and `GOALS.md` before presenting release status or
   API promises. Keep the web app isolated from the Dart package and confirm its
   files do not unintentionally enter the pub archive.
3. Check the installed package source or current official Nextra documentation
   before relying on remembered APIs. Use only official Nextra, Next.js, and
   Pagefind sources for framework behavior.
4. Read [references/nextra-v4-patterns.md](references/nextra-v4-patterns.md)
   before scaffolding, migrating, or changing routing, layout, or search.

## Choose one content architecture

Prefer the smallest structure that supports the requested site:

- Use colocated `app/**/page.mdx` content for a straightforward App Router site.
- Use a separate `content/` or `src/content/` tree plus an App Router catch-all
  page when authors need content separated from application code.
- For a custom product homepage plus documentation, keep the homepage as a
  normal Next.js page and apply the docs theme deliberately. The official
  example's root `Layout` plus page-map metadata is the baseline. Use route
  groups only after verifying them with the installed Nextra version.
- In a mixed-language monorepo, prefer a dedicated web-app directory such as
  `website/` unless the repository already defines another location.

Do not combine colocated and content-directory conventions accidentally. Record
the selected routing and content model before implementation.

## Implement the foundation

1. Preserve the repository's package manager and existing lockfile. Do not add
   a second lockfile.
2. Resolve mutually compatible current releases of Next.js, React, `nextra`,
   and `nextra-theme-docs`; do not copy version numbers from an old template.
3. Wrap Next.js with `nextra()` in `next.config.*` and configure only options
   supported by the installed release.
4. Provide `mdx-components.*` and merge the Docs Theme components with project
   overrides.
5. Compose `Layout`, `Navbar`, `Footer`, and optional `Head` or `Banner` in an
   async App Router layout. Supply `pageMap={await getPageMap()}`.
6. Add metadata, repository links, edit links, navigation metadata, and assets
   from project facts rather than placeholders.
7. Keep the landing page visually custom when requested. Use the local design
   skill separately for aesthetic direction; this skill owns Nextra structure
   and integration correctness.

## Configure documentation behavior

- Express ordering, titles, hidden pages, separators, and navbar pages through
  the current `_meta.*` conventions.
- Keep code examples executable against the documented release and public API.
- Add Pagefind explicitly when local search is required. Index the completed
  build, ignore generated search output, and verify search in the built site.
- Prefer server components. Introduce `'use client'` only for actual browser
  state, effects, or event handlers.
- Preserve keyboard navigation, visible focus, readable code blocks, heading
  hierarchy, reduced motion, responsive navigation, and light/dark contrast.

## Reject stale Nextra patterns

Do not introduce these Nextra 3-era shapes into a current site:

- a `pages/` router for a new Nextra site;
- `theme: 'nextra-theme-docs'` or `themeConfig` inside `nextra()`;
- a root `theme.config.tsx` as the primary Docs Theme configuration;
- claims that Nextra search is built-in FlexSearch;
- the old standalone `shuding/nextra-docs-template` as a copy-paste scaffold.

When migrating an existing Nextra 3 site, identify these shapes, map each one to
the installed Nextra version's App Router API, and remove obsolete files rather
than keeping parallel compatibility configurations.

## Verify proportionally

Run the checks supported by the web app and the change's risk:

1. Format, lint, and type-check the changed site.
2. Run its tests when present.
3. Run a production build. Confirm Pagefind emits its expected output when
   search is enabled.
4. Inspect the landing page and representative docs pages at narrow and wide
   viewports. Exercise navigation, theme switching, search, deep links, code
   blocks, and keyboard focus.
5. Check the repository diff and packaging boundaries so generated output,
   caches, or web dependencies are not committed accidentally.

Report the exact commands run, any skipped browser or deployment checks, and
any version-sensitive assumption that remains.
