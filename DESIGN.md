---
name: Noir Website
description: Quiet Signal is Noir's browser documentation system, not terminal-widget rendering guidance.
colors:
  ink: "#11110f"
  paper: "#fbfbf8"
  quiet: "#5f5f58"
  rule: "#d4d4cb"
  terminal: "#090909"
  terminal-ink: "#f6f6ee"
typography:
  display:
    fontFamily: "Georgia, 'Times New Roman', ui-serif, serif"
    fontSize: "clamp(3rem, 7.2vw, 6rem)"
    fontWeight: 500
    lineHeight: 0.96
    letterSpacing: "-0.045em"
  page-title:
    fontFamily: "Georgia, 'Times New Roman', ui-serif, serif"
    fontSize: "clamp(2.65rem, 5vw, 4.7rem)"
    fontWeight: 500
    lineHeight: 1
    letterSpacing: "-0.045em"
  section-heading:
    fontFamily: "Georgia, 'Times New Roman', ui-serif, serif"
    fontSize: "clamp(1.75rem, 3vw, 2.65rem)"
    fontWeight: 500
    lineHeight: 1.08
    letterSpacing: "-0.035em"
  body:
    fontFamily: "Georgia, 'Times New Roman', ui-serif, serif"
    fontSize: "1.075rem"
    lineHeight: 1.65
  ui-label:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.875rem"
  mono:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"
    fontSize: "0.82rem"
    letterSpacing: "0.01em"
  meta-label:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"
    fontSize: "0.77rem"
    letterSpacing: "0.04em"
rounded:
  square: "0"
spacing:
  page-inline: "clamp(1.25rem, 5vw, 4rem)"
  command-content: "0.65rem 0.8rem"
  ruled-slab: "0.85rem 0"
  reading-row: "0.75rem 0"
  section-breath: "clamp(3rem, 8vw, 7rem)"
components:
  action-button:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.mono}"
    rounded: "{rounded.square}"
    padding: "0.58rem 0.72rem"
  action-button-hover:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
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
    padding: "{spacing.ruled-slab}"
  terminal-recording:
    backgroundColor: "{colors.terminal}"
    textColor: "{colors.terminal-ink}"
    typography: "{typography.mono}"
    rounded: "{rounded.square}"
  site-nav-link:
    textColor: "{colors.quiet}"
    typography: "{typography.ui-label}"
  next-question-link:
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    padding: "0.82rem 0"
  architecture-signal:
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.square}"
---

# Design System: Noir Website

## Overview

**Creative North Star: "Quiet Signal"**

Quiet Signal is the visual system for Noir's browser documentation website. It
turns a technical evaluation into calm editorial reading: warm paper, near-black
type, generous empty space, and hairline rules establish confidence without
marketing gloss. It is deliberately a website system, not a description of
Noir's terminal-widget rendering UI, visual language, or native compositor.

The homepage proves the product in a restrained order: install Noir, see a
retained terminal frame, then select a concrete next question. The terminal
recording is evidence rather than decoration—the one dark anchor in an otherwise
black-and-white reading surface. The site uses no gradients, bento layouts, or
stock imagery. It ships one hand-authored vector app icon and six reviewed
asciicast text recordings; no shipping raster asset exists, so raster prompt or
provenance data is neither present nor required.

**Key Characteristics:**

- Editorial serif reading paired with utilitarian sans and monospace details.
- Warm neutral contrast, 1px rules, and square geometry instead of cards or
  shadows.
- One reviewed terminal recording as the proof-bearing visual anchor.
- Direct prerelease disclosure and question-led documentation paths.

## Colors

The palette is a warm monochrome system: contrast, not hue, establishes
hierarchy.

### Primary

- **Printed Ink** (the ink token): carries primary reading text, solid action
  controls, and the strongest rules.

### Neutral

- **Warm Paper** (the paper token): the uninterrupted reading field and the
  inversion state for actions.
- **Quiet Text** (the quiet token): supports navigation, notes, and secondary
  documentation context without becoming a second accent.
- **Hairline Rule** (the rule token): separates notices, rows, and editorial
  sections while keeping the page open.
- **Terminal Field** (the terminal token) and **Terminal Ink** (the
  terminal-ink token): confine the dark evidence frame to captured terminal
  content and code blocks.

Dark mode reassigns the same semantic CSS custom properties rather than adding
a second visual identity. New work must consume the semantic properties instead
of baking the light values into components.

**The One Dark Anchor Rule.** On a light page, reserve a solid dark field for
terminal evidence or code. Do not create competing dark cards, decorative
backdrops, or colored callouts.

## Typography

**Display Font:** Georgia (with Times New Roman and serif fallbacks)

**Body Font:** Georgia (with Times New Roman and serif fallbacks)

**Label / Mono Font:** system sans for navigation and utility labels; the
configured system monospace stack for commands, metadata, and terminal output.

**Character:** The serif face makes framework documentation read like an
edited technical essay. Sans is deliberately quiet, while monospace marks an
operation, a command, or machine evidence rather than trying to make the whole
site look like a terminal.

### Hierarchy

- **Display:** the home-page promise; compact, tightly tracked, and allowed to
  occupy the first reading beat.
- **Page Title:** the documentation-page entry point; large but subordinate to
  the homepage promise.
- **Section Heading:** major sectional turns such as the ownership explanation
  and next-reading choice.
