import 'package:meta/meta.dart';

import '../core/color.dart';
import '../render/geometry.dart';
import 'box_border.dart';
import 'decoration.dart';
import 'tui_canvas.dart';

/// An immutable description of how to paint a box.
///
/// The [BoxDecoration] class provides a variety of ways to draw a box.
///
/// The box has a [border] and a body.
///
/// The [shape] of the box can be a circle or a rectangle.
///
/// The body of the box is painted with the [color]. In the terminal,
/// [color] only fills [BoxShape.rectangle] bodies; [BoxShape.circle] paints
/// no body fill (it affects hit testing and the border only).
///
/// The [border] paints over the body.
@immutable
class BoxDecoration extends Decoration {
  /// Creates a box decoration.
  ///
  /// * If [color] is null, then no background will be painted.
  /// * If [border] is null, then no border will be painted.
  const BoxDecoration({
    this.color,
    this.border,
    this.shape = BoxShape.rectangle,
  });

  /// The color to fill in the background of the box.
  ///
  /// In the terminal the fill is only painted for [BoxShape.rectangle];
  /// [BoxShape.circle] paints no body fill.
  ///
  /// The [color] is drawn under the [border].
  final Color? color;

  /// A border to draw above the background [color].
  ///
  /// Follows the [shape].
  ///
  /// Use [Border] objects to describe borders that do not depend on the reading
  /// direction.
  final BoxBorder? border;

  /// The shape to fill the background [color] into.
  ///
  /// The [border] will be drawn on top of the shape, not within it.
  final BoxShape shape;

  @override
  EdgeInsets? get padding => border?.dimensions;

  @override
  void paint(TuiCanvas canvas, Rect rect) {
    if (color != null && shape == BoxShape.rectangle) {
      canvas.fillRect(rect, color!);
    }

    if (border != null) {
      border!.paint(canvas, rect);
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is BoxDecoration &&
        other.color == color &&
        other.border == border &&
        other.shape == shape;
  }

  @override
  int get hashCode => Object.hash(color, border, shape);

  @override
  String toString() {
    final description = <String>[];
    if (color != null) description.add('color: $color');
    if (border != null) description.add('border: $border');
    if (shape != BoxShape.rectangle) description.add('shape: $shape');
    return 'BoxDecoration(${description.join(', ')})';
  }
}
