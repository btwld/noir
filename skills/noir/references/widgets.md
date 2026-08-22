# Noir widget reference: layout, text & painting

Exact public constructors (source-verified), defaults, and a compact example
for each. Sizes are integer character cells; colors are `0.0–1.0` channels.

## Contents

- [Layout](#layout): `Container`, `Row` / `Column` / `Flex`, `Expanded` / `Flexible`, `Stack` / `Positioned`, `Wrap`, `Padding`, `SizedBox`, `Align`, `ConstrainedBox`, `DecoratedBox`
- [Theme](#theme): `Theme`, `ThemeData`
- [Chrome](#chrome): `Divider`, `Badge`, `ProgressBar`, `Spinner`
- [Geometry](#geometry): `EdgeInsets`, `Alignment`, `BoxConstraints`, `Size`, `Offset`, `Rect`
- [Painting](#painting): `Color`, `BoxDecoration`, `Border`, `Image`, `TerminalImage`
- [Text](#text): `Text`, `TextStyle`, `TextStyles`, `RichText` / `TextSpan`, `AsciiFont`
- [Parity components](#parity-components): `TabSelect`, `Slider`, `TextTable`, `CodeView`, `DiffView`, `MarkdownView`

---

## Images

`Image` loads and displays terminal graphics while `TerminalImage` owns one
already-decoded native image:

```dart
Image.memory(bytes, width: 24, height: 10, fit: ImageFit.fit)
Image.file('preview.webp', fit: ImageFit.cover)
Image.network(Uri.https('example.com', '/photo.jpg'), headers: {'authorization': token})
Image.rgba(pixels, pixelWidth: 2, pixelHeight: 2, rowStride: 8)
```

`Image(image: decoded)` borrows the supplied `TerminalImage`; dispose it in the
layer that created it. Every named source constructor owns and disposes its
decoded result. Mutable bytes and network headers are snapshotted. Rebuilding
with an equal source does not reload, replacing a source suppresses stale
callbacks and disposes late results, and a previous successful image remains
visible while its replacement loads or fails.

Explicit cell `width` / `height` and tight parent constraints win. Otherwise
natural sizing uses measured terminal pixels per cell, or a nominal one-by-two
cell pixel ratio. `ImageFit.fit` centers the complete image,
`ImageFit.cover` center-crops, and `ImageFit.fill` stretches. Protocol choices
are `auto`, `kitty`, `sixel`, and `blocks`; automatic selection and unavailable
Sixel fallbacks are owned by OpenTUI. File, network, and encoded-memory inputs
are limited to 64 MiB. Network sources accept HTTP(S) only.

`loadingBuilder` and `errorBuilder` appear only before any source succeeds;
`onLoad` and `onError` observe only the current source.

## Layout

### Container

The Flutter-style convenience box: optional padding, background, border, fixed
size, alignment, and margin around one child.

```dart
const Container({
  Alignment? alignment,
  EdgeInsets? padding,
  Color? color,                       // background fill — mutually exclusive with `decoration`
  BoxDecoration? decoration,          // border + fill — use instead of `color` when you need a border
  BoxDecoration? foregroundDecoration, // painted in front of the child (layering)
  int? width,
  int? height,
  BoxConstraints? constraints,
  EdgeInsets? margin,
  Widget? child,
  Key? key,
})
```

Rule: pass **`color` OR `decoration`, not both**. `color` is shorthand for a
plain fill; `decoration` is for borders/shapes.

```dart
// Plain fill:
Container(color: Color.rgb(0.05, 0.06, 0.1), padding: const EdgeInsets.all(2), child: child)

// Bordered panel:
Container(
  padding: const EdgeInsets.all(1),
  decoration: BoxDecoration(
    color: Color.rgb(0.07, 0.12, 0.18),
    border: Border.all(color: Color.cyan),
  ),
  child: child,
)
```

### Row / Column / Flex

`Row` (horizontal) and `Column` (vertical) are the two concrete subclasses of
the **abstract** `Flex`. `Flex` is exported so you can name it in a type
position, but it cannot be constructed — reach for `Row` or `Column`.
`spacing` inserts a gap between adjacent children; prefer it over manual
`SizedBox` separators.

```dart
const Row({
  Key? key,
  MainAxisAlignment mainAxisAlignment = MainAxisAlignment.start,
  MainAxisSize mainAxisSize = MainAxisSize.max,
  CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
  List<Widget> children = const [],
  int spacing = 0,
})
// Column takes exactly the same parameters; each fixes `direction` for you.
```

`spacing` must be a non-negative number of whole terminal cells.

Enums:
- `MainAxisAlignment` — `start`, `end`, `center`, `spaceBetween`, `spaceAround`, `spaceEvenly`
- `CrossAxisAlignment` — `start`, `end`, `center`, `stretch`
- `MainAxisSize` — `min` (shrink to children), `max` (fill available)

```dart
Column(
  mainAxisAlignment: MainAxisAlignment.center,
  crossAxisAlignment: CrossAxisAlignment.start,
  spacing: 1,
  children: [Text('A'), Text('B'), Text('C')],
)
```

### Expanded / Flexible

Place inside a `Row`/`Column` to divide leftover main-axis space. `Expanded` is
`Flexible` with `fit: FlexFit.tight` (must fill its share); plain `Flexible` with
`FlexFit.loose` takes *at most* its share.

```dart
const Flexible({ required Widget child, int flex = 1, FlexFit fit = FlexFit.loose, Key? key })
const Expanded({ required Widget child, int flex = 1, Key? key })  // fit is always tight
```

`flex` weights the split: `Expanded(flex: 2)` next to `Expanded(flex: 1)` gets
two-thirds of the free space. `FlexFit` values: `tight`, `loose`.

### Padding

```dart
const Padding({ required EdgeInsets padding, Widget? child, Key? key })
```

```dart
Padding(padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1), child: child)
```

### SizedBox

Fixed dimensions, or a fixed gap when used with no child.

```dart
const SizedBox({ int? width, int? height, Widget? child, Key? key })
const SizedBox.shrink({ Key? key })             // 0×0
const SizedBox.square({ required int dimension, Widget? child, Key? key })
```

```dart
const SizedBox(height: 1)        // one blank row between widgets
```

### Align

Positions a (possibly smaller) child within itself.

```dart
const Align({ Alignment alignment = Alignment.center, Widget? child, Key? key })
```

### ConstrainedBox

Imposes additional min/max constraints on its child.

```dart
const ConstrainedBox({ required BoxConstraints constraints, Widget? child, Key? key })
```

### DecoratedBox

Paints a `Decoration` before (default) or after the child — `Container` uses this
under the hood; reach for it directly when you only need decoration.

```dart
const DecoratedBox({
  required Decoration decoration,
  DecorationPosition position = DecorationPosition.background, // or .foreground
  Widget? child,
  Key? key,
})
```

---

## Theme

### Theme / ThemeData

Built-in widgets resolve omitted colors as
`explicitParameter ?? Theme.of(context).token`. `Theme.of` falls back to
`ThemeData.dark`, which is the unthemed appearance — wrapping a tree in
`Theme(data: ThemeData.dark)` changes nothing. The one exception is a
nullable `backgroundColor`: no color means "no fill", so those resolve
through `Theme.maybeOf` and stay empty without an ancestor `Theme`.

```dart
const Theme({required this.data, required super.child, super.key});

const ThemeData({
  this.surface = const Color(0.035, 0.038, 0.044),
  this.surfaceVariant = const Color(0.06, 0.064, 0.075),
  this.text = Color.white,
  this.textMuted = const Color(0.6, 0.6, 0.6),
  this.border = const Color(0.18, 0.22, 0.28),
  this.accent = const Color(0.4, 0.85, 1),
  this.accentForeground = const Color(0.02, 0.1, 0.16),
  this.selectedBackground = const Color(0.2, 0.4, 0.8),
  this.selectedForeground = Color.white,
  this.cursor = Color.white,
  this.scrollbarThumb = const Color(0.7, 0.7, 0.7),
  this.scrollbarTrack = const Color(0.2, 0.2, 0.2),
  this.success = Color.success,
  this.warning = Color.warning,
  this.danger = Color.error,
  this.info = Color.info,
});
static const ThemeData dark = ThemeData();
ThemeData copyWith({ Color? surface, /* + every other token */ })
```

```dart
Theme(
  data: ThemeData.dark.copyWith(accent: Color.magenta),
  child: const Button(label: 'Run'),
)
```

Use `Theme.of(context)` when you always need a color. Use `Theme.maybeOf`
when "no theme" and "themed" must paint differently.

---

## Chrome

### Divider

A solid band of `thickness` cells, not a run of `─`. It spans the bounded
cross axis. A horizontal rule in a `Column` is fine; a vertical rule in a
`Row` needs an explicit height, because a loose `Row` offers unbounded
height and the rule would paint zero cells.

```dart
const Divider({
  Key? key,
  this.thickness = 1,
  this.color,                         // ThemeData.border
  this.axis = Axis.horizontal,
})
```

```dart
Column(children: [header, const Divider(), body])
SizedBox(height: 3, child: Divider(axis: Axis.vertical))
```

### Badge

A short, bold, filled tag. Passive: no focus, no callback.

```dart
const Badge({
  required this.label,
  Key? key,
  this.variant = BadgeVariant.neutral,  // neutral | success | warning | danger | info
  this.color,
  this.textColor,                       // ThemeData.accentForeground
})
```

```dart
Badge(label: 'STAGED', variant: BadgeVariant.success)
```

### ProgressBar

One row, `width` cells, eighth-cell steps. `value` is clamped to `0..1`.

```dart
const ProgressBar({
  required this.value,
  Key? key,
  this.width = 20,
  this.color,                           // ThemeData.accent
  this.trackColor,                      // ThemeData.scrollbarTrack
})
```

### Spinner

One-cell animated glyph. Animates while mounted; remove it when the work
ends. `SpinnerFrames.dots` needs Braille; `SpinnerFrames.line` is ASCII.

```dart
const Spinner({
  Key? key,
  this.color,                           // ThemeData.accent
  this.frames = SpinnerFrames.dots,
  this.interval = const Duration(milliseconds: 80),
})
```

---

## Geometry

### EdgeInsets

Integer-cell insets.

```dart
const EdgeInsets({ int left = 0, int top = 0, int right = 0, int bottom = 0 })
const EdgeInsets.all(int v)
const EdgeInsets.symmetric({ int vertical = 0, int horizontal = 0 })
const EdgeInsets.only({ int left = 0, int top = 0, int right = 0, int bottom = 0 })
// EdgeInsets.zero is a const.
```

### Alignment

Fractional position in `[-1, 1]` on each axis (`-1` = top/left, `0` = center,
`1` = bottom/right).

```dart
const Alignment(double x, double y)
// Constants: center, topLeft, topCenter, topRight, centerLeft, centerRight,
//            bottomLeft, bottomCenter, bottomRight
```

### BoxConstraints

```dart
const BoxConstraints({ int? maxWidth, int? maxHeight, int minWidth = 0, int minHeight = 0 })
const BoxConstraints.tight({ required int width, required int height })
const BoxConstraints.loose({ int? maxWidth, int? maxHeight })
const BoxConstraints.expand({ int? width, int? height })
```

`null` max = unbounded on that axis.

### Size / Offset / Rect

```dart
const Size(int width, int height)         // Size.square(int dimension)
const Offset(int dx, int dy)              // Offset.zero
const Rect.fromLTWH(int left, int top, int width, int height)  // Rect.fromLTRB(...), Rect.zero
```

---

## Painting

### Color

Immutable RGBA, channels normalized `0.0–1.0`.

```dart
const Color(double r, double g, double b, [double a = 1.0])
const Color.rgb(double r, double g, double b)
factory Color.fromHex(String hex)         // '#rrggbb' or '#rrggbbaa'
```

Named constants:
- Grayscale: `white`, `lightGray`, `gray`, `darkGray`, `black`
- Primary: `red`, `green`, `blue`, `yellow`, `magenta`, `cyan`
- Semantic: `success`, `warning`, `error`, `info`
- Transparency: `transparent`, `whiteTransparent`, `blackTransparent`, `grayTransparent`

```dart
Color.rgb(0.2, 0.4, 0.8)   // custom
Color.cyan                 // named
Color.fromHex('#1e90ff')   // hex
```

### BoxDecoration

```dart
const BoxDecoration({
  Color? color,
  BoxBorder? border,
  BoxShape shape = BoxShape.rectangle, // or BoxShape.circle
})
```

### Border

Default color is **black** — pass `color:` explicitly for visible borders on dark
backgrounds.

```dart
Border.all({
  Color color = Color.black,
  BorderStyle style = BorderStyle.solid,  // or BorderStyle.none
  String? title,                          // optional label drawn on the top edge
  TextAlign titleAlignment = TextAlign.left,
  bool fill = false,
  List<int>? borderChars,                 // 11 custom box-drawing codepoints
})
Border.symmetric({ bool vertical = true, bool horizontal = true, /* + same styling args */ })

// Unnamed constructor: pick individual edges via `sides`.
Border({
  Color color = Color.black,
  BorderStyle style = BorderStyle.solid,
  BorderSides sides = const BorderSides(),  // all four true by default
  String? title,
  TextAlign titleAlignment = TextAlign.left,
  bool fill = false,
  List<int>? borderChars,
})
const BorderSides({ bool top = true, bool right = true, bool bottom = true, bool left = true })
```

All three `Border` constructors are regular, non-`const` constructors because
they validate and snapshot a caller-supplied `borderChars` list.

```dart
Border.all(color: Color.cyan, title: 'Logs')

// A single rule above a status bar — one edge only:
Border(color: Color.gray, sides: const BorderSides(left: false, right: false, bottom: false))
```

`title` only renders when the top side is drawn.

---

## Text

### Text

```dart
const Text(
  String data, {
  TextStyle? style,
  TextAlign textAlign = TextAlign.left,   // left | center | right
  int? maxLines,
  bool softWrap = true,
  TextOverflow overflow = TextOverflow.clip,
  TextHighlight? selection,
  Key? key,
})
const Text.rich(TextSpan textSpan, { /* same styling args */ })
```

`style` defaults to white foreground when omitted.

### TextStyle

```dart
const TextStyle({
  Color color = Color.white,
  Color? backgroundColor,
  FontWeight? fontWeight,                  // normal | bold | dim
  FontStyle? fontStyle,                    // normal | italic
  TextDecoration? decoration,              // none | underline | lineThrough
  TextEffect? effect,                      // none | blink | reverse
  int? attributes,
})
```

Chainable helpers exist: `style.bold()`, `.italic()`, `.underline()`, `.dim()`,
`.blink()`, `.reverse()`, `.strikethrough()`, plus `copyWith(...)`.
Combine underline and line-through with
`TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough])`.

```dart
Text('Saved', style: TextStyle(color: Color.green, fontWeight: FontWeight.bold))
Text('hint',  style: const TextStyle(color: Color.lightGray).italic())
```

### TextStyles (prebuilt constants)

Use these instead of re-deriving common styles: `TextStyles.normal`, `.bold`,
`.italic`, `.underline`, `.dim`, `.error`, `.warning`, `.success`, `.info`,
`.muted`, `.highlight`, `.selection`, `.h1`, `.h2`, `.h3`, `.code`, `.link`.

```dart
Text('Build failed', style: TextStyles.error)
```

### RichText / TextSpan

Compose runs with different styles. A `TextSpan`'s `style` applies to its text
and cascades to unstyled children.

```dart
const TextSpan({ String? text, TextStyle? style, Uri? uri, List<InlineSpan> children = const [] })

RichText(
  text: TextSpan(
    style: const TextStyle(color: Color.white),
    children: [
      const TextSpan(text: 'Status: '),
      TextSpan(text: 'OK', style: const TextStyle(color: Color.green, fontWeight: FontWeight.bold)),
    ],
  ),
)
```

You can also use `Text.rich(span)` for the same effect with `Text`'s ergonomics.

## Parity components

### Stack, Positioned, and Wrap

`Stack` overlays children in document order. Non-positioned children are laid
out loose by default; `StackFit.expand` gives them the stack's complete
constraints. `Positioned` sets absolute whole-cell offsets or an explicit
extent. Supplying both opposing offsets expands that axis. Stack overflow is
hard-edge clipped unless `clip: false` is deliberate.

```dart
Stack(
  fit: StackFit.expand,
  alignment: Alignment.center,
  children: const [
    Text('background'),
    Positioned(right: 1, top: 0, child: Badge(label: 'NEW')),
  ],
)

Wrap(
  direction: Axis.horizontal,
  spacing: 1,
  runSpacing: 1,
  alignment: WrapAlignment.start,
  runAlignment: WrapAlignment.start,
  crossAxisAlignment: WrapCrossAlignment.start,
  children: tags,
)
```

`Wrap` supports horizontal and vertical runs. Its `spacing`, `runSpacing`,
main-run alignment, run alignment, and cross alignment are all cell-based.

### TabSelect and Slider

`TabSelect<T>` reuses `SelectOption<T>` but presents a horizontal fixed-width
tab strip. Left/Right and `[`/`]` move, Enter confirms, and a left click both
selects and confirms. It owns focus only when no `focusNode` is supplied.

```dart
TabSelect<String>(
  options: const [
    SelectOption(name: 'Files', description: 'Changed paths', value: 'files'),
    SelectOption(name: 'Diff', description: 'Current patch', value: 'diff'),
  ],
  selectedIndex: selected,
  tabWidth: 14,
  showScrollArrows: true,
  showDescription: true,
  showUnderline: true,
  wrapSelection: false,
  onChanged: (index, option) => setState(() => selected = index),
  onSelect: (index, option) => open(option.value),
)
```

This does not replace `Select<T>`: `Select` remains the vertical,
viewport-based option list. `TabSelect` is the horizontal navigation surface.

`Slider` is controlled: it proposes a value through `onChanged`, and the
caller rebuilds with that value. A null callback disables pointer and keyboard
input. It supports either `Axis`, pointer drag, arrows, PageUp/PageDown,
Home/End, `step`, and a viewport-sized thumb.

```dart
Slider(
  value: progress,
  min: 0,
  max: 100,
  viewportSize: 20,
  step: 5,
  axis: Axis.horizontal,
  onChanged: (value) => setState(() => progress = value),
)
```

### AsciiFont and TextTable

`AsciiFont` renders natural-sized multi-row glyphs from Noir's original 5x7
printable-ASCII alphabet. The `tiny`, `block`, `shade`, `slick`, `huge`,
`grid`, and `pallet` families are seven generated visual treatments of that
one alphabet. Lowercase input uses the corresponding uppercase glyph. `color`
supplies a solid fallback; `colors` supplies the ordered palette used by
multi-color families. `backgroundColor` fills the natural glyph box, and
`selection` maps UTF-16 source ranges to complete glyph boxes.

```dart
const AsciiFont(
  'NOIR',
  family: AsciiFontFamily.pallet,
  colors: [Color.cyan, Color.blue],
)
```

`TextTable` is a finite `List<List<InlineSpan?>>` grid. Choose word,
character, or no wrapping; content-sized or full width; proportional or
balanced column fitting; and cell padding, border, or borderless column gaps.
Its `selection` is indexed over row-major plain text separated by tabs and
newlines. By default the table owns pointer drag, all four Shift+arrow
directions, Ctrl+A, Escape, and explicit Ctrl+C copy. Use `focusNode`,
`autofocus`, selection colors, `onSelectionChanged`, and `onCopy` with the
same ownership rules as document widgets. The optional `selection` remains a
controlled paint override for applications that coordinate a larger region.

```dart
const TextTable(
  content: [
    [TextSpan(text: 'Name'), TextSpan(text: 'Status')],
    [TextSpan(text: 'Noir'), TextSpan(text: 'ready')],
  ],
  wrapMode: TextTableWrapMode.word,
  columnWidthMode: TextTableColumnWidthMode.full,
  columnFitter: TextTableColumnFitter.proportional,
  cellPadding: 1,
)
```

`TextTable` does not replace `DataTable`. Keep `DataTable` for a virtualized,
interactive row source with selection and sorting; use `TextTable` for a
static rich-text grid.

### CodeView, DiffView, and MarkdownView

All three document widgets provide scrolling, optional wrapping, grapheme-safe
pointer/Shift+arrow selection, Ctrl+A, Escape, and explicit Ctrl+C copy.
`onSelectionChanged` receives immutable `SelectedText`; `onCopy` reports the
OSC52 result without clearing the selection. Ctrl+C is consumed only while a
non-empty selection exists, leaving Noir's ordinary interrupt fallback intact
otherwise. Foreground and background selection colors are configurable on all
three document widgets and flow through their shared document viewports.

`CodeView` accepts a `CodeHighlighter`. Its `highlight` method returns
synchronous or asynchronous non-overlapping UTF-16 `StyledTextRange`s. Invalid
ranges and thrown/failed futures call `onHighlightError`, fall back to plain
text, and stale async generations are ignored. Noir ships only
`PlainTextCodeHighlighter`; language engines remain application dependencies.

```dart
CodeView(
  code: source,
  language: 'dart',
  highlighter: highlighter,
  wrap: false,
  showLineNumbers: true,
  selectable: true,
)
```

Parse standard or Git unified patches with `UnifiedDiffParser`, then render a
`DiffDocument` through `DiffView`. It supports `DiffViewMode.unified` and
`split`, one synchronized viewport, optional highlighting and gutters,
`DiffViewController.jumpToHunk`, semantic hunk/line callbacks, and a
`rowBuilder` that can wrap or replace each default row. A replacement row owns
its own selection presentation, while the surrounding `DiffView` retains the
complete semantic selection and copy stream. Wrapping the default row keeps
both document-wide selection behavior and Noir's built-in visual highlight.

`MarkdownView` reparses changed source with `package:markdown`'s
GitHub-flavoured extension set. It renders headings, paragraphs, emphasis,
strikeout, links, lists/tasks, quotes, rules, fenced `CodeView`s, and
`TextTable`s. Consecutive heading blocks stay tight against the following
block; a one-cell gap appears only after a non-heading block. Empty table
columns (header plus all-empty body cells) are omitted, and content-mode
tables paint to their grid width so a stretch parent cannot inflate the last
column. GitHub `<details>`/`<summary>` wrappers are unwrapped into
visible inner markdown before parsing, because that extension set leaves the
tags as raw text. Parsing uses `encodeHtml: false` so table cells and inline
code keep literal `>=` / `<` instead of `&gt;` / `&lt;`. Markdown images
become linked alt text and never fetch by default. `embedded: true` sizes the
document to its blocks and omits the inner
`ScrollBox`, so a parent viewport can own scrolling. `blockRenderer` receives
the actual `package:markdown` AST node as an
`Object` plus a `buildDefault` callback; import `package:markdown/markdown.dart`
and type-check/cast when inspecting it. A replacement changes presentation,
while whole-document selection and copy retain the parsed block's default
semantic text because an arbitrary replacement widget cannot expose plain
text. A custom renderer may explicitly return `Image.network` when network
loading is intended.

`TextSpan(uri: ...)` emits a native terminal hyperlink only for visible,
non-empty runs. URLs longer than OpenTUI's 512-byte UTF-8 limit are rejected.
