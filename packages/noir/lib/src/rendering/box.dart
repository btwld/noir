import '../render/geometry.dart';
import 'object.dart';

/// A render object that uses the box layout model.
///
/// RenderBox provides the foundation for rectangular layouts in terminal space.
/// It defines how constraints flow down and sizes flow up the tree.
abstract class RenderBox extends RenderObject {
  /// The size computed during layout
  Size? _size;

  /// The current size of this box, or Size.zero if not laid out
  Size get size => _size ?? Size.zero;

  /// Set the size of this box
  set size(Size value) {
    if (value.width < 0 || value.height < 0) {
      throw StateError(
        '$runtimeType produced an invalid negative size: $value.',
      );
    }
    _size = value;
    width = value.width;
    height = value.height;
  }

  /// Perform layout with box constraints
  ///
  /// This is the main layout entry point. Subclasses should override this
  /// to implement their specific layout behavior.
  @override
  void performLayout(Constraints constraints) {
    if (!constraints.isNormalized) {
      throw ArgumentError.value(
        constraints,
        'constraints',
        'must be normalized and non-negative',
      );
    }
    final boxConstraints = constraints is BoxConstraints
        ? constraints
        : BoxConstraints(
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.maxHeight,
          );

    if (!boxConstraints.isNormalized) {
      throw ArgumentError.value(
        constraints,
        'constraints',
        'must be normalized and non-negative',
      );
    }
    performBoxLayout(boxConstraints);
  }

  /// Perform layout with typed box constraints
  ///
  /// Subclasses override this instead of performLayout. The default
  /// implementation sizes to the maxima, treating an unbounded axis as
  /// the corresponding lower bound.
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(
      constraints.maxWidth ?? constraints.minWidth,
      constraints.maxHeight ?? constraints.minHeight,
    );
  }

  /// Default paint implementation.
  ///
  /// RenderBox paints no self-content; it forwards painting to its RenderBox
  /// children. Subclasses override to draw their own content.
  @override
  void paint(PaintingContext context, Offset offset) {
    visitChildren((child) {
      if (child is RenderBox) {
        context.paintChild(child, offset + Offset(x, y));
      }
    });
  }

  @override
  bool hitTest(HitTestResult result, Offset position) {
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx >= width ||
        position.dy >= height) {
      return false;
    }

    result.recordVisit(this);
    final childHit = hitTestChildren(result, position);
    final selfHit = hitTestSelf(position);
    if (selfHit) {
      result.add(HitTestEntry(this as HitTestTarget, position));
    }
    return childHit || selfHit;
  }

  /// Hit-test children in reverse paint order.
  ///
  /// [RenderObject.hitTest] is exactly that child walk (no bounds or self
  /// check), so the base implementation is reused directly.
  bool hitTestChildren(HitTestResult result, Offset position) =>
      super.hitTest(result, position);

  /// Whether this box should add itself to a hit-test path.
  bool hitTestSelf(Offset position) => false;

  /// Position a child within this box
  ///
  /// Helper method for laying out children.
  void positionChild(RenderBox child, int x, int y) {
    child.x = x;
    child.y = y;
  }
}
