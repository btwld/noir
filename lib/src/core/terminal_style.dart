/// How terminal text should be aligned horizontally.
enum TextAlign {
  /// Align content to the left edge.
  left,

  /// Center content in the available width.
  center,

  /// Align content to the right edge.
  right,
}

/// Selects which sides of a terminal box are drawn.
final class BorderSides {
  /// Creates a side mask.
  const BorderSides({
    this.top = true,
    this.right = true,
    this.bottom = true,
    this.left = true,
  });

  /// Whether to draw the top side.
  final bool top;

  /// Whether to draw the right side.
  final bool right;

  /// Whether to draw the bottom side.
  final bool bottom;

  /// Whether to draw the left side.
  final bool left;
}

/// Semantic options for drawing a terminal box.
final class BoxOptions {
  /// Creates box drawing options.
  const BoxOptions({
    this.sides = const BorderSides(),
    this.fill = false,
    this.title,
    this.titleAlignment = TextAlign.left,
    this.borderChars,
  });

  /// The sides to draw.
  final BorderSides sides;

  /// Whether to fill the box interior.
  final bool fill;

  /// Optional title drawn in the top border.
  final String? title;

  /// Horizontal alignment of [title].
  final TextAlign titleAlignment;

  /// Optional 11-code-point border glyph table.
  ///
  /// Entries are top-left, top-right, bottom-left, bottom-right, horizontal,
  /// vertical, top-T, bottom-T, left-T, right-T, and cross.
  final List<int>? borderChars;
}

/// Terminal cell attribute bit flags.
abstract final class Attr {
  /// Bold intensity.
  static const int bold = 1 << 0;

  /// Dim intensity.
  static const int dim = 1 << 1;

  /// Italic style.
  static const int italic = 1 << 2;

  /// Underline decoration.
  static const int underline = 1 << 3;

  /// Blink effect.
  static const int blink = 1 << 4;

  /// Reverse-video effect.
  static const int reverse = 1 << 5;

  /// Strikethrough decoration.
  static const int strike = 1 << 6;
}
