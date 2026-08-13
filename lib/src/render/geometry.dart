import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Rejects a negative viewport/content extent with the standard
/// `ArgumentError.value(value, name, 'must be non-negative')` shape.
///
/// Single owner of the widget-layer extent-domain rule shared by
/// `ViewportController`, `ScrollController`, `RenderTextArea`, and
/// `RenderSelect`. Internal — not exported from any barrel.
@internal
void requireNonNegativeExtent(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must be non-negative');
  }
}

/// The direction of a one-dimensional layout or viewport.
enum Axis {
  /// Lay content out left-to-right.
  horizontal,

  /// Lay content out top-to-bottom.
  vertical,
}

/// Layout constraints handed down from a parent to a child during the
/// constraint-down / size-up layout pass.
///
/// The terminal grid is integer-addressed: every cell is a fixed character
/// cell, so all constraint values are [int]. A `null` `maxWidth` or
/// `maxHeight` means **unbounded** — the child may pick any non-negative
/// size along that axis.
///
/// Equality is by value and exact runtime type, so subtypes carrying extra
/// state (such as [BoxConstraints]) never compare equal to their base type.
@immutable
class Constraints {
  /// Sets non-negative cell maxima; a `null` maximum leaves that axis unbounded.
  const Constraints({this.maxWidth, this.maxHeight})
    : assert(maxWidth == null || maxWidth >= 0),
      assert(maxHeight == null || maxHeight >= 0);

  /// Maximum width in cells, or `null` for unbounded.
  final int? maxWidth;

  /// Maximum height in cells, or `null` for unbounded.
  final int? maxHeight;

  /// Whether every finite maximum is non-negative.
  bool get isNormalized =>
      (maxWidth == null || maxWidth! >= 0) &&
      (maxHeight == null || maxHeight! >= 0);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Constraints &&
        other.runtimeType == runtimeType &&
        other.maxWidth == maxWidth &&
        other.maxHeight == maxHeight;
  }

  @override
  int get hashCode => Object.hash(runtimeType, maxWidth, maxHeight);
}

/// Box-shaped layout constraints with independent min/max on each axis.
///
/// A `null` `maxWidth` / `maxHeight` means the corresponding axis is
/// unbounded. `minWidth` / `minHeight` are always non-negative ints.
class BoxConstraints extends Constraints {
  /// Sets ordered cell bounds, with both minimums defaulting to zero.
  const BoxConstraints({
    super.maxWidth,
    super.maxHeight,
    this.minWidth = 0,
    this.minHeight = 0,
  }) : assert(minWidth >= 0),
       assert(minHeight >= 0),
       assert(maxWidth == null || maxWidth >= minWidth),
       assert(maxHeight == null || maxHeight >= minHeight);

  /// Constraints that force the child to exactly `(width, height)` cells.
  const BoxConstraints.tight({required int width, required int height})
    : assert(width >= 0),
      assert(height >= 0),
      minWidth = width,
      minHeight = height,
      super(maxWidth: width, maxHeight: height);

  /// Constraints with `min = 0` on both axes and the supplied maxima.
  const BoxConstraints.loose({super.maxWidth, super.maxHeight})
    : assert(maxWidth == null || maxWidth >= 0),
      assert(maxHeight == null || maxHeight >= 0),
      minWidth = 0,
      minHeight = 0;

  /// Tight constraints when both `width` and `height` are supplied;
  /// otherwise unbounded on the missing axis (`null` max).
  const BoxConstraints.expand({int? width, int? height})
    : assert(width == null || width >= 0),
      assert(height == null || height >= 0),
      minWidth = width ?? 0,
      minHeight = height ?? 0,
      super(maxWidth: width, maxHeight: height);

  /// Minimum permitted width in terminal character cells.
  final int minWidth;

  /// Minimum permitted height in terminal character cells.
  final int minHeight;

