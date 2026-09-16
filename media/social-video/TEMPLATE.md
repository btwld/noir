# Noir social frame — how to reuse this

One composition, four ratios, no second file.

## Change the ratio

Edit only the root's `data-width` / `data-height` in `index.html`:

| Ratio | Size        | Where it goes                  |
| ----- | ----------- | ------------------------------ |
| 16:9  | 1920 × 1080 | X / LinkedIn timeline          |
| 4:5   | 1080 × 1350 | best feed real estate          |
| 1:1   | 1080 × 1080 | square feed                    |
| 9:16  | 1080 × 1920 | Reels / Shorts / TikTok        |

Then `npm run check && npm run render`. Nothing else changes.

The CLI's `--resolution` flag does **not** do this — it only raises DPR and
requires the aspect to already match the composition.

## Why it works: the container law

`#frame` sets `container-type: size`. Every frame-relative length is `cqw`
against it — never `vw`, never a hardcoded px. Hairlines (1px) and radii (12px)
stay in px on purpose; they are chrome, not layout.

**The trap:** a container cannot restyle itself from inside its own
`@container` rule. That is why the tokens live on `.stage`, one level down.
Putting them on `#frame` silently does nothing — the query never fires and the
layout stays landscape at every size.

At `max-aspect-ratio: 1/1` the panes stack and the type ramp steps up, so a
narrow frame keeps the same relative legibility instead of shrinking.

## Swap the content

Three `<section>` slots:

1. **`#s1` the premise** — `.lede` + `.sub`. The claim, then the old way.
2. **`#s2` the panes** — `.pane` × 2: code on the left, its real result on the
   right. Add `.code-line` / `.out-line` rows; the timeline staggers whatever
   is there.
3. **`#s3` the payoff** — `.payoff` + `.pkg`.

Timings are on each section's `data-start` / `data-duration`, and the GSAP
timeline at the bottom references the slots by id.

## House rules

- **One accent per frame.** `.hit` (amber) is the scarce voltage — the single
  thing the eye should land on. Two of them and neither reads.
- **Paste real output.** Every line in the failure pane came from an actual
  run. Mocked output in a developer-tool post is the fastest way to lose the
  room.
- **No fake terminal chrome.** The registry has a dozen
  `code-snippet-apple-terminal-*` blocks with macOS traffic lights. They
  contradict the whole point: this runs headless, with no terminal.
- **Let `check` do the design review.** It caught dim greys failing WCAG, a
  line overflowing into the next pane, and a font dropping below the
  large-text contrast threshold when it shrank. Run it before every render.

## Fonts

JetBrains Mono 400/700 ships in `assets/fonts/` with its OFL licence, declared
via `@font-face`. A named `font-family` with no in-file `@font-face` fails lint
(`font_family_without_font_face`), and a generic `monospace` renders as
whatever the render box happens to have.

## Commands

```sh
npm run check                                  # lint + runtime + layout + motion + contrast
npx hyperframes snapshot --at 1.5,8.6,11       # eyeball frames before rendering
npm run render                                 # MP4 into renders/
```

## Where the content comes from

`example/counter.dart` is the app the video shows. It is a real Noir app, not a
mock-up. To re-capture what it paints, from `packages/noir_driver/`:

```sh
cp ../../media/social-video/example/counter.dart test/fixtures/_c.dart
printf 'click key increment\ncapture --cells\nquit\n' |
  dart run --verbosity=error noir_driver:drive test/fixtures/_c.dart --size 26x5 --json
rm test/fixtures/_c.dart
```

The `--cells` JSON carries each cell's `char`, `fg`, `bg` and `attrs`. The
"what it paints" pane reproduces those exactly — the focused button really is
`#051a29` on `#66d9ff`, bold. Paste real output; a mocked frame in a
developer-tool post is the fastest way to lose the room.

## Positioning, checked against the field

"Flutter-like reactive UI, in your terminal" is accurate but **not
differentiating**. The Dart TUI space is crowded and several packages use the
same framing: `radartui` is "a Flutter-inspired TUI framework for Dart" with
"declarative widgets", and `termui` has a "widget tree structure inspired by
Flutter". Keep the line — it is the fastest way to convey the shape — but do
not expect it to carry the post.

The wedge is the testing story. Every comparable framework tests **in
process**: Textual has `pytest-textual-snapshot` (SVG screenshot diffing),
Bubble Tea has `teatest` with golden files, Ratatui has `TestBackend`. Ratatui's
own docs concede that TestBackend "tests rendering in-process, but does not
cover event loop, key handling, terminal setup and teardown or exit codes."

That is exactly the gap Noir Driver fills: a real OS process, input through the
production ANSI parser, clicks through real render-tree hit testing. So the
payoff line names it — "drives the real process, reads back real cells" — and
the video spends its two evidence beats there rather than on the widget API.
