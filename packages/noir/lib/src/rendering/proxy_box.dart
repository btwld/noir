import '../render/geometry.dart';
import 'box.dart';
import 'object.dart';

/// A render object that forwards layout and paint to a single child.
class RenderProxyBox extends RenderBox with RenderObjectWithSingleChild {
  /// Adopts [child] through the authoritative single-render-child edge.
  RenderProxyBox([RenderBox? child]) {
    setSingleRenderObjectChild(this, child);
  }

  /// The single render child, or `null` when there is none.
  @override
  RenderBox? get child => super.child as RenderBox?;

  /// Replaces the child, dropping the old one and adopting the new one.
  ///
  /// The complete replacement is validated before either edge changes.
  ///
  /// Passing the current child is a no-op.
  set child(RenderBox? value) {
    setSingleRenderObjectChild(this, value);
  }

  @override
  void setChild(RenderObject? child) {
    if (child != null && child is! RenderBox) {
      throw ArgumentError(
        'RenderProxyBox children must be RenderBox, got ${child.runtimeType}',
      );
    }
    setSingleRenderObjectChild(this, child);
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) {
      size = Size(constraints.minWidth, constraints.minHeight);
      return;
    }

    child.layout(constraints);
    size = Size(child.size.width, child.size.height);
    child.x = 0;
    child.y = 0;
  }
}
