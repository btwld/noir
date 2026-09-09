---
name: Noir Website
description: Ink and Signal is Noir's browser documentation system, not terminal-widget rendering guidance.
colors:
  ink: '#11110f'
  paper: '#fbfbf8'
  quiet: '#5f5f58'
  rule: '#d4d4cb'
  signal: '#244fd7'
  terminal: '#090a0a'
  terminal-ink: '#f5f5ed'
typography:
  root:
    fontFamily: 'ui-sans-serif, system-ui, sans-serif'
    fontSize: '1rem'
    lineHeight: 1.7
  display:
    fontFamily: "Georgia, 'Times New Roman', ui-serif, serif"
    fontSize: 'clamp(2.6rem, 5vw, 4rem)'
    fontWeight: 500
    lineHeight: 1.06
    letterSpacing: '-0.03em'
  page-title:
    fontFamily: "Georgia, 'Times New Roman', ui-serif, serif"
    fontSize: 'clamp(2rem, 3.2vw, 2.8rem)'
    fontWeight: 500
    lineHeight: 1.08
    letterSpacing: '-0.03em'
  section-heading:
    fontFamily: "Georgia, 'Times New Roman', ui-serif, serif"
    fontSize: 'clamp(1.5rem, 2.3vw, 1.85rem)'
    fontWeight: 500
    lineHeight: 1.18
    letterSpacing: '-0.02em'
  ui-label:
    fontSize: '0.875rem'
  mono:
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace'
    fontSize: '0.86rem'
    lineHeight: 1.7
  scale:
    meta: '0.76rem'
    label: '0.82rem'
    code: '0.86rem'
    ui: '0.875rem'
    small: '0.92rem'
    body: '1rem'
    lead: '1.06rem'
    sub: '1.14rem'
    intro: 'clamp(1.15rem, 2vw, 1.4rem)'
    display-sm: '1.35rem'
    display-md: 'clamp(1.5rem, 2.3vw, 1.85rem)'
    display-lg: 'clamp(2rem, 3.2vw, 2.8rem)'
    display-xl: 'clamp(2.6rem, 5vw, 4rem)'
rounded:
  square: '0'
spacing:
  page-inline: 'clamp(1.25rem, 5vw, 4rem)'
  section-breath: 'clamp(4rem, 10vw, 8.5rem)'
  heading-gap: '1.4rem'
components:
  terminal-frame:
    backgroundColor: '{colors.terminal}'
    textColor: '{colors.terminal-ink}'
    rounded: '{rounded.square}'
  terminal-recording:
    backgroundColor: '{colors.terminal}'
    textColor: '{colors.terminal-ink}'
    rounded: '{rounded.square}'
  install-command:
    backgroundColor: '{colors.paper}'
    textColor: '{colors.ink}'
    typography: '{typography.mono}'
    rounded: '{rounded.square}'
  availability:
    backgroundColor: '{colors.paper}'
    textColor: '{colors.ink}'
    typography: '{typography.ui-label}'
    rounded: '{rounded.square}'
  process-flow:
    backgroundColor: '{colors.paper}'
    textColor: '{colors.ink}'
    rounded: '{rounded.square}'
---

# Design system: Noir website

## Creative direction

**Ink and Signal** uses warm paper, serif display headings, square near-black
terminal frames, thin rules, and one blue accent. Terminal material is captured
output, shown with its capture boundary.

This is a browser documentation system. It does not prescribe the appearance of
applications built with Noir. Terminal styling is reserved for output. It is
never page chrome or decoration.

Blue is a signal, not a theme color. Use it for process numbers or a small
evidence marker. Links, headings, cards, and whole page regions do not become
blue by default.

## Typography

The application root is sans-serif at 1rem / 1.7. That includes navigation,
search results, dialogs, tables, captions, and every overlay Nextra renders, so
the site has one interface typeface everywhere.

Serif is opt-in, and only for display type: the wordmark, the homepage
headings, and article `h1` and `h2`. Nothing else adds a font family. Three
custom properties carry the whole system: `--display`, `--body`, and `--mono`.
A rule that writes a literal font stack is a defect.

Size is a closed ramp on the same terms. Thirteen `--text-*` custom properties
carry every step, from `--text-meta` for captions and provenance rows to
`--text-display-xl` for the homepage headline. A rule that writes a literal
`rem` size is a defect. Two literals are not scale steps and stay: the inline
code `em` that tracks its parent, and the narrow-viewport headline caps. Mono
sits one step below the interface step so the two read level.

Prose stays near 65–80 characters. Code, tables, and captured frames may use
the full article width; long code lines scroll inside the code block only.

## Page templates

Every page states one reader intent and one completion. A page that cannot name
both belongs inside another page.

### Tutorial

Lead with the outcome and the requirements. Then repeat one loop: exact file
and edit location, small changed excerpt, an optional syntax note beside the
new Dart, the command or interaction, the expected result, and a matching real
capture. Long tutorials become linked lessons; a lesson keeps its complete
runnable checkpoint and its exact diff in disclosures.

Chapter navigation belongs to the tutorial. Global document ordering never
becomes a tutorial's Next link, so `Layout` sets `navigation={false}` and
lessons link forward in their own prose.

### Task guide

A specific goal, a prerequisites link, the smallest complete recipe, the
expected behavior, one relevant variation, and recovery advice beside the
recipe that needs it. Guides do not build a second omnibus troubleshooting
page.

Guide examples are widgets with `const` constructors and named callbacks, not
helper functions that return `Widget`. Extract a `StatelessWidget` or
`StatefulWidget` whenever a snippet owns layout or lifecycle.

