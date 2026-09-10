import 'package:meta/meta.dart';

import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/positioned_box.dart';

/// A widget that aligns its child within itself.
///
/// Positions the child in whole terminal cells. Flutter's `widthFactor` and
/// `heightFactor` sizing options are not supported.
///
/// This widget uses RenderPositionedBox to handle alignment positioning
/// without relying on Container widgets to avoid circular dependencies.
class Align extends SingleChildRenderObjectWidget {
  /// Creates an alignment widget.
  ///
  /// The alignment defaults to [Alignment.center].
  const Align({this.alignment = Alignment.center, super.child, super.key});

  /// The alignment of the child within the parent.
  final Alignment alignment;

  @override
  @internal
  RenderPositionedBox createRenderObject(BuildContext context) =>
      RenderPositionedBox(alignment: alignment);

  @override
  @internal
  void updateRenderObject(
    BuildContext context,
    RenderPositionedBox renderObject,
  ) {
    renderObject.alignment = alignment;
  }
}
