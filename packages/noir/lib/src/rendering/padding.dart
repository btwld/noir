import '../render/geometry.dart';
import 'box.dart';
import 'object.dart';

/// A render object that applies padding to its child.
///
/// Uses the existing BoxConstraints.deflate() infrastructure to reduce
/// available space for the child and positions it with the padding offset.
class RenderPadding extends RenderBox with RenderObjectWithSingleChild {
  /// Validates that [padding] is non-negative and adopts [child] when given.
  RenderPadding({required EdgeInsets padding, RenderBox? child})
    : _padding = _validatePadding(padding) {
    setSingleRenderObjectChild(this, child);
  }

  EdgeInsets _padding;

  /// Non-negative insets reserved around the child.
  EdgeInsets get padding => _padding;

  set padding(EdgeInsets value) {
    _validatePadding(value);
    if (_padding == value) return;
    _padding = value;
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
        'RenderPadding children must be RenderBox, '
        'got ${newChild.runtimeType}',
      );
    }
    setSingleRenderObjectChild(this, newChild);
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child != null) {
      final childConstraints = constraints.deflate(
        width: _padding.left + _padding.right,
        height: _padding.top + _padding.bottom,
      );

      child.layout(childConstraints);

      positionChild(child, _padding.left, _padding.top);

      size = Size(
        constraints.constrainWidth(
          child.width + _padding.left + _padding.right,
        ),
        constraints.constrainHeight(
          child.height + _padding.top + _padding.bottom,
        ),
      );
    } else {
      size = Size(
        constraints.constrainWidth(_padding.left + _padding.right),
        constraints.constrainHeight(_padding.top + _padding.bottom),
      );
    }
  }

  static EdgeInsets _validatePadding(EdgeInsets value) {
    if (!value.isNonNegative) {
      throw ArgumentError.value(
        value,
        'padding',
        'must have non-negative edges',
      );
    }
    return value;
  }
}
