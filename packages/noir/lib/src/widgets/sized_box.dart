import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import 'constrained_box.dart';

/// A box with a fixed [width] and/or [height] that constrains its [child].
class SizedBox extends StatelessWidget {
  /// Makes each specified non-negative cell dimension tight and leaves null axes unbounded.
  const SizedBox({this.width, this.height, this.child, super.key})
    : assert(width == null || width >= 0),
      assert(height == null || height >= 0);

  /// Creates a zero-by-zero box with no child.
  const SizedBox.shrink({super.key}) : width = 0, height = 0, child = null;

  /// Gives the optional [child] equal non-negative cell dimensions.
  const SizedBox.square({required int dimension, this.child, super.key})
    : assert(dimension >= 0),
      width = dimension,
      height = dimension;

  /// The width to give the child, in terminal character cells.
  ///
  /// If null, the child's width is left unconstrained.
  final int? width;

  /// The height to give the child, in terminal character cells.
  ///
  /// If null, the child's height is left unconstrained.
  final int? height;

  /// The widget below this widget in the tree.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (width != null || height != null) {
      // Tight constraints on specified dimensions; the other axis stays
      // unbounded (null max) so the child sizes naturally.
      return ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: width ?? 0,
          maxWidth: width,
          minHeight: height ?? 0,
          maxHeight: height,
        ),
        child: child,
      );
    } else {
      // No size specified, just return the child or empty box
      return child ??
          const ConstrainedBox(
            constraints: BoxConstraints.tight(width: 0, height: 0),
          );
    }
  }
}
