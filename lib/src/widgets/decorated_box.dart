import 'package:meta/meta.dart';

import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../painting/decoration.dart';
import '../rendering/decorated_box.dart';
import '../rendering/object.dart';

/// Where to paint a box decoration.
enum DecorationPosition {
  /// Paint the box decoration behind the children.
  background,

  /// Paint the box decoration in front of the children.
  foreground,
}

/// A widget that paints a [Decoration] either before or after its child paints.
///
/// [Container] insets its child by the widths of the borders; this widget does
/// not.
///
/// Commonly used with [BoxDecoration].
class DecoratedBox extends SingleChildRenderObjectWidget {
  /// Creates a widget that paints a [Decoration].
  ///
  /// By default the decoration paints behind the child.
  const DecoratedBox({
    required this.decoration,
    this.position = DecorationPosition.background,
    super.child,
    super.key,
  });

  /// What decoration to paint.
  ///
  /// Commonly a [BoxDecoration].
  final Decoration decoration;

  /// Whether to paint the box decoration behind or in front of the child.
  final DecorationPosition position;

  @override
  @internal
  RenderObject createRenderObject(BuildContext context) =>
      RenderDecoratedBox(decoration: decoration, position: position);

  @override
  @internal
  void updateRenderObject(
    BuildContext context,
    RenderDecoratedBox renderObject,
  ) {
    renderObject
      ..decoration = decoration
      ..position = position;
  }
}
