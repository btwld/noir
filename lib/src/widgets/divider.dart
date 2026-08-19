import '../core/color.dart';
import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import 'container.dart';
import 'sized_box.dart';
import 'theme.dart';

/// A filled rule that separates sections of a layout.
///
/// The rule is a solid band of [thickness] cells, not a run of `─`: a band
/// needs no width to be known up front, so the divider stays pure composition
/// and inherits whatever cross-axis extent its parent offers.
///
/// It spans as much of its cross axis as the parent offers, so that axis has
/// to be bounded. A horizontal rule in a `Column` is bounded by the terminal
/// width and needs nothing extra:
///
/// ```dart
/// Column(children: [header, const Divider(), body])
/// ```
///
/// A vertical rule inside a `Row` is a different story: a `Row` hands its
/// children an unbounded height whenever its own parent leaves the height
/// loose, and an unbounded axis has no extent to span, so the rule renders
/// zero cells tall. Give it a height:
///
/// ```dart
/// Row(
///   children: [
///     left,
///     const SizedBox(height: 3, child: Divider(axis: Axis.vertical)),
///     right,
///   ],
/// )
/// ```
class Divider extends StatelessWidget {
  /// Configures a rule [thickness] cells thick, running across [axis].
  const Divider({
    super.key,
    this.thickness = 1,
    this.color,
    this.axis = Axis.horizontal,
  }) : assert(thickness >= 1);

  /// Cells of extent the rule occupies along its short side.
  final int thickness;

  /// Fill of the rule. Falls back to [ThemeData.border].
  final Color? color;

  /// Direction the rule runs. A horizontal rule separates stacked rows; a
  /// vertical one separates side-by-side columns.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? Theme.of(context).border;
    // `alignment` makes Container wrap the (empty) child in an Align, and Align
    // fills every bounded axis. Without it the fill would collapse to the
    // minimum extent whenever the parent's constraints are loose.
    return Container(
      color: fill,
      width: axis == Axis.vertical ? thickness : null,
      height: axis == Axis.horizontal ? thickness : null,
      alignment: Alignment.center,
      child: const SizedBox.shrink(),
    );
  }
}
