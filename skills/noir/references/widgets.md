# Noir widget reference: layout, text & painting

Exact public constructors (source-verified), defaults, and a compact example
for each. Sizes are integer character cells; colors are `0.0–1.0` channels.

## Contents

- [Layout](#layout): `Container`, `Row` / `Column` / `Flex`, `Expanded` / `Flexible`, `Padding`, `SizedBox`, `Align`, `ConstrainedBox`, `DecoratedBox`
- [Geometry](#geometry): `EdgeInsets`, `Alignment`, `BoxConstraints`, `Size`, `Offset`, `Rect`
- [Painting](#painting): `Color`, `BoxDecoration`, `Border`
- [Text](#text): `Text`, `TextStyle`, `TextStyles`, `RichText` / `TextSpan`

---

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
const Border.all({
  Color color = Color.black,
  BorderStyle style = BorderStyle.solid,  // or BorderStyle.none
  String? title,                          // optional label drawn on the top edge
  TextAlign titleAlignment = TextAlign.left,
  bool fill = false,
  List<int>? borderChars,                 // 11 custom box-drawing codepoints
})
Border.symmetric({ bool vertical = true, bool horizontal = true, /* + same styling args */ })

// Unnamed constructor: pick individual edges via `sides`.
const Border({
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

`Border.symmetric` is a regular generative constructor and is not `const`;
`Border.all` and the unnamed `Border` are.

```dart
Border.all(color: Color.cyan, title: 'Logs')

// A single rule above a status bar — one edge only:
const Border(color: Color.gray, sides: BorderSides(left: false, right: false, bottom: false))
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
  List<TextDecoration>? decoration,        // none | underline | lineThrough
  TextEffect? effect,                      // none | blink | reverse
  int? attributes,
})
```

Chainable helpers exist: `style.bold()`, `.italic()`, `.underline()`, `.dim()`,
`.blink()`, `.reverse()`, `.strikethrough()`, plus `copyWith(...)`.

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
const TextSpan({ String? text, TextStyle? style, List<InlineSpan> children = const [] })

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
