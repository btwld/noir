import 'package:meta/meta.dart';

import '../framework/build_context.dart';
import '../framework/element.dart';
import '../render/geometry.dart';
import '../rendering/flex.dart';
import 'flexible.dart';

/// Base class for widgets that arrange children in a one-dimensional array.
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
