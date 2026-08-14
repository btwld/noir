# Counter alignment and visual polish

## Context and reviewed findings

The Flutter-style counter is functionally complete, but its first VS Code
capture exposes two visual problems with different causes.

1. The action surface composes a 7x3 rounded glyph border around a separate
   5x1 blue fill. Terminal border glyphs paint foreground strokes while keeping
   the surface background visible, so the result reads as a small blue pill
   inside an outlined frame. This is an example-composition choice, not a
   pointer or layout-engine failure.
2. The three-row app bar requests `Alignment.centerLeft`, but its title paints
   on the first row. `RenderPositionedBox` currently lays its child out with the
   parent's tight constraints. The child therefore occupies the entire box and
   leaves no remaining extent for `Alignment` to position. Existing alignment
   coverage proves visibility and accumulated offsets, but not the documented
   position within a tight bounded box.

The selected change fixes the framework alignment defect and then simplifies
the counter composition so both the title and action use the corrected public
layout behavior.

## Considered approaches

### 1. Repair `Align` and simplify the counter (selected)

Lay out an `Align` child with loose constraints bounded by the available
maximum extent, while the `RenderPositionedBox` itself continues to fill each
bounded axis and shrink-wrap each unbounded axis. Then replace the counter's
glyph borders with flat color surfaces.

This restores the documented `Align` contract for every consumer and lets the
example remain idiomatic. It carries a wider regression surface than an
example-only edit, so it requires focused render-layout tests, affected visual
checks, architecture checks, and the ordinary suite.

### 2. Work around alignment in the counter

Hard-code blank rows or padding around the title and plus glyph. This is a
smaller diff, but it leaves a framework primitive behaving contrary to its
documentation and teaches consumers to compensate for broken layout.

### 3. Retain and fill the border glyphs

Paint a blue background behind the existing rounded outline. This reduces the
white gap but preserves the outline the user asked to remove and does not
address title alignment.

## Framework behavior

`RenderPositionedBox.performBoxLayout` will give its child loose constraints
whose maxima match the incoming bounded maxima. This permits text and other
naturally sized children to report their intrinsic constrained size.

The render object then keeps its existing parent-size rule:

- on a bounded axis, fill the available maximum extent;
- on an unbounded axis, shrink-wrap the laid-out child and constrain that
  result against the incoming minimum;
- position the child from the remaining integer-cell extent using the selected
  `Alignment`.

For a 7x3 bounded box containing a one-cell `Text('+')`, center alignment must
place the glyph at `(3, 1)`. In a three-row full-width app bar,
`Alignment.centerLeft` must place a one-row title on the middle row while
preserving its left inset.

The change stays within the existing public API. It adds no compatibility shim,
new widget, FFI call, native behavior, or OpenTUI change.

## Counter composition

The counter retains its full-frame warm-white surface, three-row Material-blue
app bar, centered body, bottom hint, state ownership, keyboard bindings, mouse
enablement, pointer callback, and hot-reload registration.

The visual polish changes only these details:

- The app bar becomes one flat `#1976D2` surface with no darker bottom border.
- `Noir Counter` remains bold white, horizontally inset by two cells, and is
  vertically centered on the app bar's middle row by `Alignment.centerLeft`.
- The increment action becomes one solid 7x3 `#1976D2` surface. At the observed
  VS Code terminal cell ratio, the filled area reads as a square action tile
  rather than a 5x1 pill inside a frame.
- The bold white `+` is centered in that entire surface.
- No rounded box-drawing glyph, border decoration, dark-rule color, or separate
  inner fill remains.
- `PointerListener` continues to wrap the full 7x3 action, so a left-button down
  anywhere inside the tile increments exactly once. Release, middle, and right
  events remain ignored.

The action remains two cells from the right terminal edge and one row from the
bottom edge. Compact layouts retain the title, counter, and action.

## Test-first contract

The implementation proceeds in red/green order.

Focused rendering tests will first demonstrate the current defect by asserting
exact cell coordinates for naturally sized children under center,
center-left, and bottom-right alignment in tight bounded boxes. The failure
must show a wrong child position rather than a mount, paint, or lookup error.

The counter visual test will then be updated before the example:

- title at row 1 of the three-row app bar;
- blue background across all three app-bar rows and no dark rule glyph;
- solid blue background across every cell of the 7x3 action surface;
- centered bold white plus with no rounded border glyphs;
- unchanged body centering, bottom placement, and full keyboard hint;
- left-click activation from a non-glyph corner of the action surface, proving
  that its entire visible area is interactive;
- unchanged ignored release, middle-button, and right-button behavior;
- unchanged keyboard, entrypoint, and compact-layout behavior.

Any visual goldens changed by the corrected `Align` semantics will be reviewed
individually and updated only when their prior output encoded the alignment
defect.

## Documentation and evidence

The original counter design, root README, example README, changelog, and release
evidence must not continue to advertise rounded borders or a dark app-bar rule.
They will describe the flat app bar and solid square-style action tile after
the focused behavior is green.

After automated verification, Computer Use will operate the already-open VS
Code integrated terminal and run `dart run example/counter.dart`. The pass will
capture a fresh polished frame and compare it with the earlier screenshot,
confirming:

1. no app-bar outline or rule;
2. vertically centered title;
3. one solid, square-reading action surface with a centered plus and no outline;
4. keyboard activation and a real left click still increment exactly once;
5. Ctrl+C returns to a usable shell without a stack trace.

Screenshots remain gitignored validation artifacts under `.context`.

## Verification

The exact final tree must pass:

```text
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ scripts/
dart analyze --fatal-infos
dart test test/rendering/align_offset_test.dart test/example/counter_test.dart --concurrency=1
dart test test/architecture/ --concurrency=1
dart test --concurrency=1
dart run scripts/fetch_opentui_binaries.dart --verify-only
dart pub publish --dry-run
git diff --check
```

An independent behavior and full-diff review must report no unresolved Critical
or Important issue before completion.

## Acceptance criteria

The work is complete when the title and plus are correctly centered through the
fixed `Align` primitive, the two unwanted outlines are absent, the complete
action tile remains clickable, docs match the rendered UI, fresh screenshots
show the requested polish, all authorized checks pass, and independent review
has no unresolved Critical or Important finding.