  /// Returns a new constraint with its maxima further narrowed by `width`
  /// / `height` if those are smaller than the existing maxima. `null`
  /// maxima are treated as unbounded and replaced by the supplied value.
  BoxConstraints constrain({int? width, int? height}) {
    _requireNonNegative(width, 'width');
    _requireNonNegative(height, 'height');
    return BoxConstraints(
      minWidth: minWidth,
      minHeight: minHeight,
      maxWidth: _narrowMaximum(minWidth, maxWidth, width),
      maxHeight: _narrowMaximum(minHeight, maxHeight, height),
    );
  }

  /// Shrink the constraints by the supplied insets.
  BoxConstraints deflate({int? width, int? height}) {
    final w = width ?? 0;
    final h = height ?? 0;
    _requireNonNegative(width, 'width');
    _requireNonNegative(height, 'height');
    final newMaxWidth = maxWidth == null ? null : math.max(0, maxWidth! - w);
    final newMaxHeight = maxHeight == null ? null : math.max(0, maxHeight! - h);
    return BoxConstraints(
      minWidth: newMaxWidth == null
          ? math.max(0, minWidth - w)
          : (minWidth - w).clamp(0, newMaxWidth),
      minHeight: newMaxHeight == null
          ? math.max(0, minHeight - h)
          : (minHeight - h).clamp(0, newMaxHeight),
      maxWidth: newMaxWidth,
      maxHeight: newMaxHeight,
    );
  }

  /// Returns constraints tightened to the supplied `width` / `height` on
  /// either axis, clamped to the current `[min, max]` range. `null` maxima
  /// are treated as unbounded.
  BoxConstraints tighten({int? width, int? height}) {
    _requireNonNegative(width, 'width');
    _requireNonNegative(height, 'height');
    final tightenedWidth = width == null
        ? null
        : (maxWidth == null
              ? math.max(minWidth, width)
              : width.clamp(minWidth, maxWidth!));
    final tightenedHeight = height == null
        ? null
        : (maxHeight == null
              ? math.max(minHeight, height)
              : height.clamp(minHeight, maxHeight!));
    return BoxConstraints(
      minWidth: tightenedWidth ?? minWidth,
      minHeight: tightenedHeight ?? minHeight,
      maxWidth: tightenedWidth ?? maxWidth,
      maxHeight: tightenedHeight ?? maxHeight,
    );
  }

  /// Returns `width` clamped to `[minWidth, maxWidth]`. When `maxWidth`
  /// is `null` (unbounded) only the lower bound is enforced.
  int constrainWidth(int width) {
    _requireNonNegative(width, 'width');
    return maxWidth == null
        ? math.max(minWidth, width)
        : width.clamp(minWidth, maxWidth!);
  }

  /// Returns `height` clamped to `[minHeight, maxHeight]`. When
  /// `maxHeight` is `null` (unbounded) only the lower bound is enforced.
  int constrainHeight(int height) {
    _requireNonNegative(height, 'height');
    return maxHeight == null
        ? math.max(minHeight, height)
        : height.clamp(minHeight, maxHeight!);
  }

  @override
  bool get isNormalized =>
      minWidth >= 0 &&
      minHeight >= 0 &&
      (maxWidth == null || maxWidth! >= minWidth) &&
      (maxHeight == null || maxHeight! >= minHeight);

  /// Internal: returns these constraints combined with [other]: each minimum
  /// is the larger of the two, each maximum the tighter of the two (`null`
  /// maxima are unbounded, so the non-null one wins when only one side
  /// specifies a limit), and each combined minimum is clamped to the combined
  /// maximum.
  ///
  /// This is a strictest-of-each-bound intersection and deliberately not
  /// Flutter's `enforce`, which clamps this box into the other's range.
  @internal
  BoxConstraints intersectWith(BoxConstraints other) {
    final combinedMinWidth = math.max(minWidth, other.minWidth);
    final combinedMaxWidth = _minNullable(maxWidth, other.maxWidth);
    final combinedMinHeight = math.max(minHeight, other.minHeight);
    final combinedMaxHeight = _minNullable(maxHeight, other.maxHeight);

    return BoxConstraints(
      minWidth: combinedMaxWidth == null
          ? combinedMinWidth
          : math.min(combinedMinWidth, combinedMaxWidth),
      maxWidth: combinedMaxWidth,
      minHeight: combinedMaxHeight == null
          ? combinedMinHeight
          : math.min(combinedMinHeight, combinedMaxHeight),
      maxHeight: combinedMaxHeight,
    );
  }

