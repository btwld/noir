# Noir reference: screen design

How a Noir screen should look and feel, given the widgets that actually
ship. Constructors stay in `widgets.md` and `inputs-and-focus.md`. Load this
before inventing chrome, spacing, or a palette.

Plan the screen, then build from the catalog. Do not start from a web
design skill or a generic TUI gallery — those assume typefaces, overlays,
and widgets Noir does not have.

## Contents

- [Process](#process)
- [Spacing: 0 / 1 / 2 cells](#spacing-0--1--2-cells)
- [Chrome color: `ThemeData`, not a hex sheet](#chrome-color-themedata-not-a-hex-sheet)
- [Type and copy](#type-and-copy)
- [Anti-slop](#anti-slop)
- [Floor before shipping a screen](#floor-before-shipping-a-screen)

---

## Process

1. **Name the job.** One sentence: who this is for and what this screen
   does. Pick one layout from that job — do not mix them:
   - **Page chrome** — title, optional hint, body (the demo scaffold shape).
   - **Split** — sidebar + main, or list + detail, with a 1-row status.
   - **Form** — labels and fields in a column; Tab moves between them.
   - **Dashboard** — a few self-contained regions, all visible at once.
   - **Transcript** — scrollable history above a 1-row composer.
2. **Write a token plan**, not hex. Chrome uses `ThemeData` slots (below).
   Spacing uses the 0 / 1 / 2 cell scale. Type roles are body, muted,
   emphasis (bold), and accent — one monospace face.
3. **Draw an 80×24 ASCII wireframe in cells.** Count the border row, the
   footer row, and every `spacing: 1` blank line. If the body does not fit,
   cut chrome, not content.
4. **Pick one signature.** A landmark split, a status line, or one accent
   — not a hero, a gradient, or a second typeface.
5. **Slop check.** If the plan would look the same for any TUI, or if it
   needs a widget that is not in the catalog, revise it.
6. **Build from the catalog**, then **look at a capture at 80×24** (and a
   wider size). Drive mode on the main skill file is how; assertions stay
   in ordinary tests (`testing.md`).

## Spacing: 0 / 1 / 2 cells

A cell is not square. Typical fonts are about twice as tall as they are
wide, so **1 row of vertical space reads like 2 columns of horizontal
space.** Use only these steps:

| Cells | Vertical | Horizontal |
|---|---|---|
| **0** | Flush lists, table rows | Flush columns, chips on a title row |
| **1** | Default `Column` gap — a whole blank line | Thin gutter; inner pad next to a border |
| **2** | Rare; two rows at 80×24 | Page inset; optical match to 1 row |
| **3+** | Do not | Do not |

Recipes:

- **Page chrome:** `EdgeInsets(left: 2, top: 1, right: 2, bottom: 1)` on
  the root `Container`.
- **Stack:** `Column(spacing: 1)` between distinct blocks; `spacing: 0`
  inside a list of rows.
- **Status / footer:** `SizedBox(height: 1, child: …)` pinned last. Do
  not pad it into a bar.
- **Bordered region:** a border already occupies one cell per edge.
  `Container` takes the per-side max of `padding` and border thickness —
  `padding: 1` plus `border: 1` does not become 2. Prefer the border as
  the inset; add padding only when glyphs sit on the border and become
  unreadable.
- **Button:** shipped default is one row with `horizontal: 1`. Do not
  add vertical pad.

Wide characters (CJK, many emoji) take 2 columns. Budget them in the
wireframe; do not assume `string.length` is the cell width.

## Chrome color: `ThemeData`, not a hex sheet

Chrome reads `Theme.of(context).token`. `Theme.of` falls back to
`ThemeData.dark`, which *is* the unthemed look. Wrapping a tree in
`Theme(data: ThemeData.dark)` changes nothing. A nullable fill
(`backgroundColor` on lists and fields) uses `Theme.maybeOf` and stays
empty without an ancestor `Theme`.

| Slot | Use for |
|---|---|
| `surface` | Page fill |
| `surfaceVariant` | Nested region, gutter, header row |
| `text` / `textMuted` | Body / hints, metadata, disabled labels |
| `border` | Box-drawing and `Divider` |
| `accent` / `accentForeground` | Primary action fill and text on it |
| `selectedBackground` / `selectedForeground` | Focused highlight row |
| `success` / `warning` / `danger` / `info` | Status, never decoration |

Content color stays a literal only when the color *is* the subject (a
speaker, a specimen, a teaching palette).

Focused lists, selects, and tables already paint `selectedBackground` and
mute to `surfaceVariant` when they do not own the keyboard. Do not
reimplement that with extra boxes.

Hand-roll a bordered region with `Container` + `BoxDecoration` +
`Theme.of(context).border`. Put the region's name on `Border.title`
(`title: ' Name '`) so it sits in the top edge, not on an inner row.
There is no public `Panel`, modal, or command-palette widget. In-repo examples
share `example/src/demo_scaffold.dart` for application-specific chrome. Use
`Stack`/`Positioned` for deliberate overlays and `Wrap` for cell-based runs.

## Type and copy

One face. Hierarchy is **bold**, **dim**, italic, and `textMuted` — not a
display font. `TextStyles.error` / `.success` / `.muted` / `.bold` cover
the common cases.

Copy is layout. Labels name what the person controls. A button says what
it does (`Save`, not `Submit`). Empty and error states say what to do
next. Keep a 1-row footer of the keys that work *right now*; do not
decorate it.

## Anti-slop

Do not:

- Port web chrome: radius, shadow, gradient, hero, serif display, 8px grid.
- Box every widget. Borders mark regions, not every `Text`.
- Paint everything cyan-on-black, or rainbow status for decoration.
- Default to a lazygit clone when the job is a form, a chat, or a table.
- Bind a bare letter at `app.onKey` (it steals typing). Tab already moves
  focus.
- Assume Nerd Fonts. For images, keep `ImageProtocol.auto` unless the
  application has a measured reason to force Kitty, Sixel, or block fallback.
- Animate selection or panel resize. Motion is for determinate progress
  and explicit `AnimationController` work.

## Floor before shipping a screen

- Fits and reads at 80×24; resize does not clip the only action.
- Keyboard-only: Tab/Shift+Tab, Enter/Space on controls, Esc back or
  dismiss where that is the job. `TuiApp.exit(context)` (or unconsumed
  Ctrl+C) quits.
- Usable if color is ignored: bold, dim, reverse/selection, and labels
  still distinguish state.
- Every control in the tree is a catalog widget or a composition of them.