- **Body:** continuous prose; individual documentation paragraphs and list
  items are held to a readable 72ch maximum.
- **UI Label:** navigation and utility context; subdued rather than
  display-like.
- **Mono** and **Meta Label:** commands, action labels, terminal material, and
  compact uppercase status markers.

**The Serif / Mono Relay Rule.** Use serif for explanation, monospace for an
operation or captured output, and system sans for navigation. Do not turn
reader-facing prose into terminal chrome.

## Layout

The home canvas is centered at a 76rem maximum width, with responsive inline
padding from 1.25rem to 4rem and a deliberately deep opening margin. The
introductory argument narrows further, keeping the promise, summary, status,
and install action in a focused column before the terminal frame opens to the
full content width. Long-form documentation constrains prose and list measures
to 72ch; example explanations use 65ch.

Vertical rhythm is slow and sectional. The terminal evidence and the ownership
signal each receive the established section-breath interval; thin horizontal
rules make lists feel like an annotated ledger instead of a set of cards. The
architecture list is a two-column label-and-explanation grid on wide screens,
then becomes stacked reading rows at the real 700px breakpoint. At that same
breakpoint, the top navigation keeps the GitHub destination while its ordinary
section links collapse out of view.

For a top-level Noir documentation landing page, preserve the proven sequence:
short promise → copyable install command → reviewed retained-rendering evidence
→ a safe, specific next question. It is a conversion-to-comprehension path, not
a mandate to repeat the home-page composition on every article.

## Elevation & Depth

This is a flat system: the website defines no box-shadow vocabulary. Depth comes
from whitespace, 1px rule placement, type scale, and the terminal's deliberate
black field against paper. The terminal frame is an evidence boundary, not a
raised card.

**The Flat Evidence Rule.** If a surface needs separation, use a rule, spacing,
or the existing terminal contrast before adding a shadow, blur, tint, or
floating-panel effect.

## Shapes

Geometry is rectangular and exact. Code blocks, terminal recordings, install
commands, inline code, and ruled reading rows use square corners; borders are
hairline and functional. The design favors column, row, and frame silhouettes
over pills, rounded containers, badges, or ornamental clipping.

**The Square Boundary Rule.** A boundary should read as a document rule or a
terminal frame. Rounded treatment is not part of the incumbent website's
component language.

## Components

### Buttons

Action buttons are compact monospace rectangles. Their default is Printed Ink
on Warm Paper; hover reverses the field and text while retaining the border.
The shared visible focus treatment is a 3px current-color outline with a 3px
offset. Use these for explicit actions such as copying an install command or
starting a reviewed recording.

### Install Command

The install command is a single bordered horizontal control: selectable
monospace command text, then a Copy button divided by a left rule. It stays
inline while it fits and becomes a flexible row on compact screens; command
text may wrap rather than forcing horizontal overflow.

### Prerelease Notice

The prerelease notice is an editorial aside, not an alert card. Two Hairline
Rules enclose a small system-sans statement, led by an uppercase monospace
status label. At the compact breakpoint, its label and explanation stack so the
limitation remains easy to read.

### Terminal Recording

The terminal recording is the signature website component: a square black
figure with a caption, source-backed still poster, explicit playback action,
and direct .cast download. It begins as a still frame; reduced-motion users keep
that still frame until they choose playback, and a failed player returns to the
same evidence with an honest status note. This describes the website's recording
presenter only, never Noir's terminal widget styling.

### Site Navigation

Top navigation uses small quiet system-sans links with no decorative
underlines. Hover restores Printed Ink; keyboard focus uses the global visible
outline. Compact navigation reduces visual choices without hiding the GitHub
destination.

### Architecture Signal

The ownership explanation is a ruled ledger: mono owner names form the left
column and serif explanations form the right. Each row has a bottom rule and
the whole list begins with a top rule. On compact screens, label then
explanation become a readable vertical pair.

### Next-Question Links

Next-reading choices are full-width serif questions between rules, each ending
with a simple arrow. They should name a real reader decision instead of using a
generic call to action.

### Code Blocks

Documentation code blocks use the same Terminal Field / Terminal Ink inversion
as recorded evidence, with a square Hairline Rule. Inline code is lighter: it
stays on paper inside a small square rule rather than becoming a colored chip.

## Do's and Don'ts

### Do:

- **Do** use the paper, ink, quiet-text, and hairline-rule system to create
  hierarchy before adding a new visual treatment.
- **Do** make terminal evidence real, reviewed, and legible as a still poster
  before playback; retain a direct source or .cast path where the component
  provides one.
- **Do** lead a landing page from installation to retained-rendering evidence
  to a specific, safe next question.
- **Do** keep prerequisites and prerelease limits direct, ruled, and adjacent
  to the behavior they qualify.
- **Do** preserve semantic CSS variables so the existing dark mode remains an
  inversion of the same system.

### Don't:

- **Don't** add gradients, bento grids, stock imagery, decorative raster
  imagery, or a second visual anchor that competes with the terminal evidence.
- **Don't** add shadows, rounded cards, pills, glass, blur, or hover lift to
  simulate depth that the system intentionally avoids.
- **Don't** use a terminal-looking surface as decoration or imply unverified
  live-terminal behavior; the recording pane is evidence with explicit limits.
- **Don't** apply this website document as a style specification for Noir's
  terminal widgets, render objects, compositor, or native layer.
