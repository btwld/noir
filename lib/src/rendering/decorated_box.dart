import '../painting/decoration.dart';
import '../render/geometry.dart';
import '../widgets/decorated_box.dart';
import 'box.dart';
import 'object.dart';

/// A render object that paints a [Decoration].
///
/// RenderDecoratedBox paints a decoration either before or after its child paints.
class RenderDecoratedBox extends RenderBox with RenderObjectWithSingleChild {
  /// Stores the decoration and paint position, adopting [child] when given.
  RenderDecoratedBox({
    required Decoration decoration,
    DecorationPosition position = DecorationPosition.background,
    RenderBox? child,
  }) : _decoration = decoration,
       _position = position {
    setSingleRenderObjectChild(this, child);
  }

  /// The decoration to paint.
  Decoration get decoration => _decoration;
  Decoration _decoration;
  set decoration(Decoration value) {
    if (_decoration == value) return;
    _decoration = value;
    markNeedsPaint();
  }

  /// Whether to paint the decoration behind or in front of the child.
  DecorationPosition get position => _position;
  DecorationPosition _position;
  set position(DecorationPosition value) {
    if (_position == value) return;
    _position = value;
    markNeedsPaint();
  }

  @override
  RenderBox? get child => super.child as RenderBox?;

  /// Set the child render object. Idempotent: passing the current child or
  /// one already adopted as this object's child is a no-op.
  @override
  void setChild(RenderObject? newChild) {
    if (newChild != null && newChild is! RenderBox) {
      throw ArgumentError(
        'RenderDecoratedBox children must be RenderBox, '
        'got ${newChild.runtimeType}',
      );
    }
    setSingleRenderObjectChild(this, newChild);
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child != null) {
      child.layout(constraints);

      positionChild(child, 0, 0);

      size = Size(
        constraints.constrainWidth(child.width),
        constraints.constrainHeight(child.height),
      );
    } else {
      size = Size(
        constraints.constrainWidth(0),
        constraints.constrainHeight(0),
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = offset + Offset(x, y);
    final child = this.child;

    // Decoration rect is in integer cell coordinates.
    final rect = Rect.fromLTWH(origin.dx, origin.dy, width, height);

    if (_position == DecorationPosition.background) {
      _decoration.paint(context.canvas, rect);

      if (child != null) {
        context.paintChild(child, origin);
      }
    } else {
      if (child != null) {
        context.paintChild(child, origin);
      }

      _decoration.paint(context.canvas, rect);
    }
  }
}
