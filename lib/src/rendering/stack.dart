import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../render/geometry.dart';
import 'box.dart';
import 'object.dart';

/// How non-positioned children are constrained by a [RenderStack].
enum StackFit {
  /// Children may choose any size up to the stack's available extent.
  loose,

  /// Children are forced to fill the stack's available extent.
  expand,
}

/// Absolute positioning metadata for one stack child.
@immutable
final class StackChildData {
  /// Creates positioning metadata in whole terminal cells.
  const StackChildData({
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
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

  /// Whether this child participates in absolute positioning.
  bool get isPositioned =>
      left != null ||
      top != null ||
      right != null ||
      bottom != null ||
      width != null ||
      height != null;

  @override
  bool operator ==(Object other) =>
      other is StackChildData &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, right, bottom, width, height);
}

/// A render box that overlays children in document order.
final class RenderStack extends RenderBox {
  /// Overlays [children] using whole-cell positioning and optional clipping.
  RenderStack({
    StackFit fit = StackFit.loose,
    Alignment alignment = Alignment.topLeft,
    bool clip = true,
    List<RenderBox>? children,
  }) : _fit = fit,
       _alignment = alignment,
       _clip = clip {
    if (children != null) {
      for (final child in children) {
        add(child);
      }
    }
  }

  final Map<RenderBox, StackChildData> _childData =
      Map<RenderBox, StackChildData>.identity();
  StackFit _fit;
  Alignment _alignment;
  bool _clip;

  /// How non-positioned children are constrained.
  StackFit get fit => _fit;
  set fit(StackFit value) {
    if (_fit == value) return;
    _fit = value;
    markNeedsLayout();
  }

  /// Alignment for non-positioned and partially positioned children.
  Alignment get alignment => _alignment;
  set alignment(Alignment value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  /// Whether painting is clipped to the stack bounds.
  bool get clip => _clip;
  set clip(bool value) {
    if (_clip == value) return;
    _clip = value;
    markNeedsPaint();
  }

  /// Adds or updates a child and its positioning [data].
  void add(RenderBox child, {StackChildData data = const StackChildData()}) {
    _validateData(data);
    if (identical(child.parent, this)) {
      if (_childData[child] != data) {
        _childData[child] = data;
        markNeedsLayout();
      }
      return;
    }
    adoptChild(child);
    _childData[child] = data;
  }

  /// Removes a child.
  void remove(RenderBox child) {
    if (!identical(child.parent, this)) return;
    dropChild(child);
    _childData.remove(child);
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final boxes = children.whereType<RenderBox>().toList(growable: false);
    var naturalWidth = 0;
    var naturalHeight = 0;
    var hasNonPositionedChild = false;
    final loose = BoxConstraints.loose(
      maxWidth: constraints.maxWidth,
      maxHeight: constraints.maxHeight,
    );

    for (final child in boxes) {
      final data = _childData[child] ?? const StackChildData();
      if (data.isPositioned) continue;
      hasNonPositionedChild = true;
      final childConstraints = _fit == StackFit.expand
          ? BoxConstraints.expand(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
            )
          : loose;
      child.layout(childConstraints);
      if (child.size.width > naturalWidth) naturalWidth = child.size.width;
      if (child.size.height > naturalHeight) naturalHeight = child.size.height;
    }

    final fillAvailable = _fit == StackFit.expand || !hasNonPositionedChild;
    size = Size(
      constraints.constrainWidth(
        fillAvailable ? constraints.maxWidth ?? naturalWidth : naturalWidth,
      ),
      constraints.constrainHeight(
        fillAvailable ? constraints.maxHeight ?? naturalHeight : naturalHeight,
      ),
    );

    for (final child in boxes) {
      final data = _childData[child] ?? const StackChildData();
      if (!data.isPositioned) {
        final offset = _alignedOffset(
          _alignment,
          Offset(
            size.width - child.size.width,
            size.height - child.size.height,
          ),
        );
        positionChild(child, offset.dx, offset.dy);
        continue;
      }

      final availableWidth = math.max(
        0,
        size.width - (data.left ?? 0) - (data.right ?? 0),
      );
      final availableHeight = math.max(
        0,
        size.height - (data.top ?? 0) - (data.bottom ?? 0),
      );
      final forcedWidth =
          data.width ??
          (data.left != null && data.right != null ? availableWidth : null);
      final forcedHeight =
          data.height ??
          (data.top != null && data.bottom != null ? availableHeight : null);
      child.layout(
        BoxConstraints(
          minWidth: forcedWidth ?? 0,
          maxWidth: forcedWidth ?? availableWidth,
          minHeight: forcedHeight ?? 0,
          maxHeight: forcedHeight ?? availableHeight,
        ),
      );
      final aligned = _alignedOffset(
        _alignment,
        Offset(size.width - child.size.width, size.height - child.size.height),
      );
      final x =
          data.left ??
          (data.right == null
              ? aligned.dx
              : size.width - data.right! - child.size.width);
      final y =
          data.top ??
          (data.bottom == null
              ? aligned.dy
              : size.height - data.bottom! - child.size.height);
      positionChild(child, x, y);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_clip) {
      super.paint(context, offset);
      return;
    }
    context.canvas.save();
    try {
      context.canvas.clipRect(
        Rect.fromLTWH(offset.dx + x, offset.dy + y, size.width, size.height),
      );
      super.paint(context, offset);
    } finally {
      context.canvas.restore();
    }
  }
}

Offset _alignedOffset(Alignment alignment, Offset slack) => Offset(
  ((alignment.x + 1) * slack.dx / 2).floor(),
  ((alignment.y + 1) * slack.dy / 2).floor(),
);

void _validateData(StackChildData data) {
  if ((data.width ?? 0) < 0 || (data.height ?? 0) < 0) {
    throw ArgumentError.value(data, 'data', 'dimensions must be non-negative');
  }
  if (data.left != null && data.right != null && data.width != null) {
    throw ArgumentError('left, right, and width cannot all be supplied');
  }
  if (data.top != null && data.bottom != null && data.height != null) {
    throw ArgumentError('top, bottom, and height cannot all be supplied');
  }
}
