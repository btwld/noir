import 'dart:math' as math;

import '../core/color.dart';
import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../painting/box_decoration.dart';
import '../render/geometry.dart';
import 'align.dart';
import 'constrained_box.dart';
import 'decorated_box.dart';
import 'padding.dart';
import 'sized_box.dart';

/// A convenience widget that combines common painting, positioning, and sizing
/// widgets.
///
/// A container first surrounds the child with [padding] (inflated by any
/// borders present in the [decoration]) and then applies [width] and [height]
/// sizing to the padded extent. The container is then surrounded by
/// additional empty space described from the [margin].
///
/// During painting, the container paints the [decoration] to fill the padded
/// extent, then it paints the child, and finally paints the [foregroundDecoration],
/// also filling the padded extent.
///
/// Containers with no children try to be as small as possible within terminal
/// constraints. Containers with children size themselves to their children. The
/// [width] and [height] arguments to the constructor override this.
///
/// Flutter compatibility note: transform, transformAlignment, and clipBehavior
/// are removed — terminal cells cannot rotate, skew, or clip to custom shapes.
///
/// Flutter compatibility note: [constraints] is retained; [width] and [height]
/// tighten it to exact cell values, matching Flutter's precedence rule.
class Container extends StatelessWidget {
  /// Creates a widget that combines common painting, positioning, and sizing widgets.
  ///
  /// The [height] and [width] values include the padding.
  ///
  /// The [color] and [decoration] arguments cannot both be supplied, since
  /// it would potentially result in the decoration drawing over the background
  /// color. To supply a decoration with a color, use `decoration: BoxDecoration(color: color)`.
  const Container({
    this.alignment,
    this.padding,
    this.color,
    this.decoration,
    this.foregroundDecoration,
    this.width,
    this.height,
    this.constraints,
    this.margin,
    this.child,
    super.key,
  }) : assert(
         color == null || decoration == null,
         'Cannot provide both a color and a decoration\n'
         'To provide both, use "decoration: BoxDecoration(color: color)".',
       ),
       assert(width == null || width >= 0),
       assert(height == null || height >= 0);

  /// The child contained by the container.
  ///
  /// If null, the container will size itself to its content, or if no content
  /// exists, it will attempt to be as small as possible within terminal
  /// character cell constraints.
  final Widget? child;

  /// Align the [child] within the container.
  ///
  /// If non-null, the container will expand to fill its parent and position its
  /// child within itself according to the given value. If the incoming
  /// constraints are unbounded, then the child will be shrink-wrapped instead.
  ///
  /// Ignored if [child] is null.
  final Alignment? alignment;

  /// Empty space to inscribe inside the [decoration]. The [child], if any, is
  /// placed inside this padding.
  final EdgeInsets? padding;

  /// The color to paint behind the [child].
  ///
  /// Prefer this property for a simple solid background. Use [decoration] when
  /// a supported terminal border is also needed.
  ///
  /// If the [decoration] is used, this property must be null. A background
  /// color may still be painted by the [decoration] even if this property is
  /// null.
  final Color? color;

  /// The decoration to paint behind the [child].
  ///
  /// Use the [color] property to specify a simple solid color.
  ///
  /// The [child] is not clipped to the decoration. Render objects that need
  /// rectangular clipping use `PaintingContext` / `TuiCanvas.clipRect`.
  final BoxDecoration? decoration;

  /// The decoration to paint in front of the [child].
  final BoxDecoration? foregroundDecoration;

  /// If non-null, the width of this widget in terminal character cells.
  final int? width;

  /// If non-null, the height of this widget in terminal character cells.
  final int? height;

  /// Extra min/max constraints on the child, tightened by [width]/[height].
  final BoxConstraints? constraints;

  /// Empty space to surround the [decoration] and [child].
  final EdgeInsets? margin;

  /// Composes the configured wrappers from [alignment] innermost to [margin]
  /// outermost around [child].
  @override
  Widget build(BuildContext context) {
    var current = child;

    // Build effective decoration from properties
    var effectiveDecoration = decoration;
    if (color != null) {
      assert(decoration == null);
      effectiveDecoration = BoxDecoration(color: color);
    }

    // 1. Apply alignment if specified (Flutter order: alignment first)
    if (alignment != null && current != null) {
      current = Align(alignment: alignment!, child: current);
    }

    // 2. Apply padding. In a terminal a border occupies exactly one
    // character cell at each edge of the box, so any explicit `padding`
    // of >= 1 already keeps content off the border row/column. Use the
    // per-side max of `padding` and the decoration's border thickness
    // instead of their sum: summing double-counts the border and steals
    // cells, which in tight layouts (e.g. Container(height: 4) with
    // padding: 1 and border: 1) collapses the inner content area to
    // zero rows so the label and children never appear.
    var effectivePadding = padding;
    final decorationPadding = effectiveDecoration?.padding;
    if (decorationPadding != null) {
      final base = effectivePadding ?? EdgeInsets.zero;
      effectivePadding = EdgeInsets.only(
        left: math.max(base.left, decorationPadding.left),
        top: math.max(base.top, decorationPadding.top),
        right: math.max(base.right, decorationPadding.right),
        bottom: math.max(base.bottom, decorationPadding.bottom),
      );
    }

    if (effectivePadding != null) {
      current = Padding(padding: effectivePadding, child: current);
    }

    // 3. Apply decoration (painted around the padded child)
    if (effectiveDecoration != null) {
      current = DecoratedBox(decoration: effectiveDecoration, child: current);
    }

    // 4. Apply foreground decoration (Flutter order: foreground after background)
    if (foregroundDecoration != null) {
      current = DecoratedBox(
        decoration: foregroundDecoration!,
        position: DecorationPosition.foreground,
        child: current,
      );
    }

    // 5. Apply constraints (combine width/height with additional constraints)
    // Only tighten dimensions that are explicitly provided; leave others
    // unconstrained (null max == unbounded).
    var effectiveConstraints = constraints;
    if (width != null || height != null) {
      // If base constraints exist, tighten them with specified dimensions.
      effectiveConstraints =
          effectiveConstraints?.tighten(width: width, height: height) ??
          BoxConstraints(
            minWidth: width ?? 0,
            maxWidth: width,
            minHeight: height ?? 0,
            maxHeight: height,
          );
    }

    if (effectiveConstraints != null) {
      current = ConstrainedBox(
        constraints: effectiveConstraints,
        child: current,
      );
    }

    // 6. Apply margin as outer padding (Flutter order: margin last)
    if (margin != null) {
      current = Padding(padding: margin!, child: current);
    }

    return current ?? const SizedBox.shrink();
  }
}
