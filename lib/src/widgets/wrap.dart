import 'package:meta/meta.dart';

import '../framework/build_context.dart';
import '../framework/element.dart';
import '../render/geometry.dart';
import '../rendering/wrap.dart';

/// Arranges children into horizontal or vertical runs.
class Wrap extends MultiChildRenderObjectWidget {
  /// Creates a wrapping layout in whole terminal cells.
  const Wrap({
    super.key,
    super.children,
    this.direction = Axis.horizontal,
    this.spacing = 0,
    this.runSpacing = 0,
    this.alignment = WrapAlignment.start,
    this.runAlignment = WrapAlignment.start,
    this.crossAxisAlignment = WrapCrossAlignment.start,
  }) : assert(spacing >= 0),
       assert(runSpacing >= 0);

  /// Axis along which children fill each run.
  final Axis direction;

  /// Cells between adjacent children.
  final int spacing;

  /// Cells between adjacent runs.
  final int runSpacing;

  /// Distribution of children within each run.
  final WrapAlignment alignment;

  /// Distribution of runs across the cross axis.
  final WrapAlignment runAlignment;

  /// Placement of children within each run's cross extent.
  final WrapCrossAlignment crossAxisAlignment;

  @override
  @internal
  RenderWrap createRenderObject(BuildContext context) => RenderWrap(
    direction: direction,
    spacing: spacing,
    runSpacing: runSpacing,
    alignment: alignment,
    runAlignment: runAlignment,
    crossAxisAlignment: crossAxisAlignment,
  );

  @override
  @internal
  void updateRenderObject(BuildContext context, RenderWrap renderObject) {
    renderObject
      ..direction = direction
      ..spacing = spacing
      ..runSpacing = runSpacing
      ..alignment = alignment
      ..runAlignment = runAlignment
      ..crossAxisAlignment = crossAxisAlignment;
  }
}