### Concept

One question, one concrete example, a clear mental model, and links that apply
it. Process rows can show ordered ownership, such as the layout protocol or the
path from an event to a frame. A concept page explains why a boundary exists;
it does not reproduce the API catalog.

### Reference

Purpose-first, dense, and scannable. Every widget name in the catalog is a link
to a destination that answers the lookup: a curated page, or the generated
signature for the published version. A curated widget page gives the job, a
complete minimal usage, the properties a reader reaches for first, keyboard and
pointer behavior, ownership, one common mistake, and the generated signature.

## Content ownership

One authored explanation has one home. Generated facts may be repeated
anywhere; independently authored copies of a changing rule may not.

| Material                             | Primary home                                              |
| ------------------------------------ | --------------------------------------------------------- |
| Dependency instructions and versions | `TODO.md` availability block → `/docs/installation`       |
| First-app code and its frames        | `example/tutorials/first_app/`                            |
| Task-list lessons                    | `packages/noir_signals/doc/` and its tutorial checkpoints |
| Hook and Signals contracts           | `packages/noir_signals/doc/hooks.md` and `signals.md`     |
| Runnable example catalogs            | `example/README.md` and the companion `example/README.md` |
| Widget signatures and defaults       | Generated dartdoc for the published version               |
| Terminal and platform limits         | `/docs/platform-limitations`                              |
| Framework harnesses and drive mode   | `CONTRIBUTING.md` and `test/helpers/README.md`            |

`website/scripts/sync-docs.mjs` owns every derivation. It fails the build on
stale input rather than publishing a wrong version, an unrunnable snippet, or a
frame that no longer matches its source.

## Navigation

Top navigation is **Docs · Examples · API · GitHub**. The wordmark returns
home, so there is no Home item.

All four stay in the navbar at every width, down to 320px. Examples and API
have no second route: the mobile drawer carries the documentation tree only, so
hiding the navbar links on phones stranded two of the four top-level
destinations.

The documentation sidebar groups pages by reader intent: Start here, Guides,
noir_signals, Concepts, and Reference. The noir_signals group keeps its package
overview, hook and Signals guides, and task-list lessons together on this site.
Existing guide URLs stay stable. Installation, Architecture, and curated widget pages
stay routable and linked in context, without occupying the default sidebar.

**This supersedes the previous rule that the site needs no separate Examples
route.** A guide that also has to carry an example catalog serves two readers
at once. `/examples` is a small index of runnable source, with the command, the
exact file, and what each example demonstrates. It is not a second tutorial
collection.

The active route uses a narrow ink marker, not a filled block.

## Components

### Terminal frame

A figure with a short caption, verbatim cell output as selectable text, the
producing command, and the capture boundary. The text comes from
`scripts/capture_doc_frames.dart`, which drives the same checkpoint the page
teaches. A frame the reader cannot trace to a runnable file does not belong on
the site.

### Terminal recording

The asciicast player, for behavior that motion explains better than a static
frame. It never autoplays, keeps a real poster frame, and respects
`prefers-reduced-motion`. It lives where its program lives: the examples index,
not a tutorial that teaches different code.

### Availability label

One compact row at the point where a reader is about to copy a dependency or a
command. It renders generated data, names the package, states what is
available, and links to installation. A command that cannot run today never
appears as a command to run.

### Process flow

Numbered ruled rows for ordered ownership or event movement. One action and one
consequence per row. Use it for real sequences, not for any list of points.

### Comparison table

Exact mappings: need to widget, symptom to fix, package surface to
responsibility, platform to boundary.

### Disclosure

Native `<details>` with a step-specific label and a target at least 44px tall.
A lesson must still teach its step with every disclosure closed.

## Shape, spacing, and motion

Geometry is square. Separation comes from whitespace, 1px rules, and the black
evidence surface; the system has no shadow or elevation vocabulary. Vertical
rhythm is generous on the homepage and in article headings, and tighter in
tables and process rows. At narrow widths, split compositions stack in reading
order. The site uses no ambient motion.

## Accessibility and dark mode

Keyboard focus uses a 3px current-color outline with offset, and nothing else:
the theme's own box-shadow ring is suppressed, because this system has no
shadow vocabulary to hang a second indicator on. A collapsible sidebar group
keeps the link color of its children; only the chevron marks it as a group.
At viewport widths up to 700px, interactive chrome — the menu button, navbar
links, the wordmark, and the controls inside a figure or code block — keeps
the same 44px target floor the disclosure contract states. Skip navigation,
semantic headings, figure captions, table headers, and link text stay available
without color. A diff never communicates through color alone: additions and
removals keep their `+` and `-` characters.

Dark mode reassigns the semantic paper, ink, quiet, rule, and signal tokens and
keeps the black terminal surface distinct. Dark paper is `#161614`, so `#090a0a`
frames still interrupt the reading surface.

## Checks

`npm run test:smoke` asserts the reader contracts this document states: the
homepage proof equals its checkpoint and its capture, the first tutorial shows
the file it teaches, lessons keep their own screenshots and legacy
destinations, the examples index links files that exist, the catalog reaches a
usable reference in two actions, search results use the interface typeface, and
no route overflows a 390px viewport.

Run `npm run format:check`, `npm run lint`, `npm run typecheck`, `npm run
build`, and `npm run test:smoke` before committing a website change. Validate
the non-root deployment with `NOIR_WEBSITE_BASE_PATH=/noir` as well.
