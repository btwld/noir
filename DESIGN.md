---
name: Noir Website
description: Ink and Signal is Noir's browser documentation system, not terminal-widget rendering guidance.
colors:
  ink: "#11110f"
  paper: "#fbfbf8"
  quiet: "#5f5f58"
  rule: "#d4d4cb"
  signal: "#244fd7"
  terminal: "#090a0a"
  terminal-ink: "#f5f5ed"
typography:
  display:
    fontFamily: "Georgia, 'Times New Roman', ui-serif, serif"
    fontSize: "clamp(3rem, 7.2vw, 6rem)"
    fontWeight: 500
    lineHeight: 1.04
    letterSpacing: "-0.03em"
  page-title:
    fontFamily: "Georgia, 'Times New Roman', ui-serif, serif"
    fontSize: "clamp(2.4rem, 3.6vw, 3.65rem)"
    fontWeight: 500
    lineHeight: 1.08
    letterSpacing: "-0.03em"
  section-heading:
    fontFamily: "Georgia, 'Times New Roman', ui-serif, serif"
    fontSize: "clamp(1.65rem, 2.5vw, 2.3rem)"
    fontWeight: 500
    lineHeight: 1.18
    letterSpacing: "-0.02em"
  body:
    fontFamily: "Georgia, 'Times New Roman', ui-serif, serif"
    fontSize: "1.1rem"
    lineHeight: 1.7
  ui-label:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.875rem"
  mono:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"
    fontSize: "0.86rem"
    lineHeight: 1.7
rounded:
  square: "0"
spacing:
  page-inline: "clamp(1.25rem, 5vw, 4rem)"
  section-breath: "clamp(4rem, 10vw, 8.5rem)"
  heading-gap: "1.4rem"
components:
  terminal-frame:
    backgroundColor: "{colors.terminal}"
    textColor: "{colors.terminal-ink}"
    rounded: "{rounded.square}"
  install-command:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.mono}"
    rounded: "{rounded.square}"
  prerelease-notice:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.ui-label}"
    rounded: "{rounded.square}"
  process-flow:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
---

# Design system: Noir website

## Creative direction

**Ink and Signal** pairs an editorial reading surface with verified terminal
evidence. Warm paper and serif type make long technical explanations calm. A
near-black terminal frame interrupts that calm only when readers need to see
what Noir actually produces. Thin rules expose structure; one restrained blue
signal marks process steps and evidence boundaries.

This is a browser documentation system. It does not prescribe the appearance
of applications built with Noir.

The design should feel like Noir itself: a declarative surface with visible,
precise machinery underneath. It must not become a generic prose template, a
gallery of animated demos, or a website dressed up as a terminal.

## The visual grammar

The paper field is the default. Serif is for explanation, monospace is for
code and operations, and system sans is for navigation and compact metadata.
Noir's name and major promises carry the largest type. Article titles remain
strong, but code and terminal output become the visual proof.

The terminal surface is black, square, and static. It shows a real headless
capture or a clearly labelled expected frame beside the code and command that
produce it. It is never decorative chrome and never implies a real-terminal
protocol check. The documentation does not need a separate Examples route or
an embedded playback system; complete repository examples can be linked from
the guide that explains their behavior.

Blue is a signal, not a theme color. Use it for process numbers or a small
evidence marker. Links, headings, cards, and whole page regions do not become
blue by default.

## Typography and measure

- Display and page titles use the configured Georgia stack with moderate
  tracking (`-0.03em`) and enough leading that large type can breathe.
- Body copy uses the same serif stack at 1.1rem / 1.75 leading and stays near
  65–68 characters per line. Paragraphs and headings are separated by more
  space above a heading than below it.
- Navigation and evidence labels use system sans.
- Commands, source, terminal frames, and compact process numbers use monospace.
- Heading order carries document structure; size must not substitute for a
  missing semantic level.

Code blocks may exceed the prose measure when the example needs it. Tables and
reference ledgers use the available article width so comparisons remain
scannable.

## Page compositions by reader intent

The four documentation modes share tokens, not a single repeated layout.

### Tutorial

Lead with the outcome and prerequisites. Give the reader a complete runnable
file, the exact command, an expected static frame, one observable change, and a
short explanation of what Noir retained. The Getting started page is the model.

### How-to guide

How-to examples are widgets with `const` constructors, named callbacks, and a
block `build` method—not helper functions that return `Widget`. Extract a
`StatelessWidget` or `StatefulWidget` whenever the snippet owns layout or
lifecycle. Keep constructor-only fragments on reference pages.

### Explanation

Use one concrete event to reveal the retained architecture. Process rows can
show the transition from callback to state, element, render object, display
list, and native compositor. The prose should explain why the boundary exists,
not reproduce the API catalog.

### Reference

Favor dense comparison tables and concise boundary notes. A reader should be
able to choose a widget, platform, package surface, or command without reading
an essay. Reference pages may link to guides for rationale.

## Homepage sequence

The landing page follows this order:

1. State what Noir is and disclose the prerelease boundary.
2. Offer the install command and first-app path.
3. Put a syntax-highlighted widget `State` beside the frame it produces.
4. Index the capabilities that distinguish Noir from raw terminal output.
5. Compress the retained architecture into one readable path.
6. Route readers by the job they need to do next.

The code/frame proof is the distinctive center of the page. Homepage Dart uses
the same Shiki themes as the documentation (`github-light` / `github-dark`) so
keywords, types, and callbacks are readable without turning the specimen into
a second terminal. Capability rows are an index, not marketing cards.

## Components

### Terminal frame

A figure with a short caption, verbatim cell output, the producing command,
and an evidence boundary. Keep output selectable. Preserve whitespace. If the
frame is expected rather than captured, say so. Animation belongs only where
motion itself is the behavior under discussion and a static sequence would be
misleading.

### Process flow

Numbered ruled rows communicate ordered ownership or event movement. Each row
contains one action and one consequence. Use the component for layout protocol,
input routing, and architecture because those are actual sequences—not merely
because a page has several points.

### Comparison table

Use tables for exact mappings: need to widget, test goal to harness, package
surface to responsibility, and platform to boundary. Table text uses compact
system sans while surrounding explanation remains serif.

### Install command and notices

The install command is one bordered copyable row. A prerelease notice is an
editorial aside between rules, not a tinted alert card. Both reflow without
horizontal scrolling on compact screens.

### Navigation and next steps

The active route uses a narrow ink marker instead of a filled block. Section
labels describe reader intent: Start, Build, Understand, and Reference. Final
links name a concrete next task rather than saying only “Learn more.”

## Shape, spacing, and motion

Geometry is square. Separation comes from whitespace, 1px rules, and the
black evidence surface; the system has no shadow or elevation vocabulary.
Vertical rhythm is generous on the homepage and in article headings, and tighter
in tables and process rows. At narrow widths, split compositions stack in
reading order.

The website uses no ambient motion. Respect `prefers-reduced-motion`, and do
not use a recording when static code and a captured frame communicate the same
fact more clearly.

## Accessibility and dark mode

Keyboard focus uses a 3px current-color outline with offset. Skip navigation,
semantic headings, figure captions, table headers, and link text must remain
available without color. Dark mode reassigns semantic paper, ink, quiet, rule,
and signal tokens while keeping the black terminal evidence surface distinct.
Dark paper is `#161614` so `#090a0a` terminal frames still interrupt the
reading surface.
