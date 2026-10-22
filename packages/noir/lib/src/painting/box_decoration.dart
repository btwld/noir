import 'package:meta/meta.dart';

import '../core/color.dart';
import '../render/geometry.dart';
import 'box_border.dart';
import 'decoration.dart';
import 'tui_canvas.dart';

/// An immutable description of how to paint a box.
///
/// The body of the box is painted with the [color].
///
/// The [border] paints over the body.
@immutable
class BoxDecoration extends Decoration {
  /// Creates a box decoration.
  ///
  /// * If [color] is null, then no background will be painted.
  /// * If [border] is null, then no border will be painted.
  const BoxDecoration({this.color, this.border});

  /// The color to fill in the background of the box.
  ///
  /// The [color] is drawn under the [border].
  final Color? color;

  /// A border to draw above the background [color].
  ///
  /// Use [Border] objects to describe borders that do not depend on the reading
  /// direction.
  final BoxBorder? border;

  @override
  EdgeInsets? get padding => border?.dimensions;

  @override
  void paint(TuiCanvas canvas, Rect rect) {
    if (color != null) {
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
        other.border == border;
  }

  @override
  int get hashCode => Object.hash(color, border);

  @override
  String toString() {
    final description = <String>[];
    if (color != null) description.add('color: $color');
    if (border != null) description.add('border: $border');
    return 'BoxDecoration(${description.join(', ')})';
  }
}
