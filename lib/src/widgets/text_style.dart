import '../core/color.dart';
import '../core/terminal_style.dart';

/// An immutable style describing how to format and paint text.
///
/// This class follows Flutter's TextStyle API but only exposes properties
/// that are supported by OpenTUI for terminal text rendering.
class TextStyle {
  /// Creates a text style.
  ///
  /// All parameters are optional and will use sensible defaults.
  const TextStyle({
    this.color = Color.white,
    this.backgroundColor,
    this.fontWeight,
    this.fontStyle,
    this.decoration,
    this.effect,
    int? attributes,
  }) : attributes = attributes ?? 0;

  /// The color of the text.
  final Color color;

  /// The color to use as the background for the text.
  final Color? backgroundColor;

  /// The typeface thickness to use when painting the text (e.g., bold).
  final FontWeight? fontWeight;

  /// The typeface variant to use when drawing the letters (e.g., italics).
  final FontStyle? fontStyle;

  /// Text decorations such as underline or line-through.
  final List<TextDecoration>? decoration;

  /// Terminal-specific text effects (blink, reverse video).
  ///
  /// These effects are not available in Flutter but work in terminal
  /// environments. Use for terminal-specific UI highlighting.
  final TextEffect? effect;

  /// Raw OpenTUI attribute bits merged into [computedAttributes].
  ///
  /// The chainable helpers ([bold], [italic], [underline], ...) and the
  /// [TextStyles] presets set this directly; that route is the supported
  /// shorthand for [fontWeight], [fontStyle], [decoration], and [effect].
  final int attributes;

  /// A computed property that converts Flutter-style properties to OpenTUI attributes.
  int get computedAttributes {
    var attrs = attributes;

    // Handle font weight mapping to OpenTUI attributes
    switch (fontWeight) {
      case FontWeight.bold:
        attrs |= Attr.bold;
      case FontWeight.dim:
        attrs |= Attr.dim;
      case FontWeight.normal:
      case null:
        // No additional attributes for normal weight
        break;
    }

    if (fontStyle == FontStyle.italic) {
      attrs |= Attr.italic;
    }

    if (decoration != null) {
      for (final dec in decoration!) {
        switch (dec) {
          case TextDecoration.none:
            // No decoration, do nothing
            break;
          case TextDecoration.underline:
            attrs |= Attr.underline;
          case TextDecoration.lineThrough:
            attrs |= Attr.strike;
        }
      }
    }

    // Handle terminal-specific effects
    switch (effect) {
      case TextEffect.blink:
        attrs |= Attr.blink;
      case TextEffect.reverse:
        attrs |= Attr.reverse;
      case TextEffect.none:
      case null:
        // No additional effects
        break;
    }

    return attrs;
  }

  /// Copy with different properties
  TextStyle copyWith({
    Color? color,
    Color? backgroundColor,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    List<TextDecoration>? decoration,
    TextEffect? effect,
    int? attributes,
  }) => TextStyle(
    color: color ?? this.color,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    fontWeight: fontWeight ?? this.fontWeight,
    fontStyle: fontStyle ?? this.fontStyle,
    decoration: decoration ?? this.decoration,
    effect: effect ?? this.effect,
    attributes: attributes ?? this.attributes,
  );

  /// Create bold text style
  TextStyle bold() => copyWith(attributes: attributes | Attr.bold);

  /// Create italic text style
  TextStyle italic() => copyWith(attributes: attributes | Attr.italic);

  /// Create underlined text style
  TextStyle underline() => copyWith(attributes: attributes | Attr.underline);

  /// Create dimmed text style
  TextStyle dim() => copyWith(attributes: attributes | Attr.dim);

  /// Create blinking text style
  TextStyle blink() => copyWith(attributes: attributes | Attr.blink);

  /// Create reversed text style (swap fg/bg)
  TextStyle reverse() => copyWith(attributes: attributes | Attr.reverse);

  /// Create strikethrough text style
  TextStyle strikethrough() => copyWith(attributes: attributes | Attr.strike);
}

/// Pre-defined text styles for common use cases
class TextStyles {
  // Basic styles
  /// Default text style with no added terminal attributes.
  static const normal = TextStyle();

  /// Text with the terminal bold attribute.
  static const bold = TextStyle(attributes: Attr.bold);

  /// Text with the terminal italic attribute.
  static const italic = TextStyle(attributes: Attr.italic);

  /// Text with the terminal underline attribute.
  static const underline = TextStyle(attributes: Attr.underline);

