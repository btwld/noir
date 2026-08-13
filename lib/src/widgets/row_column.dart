import 'package:meta/meta.dart';

import '../framework/build_context.dart';
import '../framework/element.dart';
import '../render/geometry.dart';
import '../rendering/flex.dart';
import 'flexible.dart';

/// How the children should be placed along the main axis in a flex layout.
enum MainAxisAlignment {
  /// Place the children as close to the start of the main axis as possible.
  start,

  /// Place the children as close to the end of the main axis as possible.
  end,

  /// Place the children as close to the middle of the main axis as possible.
  center,

  /// Place the free space evenly between the children.
  spaceBetween,

  /// Place the free space evenly between the children as well as half of that
  /// space before and after the first and last child.
  spaceAround,

  /// Place the free space evenly between the children as well as before and
  /// after the first and last child.
  spaceEvenly,
}

/// How much space should be occupied in the main axis.
///
/// All main-axis allocations are whole terminal cells.
enum MainAxisSize {
  /// Size to the children's combined extent, clamped to the max constraint.
  min,

  /// Size to the incoming maximum main-axis constraint.
  max,
}

/// How the children should be placed along the cross axis in a flex layout.
///
/// **Terminal-Only Cross Axis Alignment**: Unlike Flutter which supports baseline
/// alignment for mixed font sizes, terminals use monospaced fonts with uniform
/// character heights making baseline alignment meaningless.
///
/// Flutter compatibility note: baseline removed because terminal text has no
/// font metrics - all characters occupy identical rectangular cells.
enum CrossAxisAlignment {
  /// Place the children with their start edge aligned with the start side of
  /// the cross axis.
  start,

  /// Place the children as close to the end of the cross axis as possible.
  end,

  /// Place the children so that their centers align with the middle of the
  /// cross axis.
  center,

  /// Size children to fill the cross axis before positioning them.
  stretch,
}

/// Base class for widgets that arrange children in a one-dimensional array.
///
/// This widget uses [RenderFlex] for proper flex layout with all flex
/// properties supported.
///
/// See also:
///  * [Row], for a horizontal layout.
///  * [Column], for a vertical layout.
abstract class Flex extends MultiChildRenderObjectWidget {
  /// Creates a flex layout widget.
  const Flex({
    required this.direction,
    super.key,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    super.children,
    this.spacing = 0,
  }) : assert(spacing >= 0);

  /// The direction to use as the main axis.
  final Axis direction;

  /// How the children should be placed along the main axis.
  final MainAxisAlignment mainAxisAlignment;

  /// How much space should be occupied in the main axis.
  ///
  /// **Terminal layout control:**
  /// - If [MainAxisSize.max], size equals incoming max constraint
  /// - If [MainAxisSize.min], size equals sum of children sizes (≤ max constraint)
  final MainAxisSize mainAxisSize;

  /// How the children should be placed along the cross axis.
  final CrossAxisAlignment crossAxisAlignment;

  /// The amount of space to place between children in the main axis.
  ///
  /// The value must be a non-negative number of whole terminal cells.
  final int spacing;

  @override
  @internal
  RenderFlex createRenderObject(BuildContext context) => RenderFlex(
    direction: direction,
    mainAxisAlignment: mainAxisAlignment,
    mainAxisSize: mainAxisSize,
    crossAxisAlignment: crossAxisAlignment,
    spacing: spacing,
  );

  @override
  @internal
  void updateRenderObject(BuildContext context, RenderFlex renderObject) {
    renderObject
      ..direction = direction
      ..mainAxisAlignment = mainAxisAlignment
      ..mainAxisSize = mainAxisSize
      ..crossAxisAlignment = crossAxisAlignment
      ..spacing = spacing;
  }

  @override
  @internal
  FlexRenderObjectElement createElement() => FlexRenderObjectElement(this);
}

/// A widget that displays its children in a horizontal array.
///
/// This widget uses RenderFlex for proper flex layout with all flex properties supported.
class Row extends Flex {
  /// Creates a horizontal array of children.
  const Row({
    super.key,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.children,
    super.spacing,
  }) : super(direction: Axis.horizontal);
}

/// A widget that displays its children in a vertical array.
///
/// This widget uses RenderFlex for proper flex layout with all flex properties supported.
class Column extends Flex {
  /// Creates a vertical array of children.
  const Column({
    super.key,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.children,
    super.spacing,
  }) : super(direction: Axis.vertical);
}
