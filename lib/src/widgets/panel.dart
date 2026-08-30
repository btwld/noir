import '../core/color.dart';
import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../painting/box_border.dart';
import '../painting/box_decoration.dart';
import '../render/geometry.dart';
import 'container.dart';
import 'icons.dart';
import 'theme.dart';

/// A themed bordered region with an optional title on its top edge.
///
/// A panel shrink-wraps [child] unless [width] or [height] fixes that axis.
/// Fixed dimensions include the one-cell border; [width] also includes the
/// one-cell horizontal content inset. This makes fixed panels suitable for
/// viewport children such as lists and editors.
///
/// [focused] is a visual state only: it changes the default border from
/// [ThemeData.border] to [ThemeData.accent] and adds a one-cell marker so
/// keyboard ownership does not rely on color. The caller remains responsible
/// for focus and passes the resulting state here.
///
/// Omitted colors resolve from the nearest [Theme]. An explicit [color] or
/// [borderColor] takes precedence over that palette; [borderColor] applies in
/// both focus states.
class Panel extends StatelessWidget {
  /// Creates themed panel chrome around [child].
  const Panel({
    required this.child,
    super.key,
    this.title,
    this.focused = false,
    this.width,
    this.height,
    this.color,
    this.borderColor,
  }) : assert(width == null || width >= 0),
       assert(height == null || height >= 0);

  /// Label drawn on the top border, or null for an unlabelled border.
  final String? title;

  /// Whether the chrome indicates that this region owns keyboard focus.
  final bool focused;

  /// Fixed width in terminal cells, including border and horizontal inset.
  final int? width;

  /// Fixed height in terminal cells, including the top and bottom border.
  final int? height;

  /// Fill behind [child]. Falls back to [ThemeData.surfaceVariant].
  final Color? color;

  /// Border and title color.
  ///
  /// Falls back to [ThemeData.accent] while [focused] and [ThemeData.border]
  /// otherwise.
  final Color? borderColor;

  /// Content placed inside the border.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderTitle = switch ((title, focused)) {
      (final title?, true) => ' ${Icons.chevronRight} $title ',
      (final title?, false) => ' $title ',
      (null, true) => ' ${Icons.chevronRight} ',
      (null, false) => null,
    };
    final chrome = borderColor ?? (focused ? theme.accent : theme.border);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? theme.surfaceVariant,
        border: Border.all(color: chrome, title: borderTitle),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: child,
    );
  }
}