  /// True when both axes are tight (see [hasTightWidth] / [hasTightHeight]).
  bool get isTight => hasTightWidth && hasTightHeight;

  /// True when `maxWidth` is non-null and equal to `minWidth`.
  bool get hasTightWidth => maxWidth != null && minWidth == maxWidth;

  /// True when `maxHeight` is non-null and equal to `minHeight`.
  bool get hasTightHeight => maxHeight != null && minHeight == maxHeight;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BoxConstraints &&
        other.runtimeType == runtimeType &&
        other.minWidth == minWidth &&
        other.minHeight == minHeight &&
        other.maxWidth == maxWidth &&
        other.maxHeight == maxHeight;
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, minWidth, minHeight, maxWidth, maxHeight);

  static int? _minNullable(int? a, int? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a < b ? a : b;
  }

  static int? _narrowMaximum(int minimum, int? current, int? requested) {
    final narrowed = _minNullable(current, requested);
    return narrowed == null ? null : math.max(minimum, narrowed);
  }

  static void _requireNonNegative(int? value, String name) {
    if (value != null && value < 0) {
      throw ArgumentError.value(value, name, 'must be non-negative');
    }
  }
}

/// A 2D size in terminal character cells.
@immutable
class Size {
  /// Stores non-negative [width] and [height] extents in terminal cells.
  const Size(this.width, this.height) : assert(width >= 0), assert(height >= 0);

  /// Creates a square size with both dimensions equal to `dimension`.
  const Size.square(int dimension)
    : assert(dimension >= 0),
      width = dimension,
      height = dimension;

  /// Horizontal extent in terminal character cells.
  final int width;

  /// Vertical extent in terminal character cells.
  final int height;

  /// Canonical size with zero width and height.
  static const Size zero = Size(0, 0);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Size && other.width == width && other.height == height;
  }

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'Size($width, $height)';
}

/// A 2D offset in terminal character cells (integer-positioned).
///
/// Offsets can represent either a point relative to a separately-tracked
/// origin (e.g. a child's position inside its parent) or a vector that can
/// be added to other coordinates.
@immutable
class Offset {
  /// Stores an integer terminal-cell displacement of ([dx], [dy]).
  const Offset(this.dx, this.dy);

  /// An offset with zero magnitude.
  static const Offset zero = Offset(0, 0);

  /// The x component of the offset, in cells.
  final int dx;

  /// The y component of the offset, in cells.
  final int dy;

  /// Returns the offset difference between this point and [other].
  Offset operator -(Offset other) => Offset(dx - other.dx, dy - other.dy);

  /// Returns the offset sum of this point and [other].
  Offset operator +(Offset other) => Offset(dx + other.dx, dy + other.dy);

  /// Combine this offset and a [Size] to form a [Rect] whose top-left
  /// corner is at this point and whose extent is the given size.
  Rect operator &(Size other) =>
      Rect.fromLTWH(dx, dy, other.width, other.height);

  @override
  bool operator ==(Object other) =>
      other is Offset && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  String toString() => 'Offset($dx, $dy)';
}

/// An axis-aligned rectangle in terminal character cells (integer
/// positioned).
@immutable
class Rect {
  /// Construct a rectangle from its left, top, width, and height.
  const Rect.fromLTWH(this.left, this.top, this.width, this.height);

  /// Construct a rectangle from its left, top, right, and bottom edges.
  const Rect.fromLTRB(this.left, this.top, int right, int bottom)
    : width = right - left,
      height = bottom - top;

  /// A rectangle with all coordinates and dimensions zero.
  static const Rect zero = Rect.fromLTWH(0, 0, 0, 0);

  /// Inclusive left coordinate in terminal character cells.
  final int left;

  /// Inclusive top coordinate in terminal character cells.
  final int top;

  /// Horizontal extent in terminal character cells.
  final int width;

  /// Vertical extent in terminal character cells.
  final int height;

  /// Exclusive right edge, computed as [left] + [width].
  int get right => left + width;

