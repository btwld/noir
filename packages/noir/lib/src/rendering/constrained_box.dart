import '../render/geometry.dart';
import 'box.dart';
import 'object.dart';

/// A render object that enforces additional constraints on its child.
///
/// Uses BoxConstraints to apply min/max width and height constraints to its child.
/// This is the render object for ConstrainedBox widgets.
class RenderConstrainedBox extends RenderBox with RenderObjectWithSingleChild {
  /// Validates that the extra constraints are normalized and adopts [child]
  /// when given.
  RenderConstrainedBox({
    required BoxConstraints additionalConstraints,
    RenderBox? child,
  }) : _additionalConstraints = _validateConstraints(additionalConstraints) {
    setSingleRenderObjectChild(this, child);
  }

  BoxConstraints _additionalConstraints;

  /// Constraints intersected with the incoming constraints during layout.
  BoxConstraints get additionalConstraints => _additionalConstraints;

  set additionalConstraints(BoxConstraints value) {
    _validateConstraints(value);
    if (_additionalConstraints == value) return;
    _additionalConstraints = value;
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
        'RenderConstrainedBox children must be RenderBox, '
        'got ${newChild.runtimeType}',
      );
    }
    setSingleRenderObjectChild(this, newChild);
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child != null) {
      child.layout(constraints.intersectWith(_additionalConstraints));

      positionChild(child, 0, 0);

      size = child.size;
    } else {
      final constrainedSize = Size(
        _additionalConstraints.constrainWidth(0),
        _additionalConstraints.constrainHeight(0),
      );
      size = Size(
        constraints.constrainWidth(constrainedSize.width),
        constraints.constrainHeight(constrainedSize.height),
      );
    }
  }

  static BoxConstraints _validateConstraints(BoxConstraints value) {
    if (!value.isNormalized) {
      throw ArgumentError.value(
        value,
        'additionalConstraints',
        'must be normalized and non-negative',
      );
    }
    return value;
  }
}
