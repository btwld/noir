import 'package:meta/meta.dart';

import '../core/color.dart';
import '../core/terminal_style.dart';
import '../render/geometry.dart';
import 'tui_canvas.dart';

/// The style of line to draw for a [Border].
enum BorderStyle {
  /// Skip the border.
  none,

  /// Draw the border as a solid line.
  solid,
}

/// Base class for box borders (like [Border]).
abstract class BoxBorder {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const BoxBorder();

  /// The widths of the sides of this border represented as an [EdgeInsets].
  ///
  /// This can be used, for example, with a [Padding] widget to inset a box by
  /// the size of these borders.
  EdgeInsets get dimensions;

  /// Paints the border within the given [Rect] on the given [TuiCanvas].
  void paint(TuiCanvas canvas, Rect rect);
}

/// A border drawn around a rectangular region of a terminal.
///
/// Terminal cells render a single character per position with a single
/// foreground colour, so unlike Flutter's [Border] this class does not model
/// per-side widths or colours. A [Border] has one [color], one [style], and a
/// [sides] mask that controls which of the four edges are drawn.
///
/// Border also exposes the OpenTUI extensions: optional [title] text along
/// the top edge, [fill] to paint the interior, and a custom [borderChars]
/// table for the Unicode characters used to draw the edges and corners.
@immutable
class Border extends BoxBorder {
  /// Creates a border that draws the sides described by [sides] in the given
  /// [color] and [style].
  const Border({
    this.color = Color.black,
    this.style = BorderStyle.solid,
    this.sides = const BorderSides(),
    this.title,
    this.titleAlignment = TextAlign.left,
    this.fill = false,
    this.borderChars,
  });

  /// All four sides on, with the given [color] and [style].
  const Border.all({
    Color color = Color.black,
    BorderStyle style = BorderStyle.solid,
    String? title,
    TextAlign titleAlignment = TextAlign.left,
    bool fill = false,
    List<int>? borderChars,
  }) : this(
         color: color,
         style: style,
         sides: const BorderSides(),
         title: title,
         titleAlignment: titleAlignment,
         fill: fill,
         borderChars: borderChars,
       );

  /// Creates a border with symmetrical vertical and horizontal sides.
  ///
  /// The [vertical] flag controls whether the left and right sides are drawn,
  /// while [horizontal] controls the top and bottom sides.
  Border.symmetric({
    bool vertical = true,
    bool horizontal = true,
    Color color = Color.black,
    BorderStyle style = BorderStyle.solid,
    String? title,
    TextAlign titleAlignment = TextAlign.left,
    bool fill = false,
    List<int>? borderChars,
  }) : this(
         color: color,
         style: style,
         sides: BorderSides(
           left: vertical,
           right: vertical,
           top: horizontal,
           bottom: horizontal,
         ),
         title: title,
         titleAlignment: titleAlignment,
         fill: fill,
         borderChars: borderChars,
       );

  /// The colour used to paint every visible side of the border.
  final Color color;

  /// The line style. When [BorderStyle.none] the border is not drawn.
  final BorderStyle style;

  /// Which of the four edges are drawn.
  final BorderSides sides;

  /// Optional title text to display along the top edge.
  ///
  /// Only takes effect when the top side is drawn.
  final String? title;

  /// How the title should be aligned along the top edge.
  ///
  /// Only takes effect when [title] is not null.
  final TextAlign titleAlignment;

  /// Whether to fill the interior of the box with [color].
  final bool fill;

  /// Custom Unicode characters to use for drawing the border.
  ///
  /// If provided, must contain exactly 11 code points in this order:
  /// `[topLeft, topRight, bottomLeft, bottomRight, horizontal, vertical,
  /// topT, bottomT, leftT, rightT, cross]`.
  ///
  /// Example for a double-line box:
  /// ```dart
  /// [0x2554, 0x2557, 0x255A, 0x255D, 0x2550, 0x2551,
  ///  0x2566, 0x2569, 0x2560, 0x2563, 0x256C]
  /// ```
  final List<int>? borderChars;

  @override
  EdgeInsets get dimensions {
    final draws = style != BorderStyle.none;
    return EdgeInsets(
      top: draws && sides.top ? 1 : 0,
      right: draws && sides.right ? 1 : 0,
      bottom: draws && sides.bottom ? 1 : 0,
      left: draws && sides.left ? 1 : 0,
    );
  }

  @override
  void paint(TuiCanvas canvas, Rect rect) {
    if (style == BorderStyle.none) return;
    if (!sides.top && !sides.right && !sides.bottom && !sides.left) return;

    final backgroundColor = fill ? color : Color.transparent;
    final options = BoxOptions(
      sides: sides,
      fill: fill,
      title: title,
      titleAlignment: titleAlignment,
      borderChars: borderChars,
    );

    canvas.drawBox(rect, options, color, backgroundColor);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is Border &&
        other.color == color &&
        other.style == style &&
        other.sides.top == sides.top &&
        other.sides.right == sides.right &&
        other.sides.bottom == sides.bottom &&
        other.sides.left == sides.left &&
        other.title == title &&
        other.titleAlignment == titleAlignment &&
        other.fill == fill &&
        _listEquals(other.borderChars, borderChars);
  }

  @override
  int get hashCode => Object.hash(
    color,
    style,
    sides.top,
    sides.right,
    sides.bottom,
    sides.left,
    title,
    titleAlignment,
    fill,
    borderChars == null ? null : Object.hashAll(borderChars!),
  );

  @override
  String toString() {
    if (style == BorderStyle.none) return 'Border(none)';
    final parts = <String>['color: $color'];
    if (!(sides.top && sides.right && sides.bottom && sides.left)) {
      parts.add(
        'sides: [${sides.top ? 'T' : '-'}${sides.right ? 'R' : '-'}${sides.bottom ? 'B' : '-'}${sides.left ? 'L' : '-'}]',
      );
    }
    if (title != null) parts.add('title: "$title"');
    if (fill) parts.add('fill');
    return 'Border(${parts.join(', ')})';
  }
}

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
