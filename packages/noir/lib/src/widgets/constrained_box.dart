import 'package:meta/meta.dart';

import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/constrained_box.dart';
import '../rendering/object.dart';

/// A widget that imposes additional constraints on its child.
///
/// This is a primitive widget focused only on constraint enforcement.
/// For convenience widgets that combine constraints with decoration and padding, use [Container].
class ConstrainedBox extends SingleChildRenderObjectWidget {
  /// Applies [constraints] in addition to those received by the optional child.
  const ConstrainedBox({required this.constraints, super.child, super.key});

  /// Additional bounds imposed during child layout.
  final BoxConstraints constraints;

  @override
  @internal
  RenderObject createRenderObject(BuildContext context) =>
      RenderConstrainedBox(additionalConstraints: constraints);

  @override
  @internal
  void updateRenderObject(
    BuildContext context,
    RenderConstrainedBox renderObject,
  ) {
    renderObject.additionalConstraints = constraints;
  }
}