  /// Text with the terminal dim attribute.
  static const dim = TextStyle(attributes: Attr.dim);

  // Common color combinations
  /// Error preset with a red foreground.
  static const error = TextStyle(color: Color.red);

  /// Warning preset with a yellow foreground.
  static const warning = TextStyle(color: Color.yellow);

  /// Success preset with a green foreground.
  static const success = TextStyle(color: Color.green);

  /// Informational preset with normalized RGB `(0, 0.7, 1)`.
  static const info = TextStyle(color: Color(0, 0.7, 1)); // Blue
  /// Muted preset with a gray foreground.
  static const muted = TextStyle(color: Color.gray);

  // Highlighted styles
  /// Highlight preset with black text on a yellow background.
  static const highlight = TextStyle(
    color: Color.black,
    backgroundColor: Color.yellow,
  );

  /// Selection preset with normalized RGB `(0, 0, 0.8)` as its background.
  static const selection = TextStyle(backgroundColor: Color(0, 0, 0.8));

  // Header styles
  /// First-level heading preset using bold text.
  static const h1 = TextStyle(attributes: Attr.bold);

  /// Second-level heading preset using bold, underlined, light text.
  static const h2 = TextStyle(
    attributes: Attr.bold | Attr.underline,
    color: Color(0.9, 0.9, 0.9),
  );

  /// Third-level heading preset using bold light-gray text.
  static const h3 = TextStyle(attributes: Attr.bold, color: Color.lightGray);

  // Special styles
  /// Code preset with light text on a dark background.
  static const code = TextStyle(
    color: Color(0.9, 0.9, 0.9),
    backgroundColor: Color(0.1, 0.1, 0.1),
  );

  /// Link preset with blue, underlined text.
  static const link = TextStyle(
    color: Color(0.3, 0.7, 1),
    attributes: Attr.underline,
  );
}

/// The thickness of the glyphs used to draw text.
///
/// **Terminal-Only Font Weights**: Unlike Flutter which supports 9 numeric weights
/// (w100-w900), terminals can only render 3 distinct text weights. This enum
/// only exposes what OpenTUI can actually render.
///
/// Flutter compatibility note: w100-w900 removed because terminal emulators
/// lack font weight granularity. They typically support only normal/bold/dim.
enum FontWeight {
  /// Normal text weight - no special attributes applied.
  /// Maps to: No OpenTUI attributes (0)
  normal,

  /// Bold text weight - heavier than normal.
  /// Maps to: OpenTUI Attr.bold (1 << 0)
  bold,

  /// Dimmed text weight - lighter than normal, terminal-specific feature.
  /// Maps to: OpenTUI Attr.dim (1 << 1)
  /// Note: This is a terminal enhancement not available in Flutter
  dim,
}

/// Whether to slant the glyphs in the font.
///
/// Flutter-compatible font style enumeration for terminal text rendering.
enum FontStyle {
  /// Use the upright glyphs
  normal,

  /// Use glyphs designed for slanting
  italic,
}

/// A linear decoration to draw near the text.
///
/// **Terminal-Only Text Decorations**: Unlike Flutter which supports overline,
/// terminals cannot render text decorations above the text line due to fixed
/// character cell positioning.
///
/// Flutter compatibility note: overline removed because terminal character cells
/// have fixed height with no space above text for overline rendering.
enum TextDecoration {
  /// Do not draw a decoration
  /// Maps to: No OpenTUI attributes (0)
  none,

  /// Draw a line underneath each line of text
  /// Maps to: OpenTUI Attr.underline (1 << 3)
  underline,

  /// Draw a line through each line of text (strikethrough)
  /// Maps to: OpenTUI Attr.strike (1 << 6)
  lineThrough,

  // overline removed - terminals cannot render above text line
  // Use backgroundColor or reverse video for emphasis instead
}

/// Terminal-specific text effects not available in Flutter.
///
/// These effects leverage terminal-specific capabilities that are not part
/// of standard GUI text rendering. Use these for terminal-specific UI elements
/// like highlighting, alerts, or drawing attention.
enum TextEffect {
  /// No special effect applied
  /// Maps to: No OpenTUI attributes (0)
  none,

  /// Text blinks/flashes periodically (if terminal supports it)
  /// Maps to: OpenTUI Attr.blink (1 << 4)
  /// Note: Some modern terminals disable blinking for accessibility
  blink,

  /// Swap foreground and background colors (reverse video)
  /// Maps to: OpenTUI Attr.reverse (1 << 5)
  /// Useful for selection highlighting and emphasized text
  reverse,
}