  /// Exclusive bottom edge, computed as [top] + [height].
  int get bottom => top + height;

  /// Rectangle extent represented as a [Size].
  Size get size => Size(width, height);

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'Rect.fromLTWH($left, $top, $width, $height)';
}

/// Insets from each edge of a rectangle, in terminal character cells.
@immutable
class EdgeInsets {
  /// Creates insets with independent edges; each defaults to 0.
  const EdgeInsets({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  }) : assert(left >= 0),
       assert(top >= 0),
       assert(right >= 0),
       assert(bottom >= 0);

  /// Creates insets with the same value `v` on all four edges.
  const EdgeInsets.all(int v) : this(left: v, top: v, right: v, bottom: v);

  /// Creates insets with only the specified edges set; others default to 0.
  const EdgeInsets.only({
    int left = 0,
    int top = 0,
    int right = 0,
    int bottom = 0,
  }) : this(left: left, top: top, right: right, bottom: bottom);

  /// Creates insets where `vertical` sets top/bottom and `horizontal`
  /// sets left/right.
  const EdgeInsets.symmetric({int vertical = 0, int horizontal = 0})
    : this(
        left: horizontal,
        top: vertical,
        right: horizontal,
        bottom: vertical,
      );

  /// Non-negative left inset in terminal character cells.
  final int left;

  /// Non-negative top inset in terminal character cells.
  final int top;

  /// Non-negative right inset in terminal character cells.
  final int right;

  /// Non-negative bottom inset in terminal character cells.
  final int bottom;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EdgeInsets &&
        other.left == left &&
        other.top == top &&
        other.right == right &&
        other.bottom == bottom;
  }

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  /// Whether every dimension is non-negative.
  bool get isNonNegative => left >= 0 && top >= 0 && right >= 0 && bottom >= 0;

  /// An [EdgeInsets] with zero offsets in each direction.
  static const EdgeInsets zero = EdgeInsets.all(0);
}

/// An alignment within a rectangle, expressed as fractional coordinates in
/// `[-1, 1]` on each axis. `(-1, -1)` is the top-left corner, `(0, 0)` is
/// the center, `(1, 1)` is the bottom-right corner.
///
/// The fields are `double` because they're normalized weights, not cell
/// positions. Concrete pixel/cell offsets are computed by the layout code
/// using these weights against the available space.
@immutable
class Alignment {
  /// Stores horizontal and vertical fractional layout weights.
  const Alignment(this.x, this.y);

  /// Center alignment at normalized coordinate `(0, 0)`.
  static const Alignment center = Alignment(0, 0);

  /// Top-left alignment at normalized coordinate `(-1, -1)`.
  static const Alignment topLeft = Alignment(-1, -1);

  /// Top-center alignment at normalized coordinate `(0, -1)`.
  static const Alignment topCenter = Alignment(0, -1);

  /// Top-right alignment at normalized coordinate `(1, -1)`.
  static const Alignment topRight = Alignment(1, -1);

  /// Center-left alignment at normalized coordinate `(-1, 0)`.
  static const Alignment centerLeft = Alignment(-1, 0);

  /// Center-right alignment at normalized coordinate `(1, 0)`.
  static const Alignment centerRight = Alignment(1, 0);

  /// Bottom-left alignment at normalized coordinate `(-1, 1)`.
  static const Alignment bottomLeft = Alignment(-1, 1);

  /// Bottom-center alignment at normalized coordinate `(0, 1)`.
  static const Alignment bottomCenter = Alignment(0, 1);

  /// Bottom-right alignment at normalized coordinate `(1, 1)`.
  static const Alignment bottomRight = Alignment(1, 1);

  /// Horizontal weight where -1, 0, and 1 mean left, center, and right.
  final double x;

  /// Vertical weight where -1, 0, and 1 mean top, center, and bottom.
  final double y;

  @override
  bool operator ==(Object other) =>
      other is Alignment && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Alignment($x, $y)';
}

/// The shape used when rendering a [BoxDecoration].
enum BoxShape {
  /// An axis-aligned rectangle.
  rectangle,

  /// A circle inscribed in the box.
  circle,
}
