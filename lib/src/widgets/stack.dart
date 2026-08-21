import 'package:meta/meta.dart';

import '../framework/build_context.dart';
import '../framework/element.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/box.dart';
import '../rendering/object.dart';
import '../rendering/stack.dart';

/// Overlays children in document order.
///
/// With only positioned children, bounded axes fill their available extent and
/// unbounded axes derive a finite extent from child sizes and edge offsets.
/// Negative offsets may still overflow that extent and are clipped by default.
class Stack extends MultiChildRenderObjectWidget {
  /// Creates a stack with hard-edge clipping by default.
  const Stack({
    super.key,
    super.children,
    this.fit = StackFit.loose,
    this.alignment = Alignment.topLeft,
    this.clip = true,
  });

  /// How non-positioned children are constrained.
  final StackFit fit;

  /// Placement of non-positioned and partially positioned children.
  final Alignment alignment;

  /// Whether descendants are clipped to the stack bounds.
  final bool clip;

  @override
  @internal
  RenderStack createRenderObject(BuildContext context) =>
      RenderStack(fit: fit, alignment: alignment, clip: clip);

  @override
  @internal
  void updateRenderObject(BuildContext context, RenderStack renderObject) {
    renderObject
      ..fit = fit
      ..alignment = alignment
      ..clip = clip;
  }

  @override
  @internal
  MultiChildRenderObjectElement createElement() => _StackElement(this);
}

/// Positions one child relative to the edges of its nearest [Stack].
class Positioned extends ProxyWidget {
  /// Creates an absolutely positioned stack child.
  const Positioned({
    required super.child,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
    super.key,
  }) : assert(width == null || width >= 0),
       assert(height == null || height >= 0),
       assert(left == null || right == null || width == null),
       assert(top == null || bottom == null || height == null);

  /// Distance from the stack's left edge.
  final int? left;

  /// Distance from the stack's top edge.
  final int? top;

  /// Distance from the stack's right edge.
  final int? right;

  /// Distance from the stack's bottom edge.
  final int? bottom;

  /// Explicit child width.
  final int? width;

  /// Explicit child height.
  final int? height;

  StackChildData get _data => StackChildData(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    width: width,
    height: height,
  );

  @override
  @internal
  Element createElement() => _PositionedElement(this);
}

final class _PositionedElement extends ProxyElement {
  _PositionedElement(Positioned super.widget);

  StackChildData get data => (widget as Positioned)._data;
}

final class _StackElement extends MultiChildRenderObjectElement {
  _StackElement(super.widget);

  @override
  void adoptChildRenderObject(RenderBox child, Element childElement, int slot) {
    final stack = renderObject! as RenderStack;
    final data = childElement is _PositionedElement
        ? childElement.data
        : const StackChildData();
    stack.add(child, data: data);
  }

  @override
  void dropChildRenderObject(RenderObject child, Element? childElement) {
    final stack = renderObject as RenderStack?;
    if (stack == null || child is! RenderBox) return;
    stack.remove(child);
  }
}
