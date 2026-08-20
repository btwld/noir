# Pub Search Interaction Cleanup Design

Date: 2026-08-20

## Verdict

Refine the existing implementation. The page structure, theme, focus model,
and full-screen package detail flow already solve the terminal job cleanly at
80×24. The remaining problem is interaction discoverability and proof: help
copy does not consistently describe the action available to the current focus
owner, and application-level tests do not yet lock the mouse and cursor
behavior that the implementation already intends.

## Problem Reframed

The pub-search example must let a terminal user:

- enter and submit a pub.dev query;
- distinguish whether the query, result list, or detail panel owns input;
- select and open a package with either keyboard or mouse;
- switch package sections with arrows, digits, or a single mouse click;
- scroll detail content without losing the section or focus state;
- understand the currently available commands at 80×24; and
- retain a clean, product-faithful layout at wider terminal sizes.

The existing full-screen search/detail structure is a design choice, not a
requirement. A clean-sheet comparison nevertheless keeps it: a split view
would reduce usable detail width and vertical room at the supported 80×24
floor, while heavier boxed controls would add chrome without improving the
demonstrated workflow.

## Evidence From the Existing Implementation

Noir Driver and rendered-cell captures establish that:

- the query shows an amber blinking block cursor while focused;
- the cursor is hidden while results or detail owns focus;
- a single click on a package row opens its detail view;
- each one-row tab responds to a single click across its padded hitbox;
- the active tab paints the theme accent across the label and padding;
- query, results, and detail borders transfer the focus accent correctly;
- all bottom borders and help rows fit at 80×24; and
- the same hierarchy expands without clipping at 120×32.

Direct Computer Use inspection was available for VS Code. Apple Terminal and
iTerm control were rejected by the environment safety policy, so Noir Driver's
production-parser input and exact rendered-cell capture remain the
authoritative terminal evidence.

## What Stays

- `DemoScaffold` page chrome and `DemoPanel` focus borders.
- The branded `pubTheme` and semantic component tokens.
- Search-first navigation with a separate full-screen detail surface.
- The query `TextInput`, result `Select`, and detail `ScrollBox` ownership.
- A one-row, non-focusable tab strip above the detail panel.
- Single-click activation for package rows and tabs.
- Arrow and digit shortcuts for tabs and ordinary focus traversal for search.
- The status row, loading/error/empty states, and executable's live-only
  `PubApiCatalog` data source. Deterministic catalogs remain test and capture
  infrastructure only.

## Interaction and Copy Design

### Search

The scaffold hint follows the focus owner and the state that is actually
actionable:

- Idle query: `Enter search   Esc quit`
- Query with a result surface: `Enter search  Tab sort  Esc quit`
- Focused results: `↑↓ select  Enter/click open  s/f pick  / query  Esc`

After an eligible edit, completion waits 300 ms, then makes fresh hosted name
and topic requests. The spinner appears only while that request is active;
there is no app-owned completed or in-flight completion cache. Query, sort,
and filter are individual focus owners: traversal is query → sort → filter →
results when results exist, and query → sort → filter for an empty result.
Sort and filter are launchers, not cycling controls. Enter, Space, a click, or
the result-list `s`/`f` shortcut opens an in-panel `Select`; arrows only move
its temporary highlight, while Enter/click applies and Tab/Escape cancels.

Pagination remains visible in the status row. `<page>` is omitted when neither
direction is available, becomes `n next` or `p prev` when only one direction is
available, and becomes `n/p page` when both are available. The hint must not
advertise an unavailable page action. Every resolved variant fits the 76-cell
content width at 80×24.

A package row opens immediately on one left click, matching `Select.onSelect`.
Keyboard users move with arrows and open with Enter. The selected row remains
subtle while the query owns focus and uses `selectedBackground` when the list
owns focus.

### Detail tabs

The tab row remains a flat strip rather than joining focus traversal. The
active tab uses `accent` fill, `accentForeground`, and bold text; inactive tabs
use muted text with the same one-cell horizontal padding. A single left click
anywhere inside that padded region switches immediately to the clicked tab.

The detail help becomes:

`←→/1–4/click tabs  ↑↓/PgUp/PgDn scroll  / search  Esc results`

This fits inside the 76-cell content width at 80×24 and makes the mouse path
discoverable without adding another row.

### Cursor and focus

The text cursor remains an amber blinking block and is visible only while the
query owns focus. It is hidden in results and detail. Focus ownership continues
to be represented independently of color by the selected-row treatment and
panel title/border emphasis.

Terminal applications do not control an OS pointer cursor shape through Noir;
no web-style hand cursor is introduced. Mouse affordance comes from the active
fill, selected row, contextual help, and immediate click response.

## 80×24 Layout Contract

Search retains one page header, one query panel, one compact status row, and
one expanding results panel:

```text
  PUB / FIND
  <contextual commands>

  ┌─ SEARCH ─────────────────────────────────────────────────────────────────┐
  │query                                                                     │
  └──────────────────────────────────────────────────────────────────────────┘

  SORT [TOP ▾]   FILTER [ANY ▾]                                       PAGE  1

  ┌─ RESULTS ────────────────────────────────────────────────────────────────┐
  │3 PACKAGES                                                                │
  │selected package                                                          │
  │...                                                                       │
  └──────────────────────────────────────────────────────────────────────────┘
```

Detail retains its package identity, metrics, single-row tabs, expanding
scroll panel, and one-row command footer. Chrome is not added or moved into the
content viewport.

## Failure and Boundary Behavior

- Loading keeps its spinner and preserves the previous result list when one
  exists.
- Search loading shows its one spinner in Results; an open chooser shows its
  one `Updating results…` indicator above the picker. Completion loading is
  local to the query field, and detail loading is local to the detail surface.
- Empty results return focus to the query and do not advertise result actions.
- Search and package errors retain their retry paths and semantic danger color.
- Escape returns detail to results and exits from search through `TuiApp.exit`.
- Resize must preserve the only actionable controls and bottom frame at 80×24;
  120×32 should add space rather than introduce a different information
  architecture.

## Test and Review Contract

Add focused application regressions that prove:

1. A package row opens on a single click.
2. Clicking the horizontal padding of every detail tab selects it.
3. The selected tab's padding and label use the accent background and
   accent-foreground text.
4. Query focus shows the amber block cursor; results and detail hide it.
5. Contextual help changes with focus and does not advertise unavailable
   actions.
6. Keyboard search, selection, opening, tab switching, scrolling, and Escape
   behavior remain unchanged.

Regenerate affected visual goldens, then use Noir Driver to capture idle,
autocomplete loading and suggestions, both open pickers, sort and filter
refresh loading, empty and error states, detail loading, and all four detail
tabs at 80×24 and 120×32. Review each pair for borders, selection, spinner
placement, tab fill, cursor state, copy fit, wrapping, scrollbar placement,
and bottom-row preservation. Obtain an independent behavior/diff review before
the full authorized verification suite.

## Non-goals

- No split-view redesign or responsive breakpoint.
- No new framework widget, hover system, or pointer-cursor API.
- No public catalog, API, model, sorting, filtering, or pagination redesign.
- No extra border, modal, command palette, animation, or second help row.
- No compatibility shim for obsolete example APIs.

## Compatibility

The refinement preserves the example's public constructors and catalog model.
Only visible command copy and additional regression coverage are expected to
change. Existing keyboard and mouse behavior remains compatible.
