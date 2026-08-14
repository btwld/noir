import '../render/geometry.dart';
import 'box.dart';
import 'object.dart';

/// A render object that positions its child within the available space according to an alignment.
///
/// This is the render object used by Align widgets to position their children
/// without relying on Container widgets, avoiding circular dependencies.
class RenderPositionedBox extends RenderBox with RenderObjectWithSingleChild {
  /// Stores the alignment and adopts [child] when given.
  RenderPositionedBox({required Alignment alignment, RenderBox? child})
    : _alignment = alignment {
    setSingleRenderObjectChild(this, child);
  }

  Alignment _alignment;

  /// Placement of the child within the leftover space, from (-1, -1)
  /// top-left through (0, 0) center to (1, 1) bottom-right.
  Alignment get alignment => _alignment;

  set alignment(Alignment value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  @override
  RenderBox? get child => super.child as RenderBox?;

  /// Set the child render object. Idempotent: passing the current child or
  /// one already adopted as this object's child is a no-op.
  @override
  void setChild(RenderObject? newChild) {
    if (newChild != null && newChild is! RenderBox) {
      throw ArgumentError(
        'RenderPositionedBox children must be RenderBox, '
        'got ${newChild.runtimeType}',
      );
    }
    setSingleRenderObjectChild(this, newChild);
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final child = this.child;

    if (child == null) {
      super.performBoxLayout(constraints);
      return;
    }

    // Align fills bounded axes but lets its child choose a natural size within
    // those bounds, leaving an extent for the requested alignment to position.
    child.layout(
      BoxConstraints.loose(
        maxWidth: constraints.maxWidth,
        maxHeight: constraints.maxHeight,
      ),
    );
    final selfWidth =
        constraints.maxWidth ?? constraints.constrainWidth(child.width);
    final selfHeight =
        constraints.maxHeight ?? constraints.constrainHeight(child.height);
    size = Size(selfWidth, selfHeight);

    final childSize = child.size;
    final availableWidth = size.width - childSize.width;
    final availableHeight = size.height - childSize.height;

    final offsetX = ((alignment.x + 1) * availableWidth / 2).round();
    final offsetY = ((alignment.y + 1) * availableHeight / 2).round();

    positionChild(child, offsetX, offsetY);
  }
}
