import 'package:meta/meta.dart';

import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/object.dart';
import '../rendering/padding.dart';

/// A widget that insets its child by the given padding.
class Padding extends SingleChildRenderObjectWidget {
  /// Insets the optional child by the required [padding].
  const Padding({required this.padding, super.child, super.key});

  /// Terminal-cell insets applied around the child.
  final EdgeInsets padding;

  @override
  @internal
  RenderObject createRenderObject(BuildContext context) =>
      RenderPadding(padding: padding);

  @override
  @internal
  void updateRenderObject(BuildContext context, RenderPadding renderObject) {
    renderObject.padding = padding;
  }
}
