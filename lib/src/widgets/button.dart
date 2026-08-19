import '../core/color.dart';
import '../foundation/listenable.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import 'activatable.dart';
import 'container.dart';
import 'focus_node_owner_mixin.dart';
import 'text.dart';
import 'text_style.dart';
import 'theme.dart';

/// A labelled push surface activated by Space, Enter, or a left click.
///
/// The button paints a solid fill behind its label rather than a border, which
/// keeps it one row tall — a bordered button costs three rows, and terminal
/// layouts rarely have them to spare. Add a `DecoratedBox` for a border when
/// the space exists.
///
/// Leaving [onPressed] null disables the button, which mutes its colors and
/// drops it out of Tab traversal. While focused the label renders bold.
///
/// ```dart
/// Button(label: 'Run', onPressed: () => setState(_start))
/// ```
class Button extends StatefulWidget {
  /// Configures a button showing [label], disabled when [onPressed] is null.
  const Button({
    required this.label,
    super.key,
    this.onPressed,
    this.color,
    this.textColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 1),
    this.focusNode,
    this.autofocus = false,
  });

  /// Text rendered inside the button.
  final String label;

  /// Called once per activation. A null callback disables the button.
  final VoidCallback? onPressed;

  /// Fill painted behind the label. Falls back to [ThemeData.accent]. A
  /// disabled button ignores this and uses [ThemeData.surfaceVariant].
  final Color? color;

  /// Color of the label. Falls back to [ThemeData.accentForeground]. A
  /// disabled button ignores this and uses [ThemeData.textMuted].
  final Color? textColor;

  /// Empty space between the fill's edge and the label.
  final EdgeInsets padding;

  /// Focus node controlling this button. One is created if null.
  final FocusNode? focusNode;

  /// Whether this widget requests focus when first mounted. Ignored while the
  /// button is disabled.
  final bool autofocus;

  @override
  State<Button> createState() => _ButtonState();
}

class _ButtonState extends State<Button>
    with FocusNodeOwnerStateMixin<Button>, ActivatableStateMixin<Button> {
  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  bool get isEnabled => widget.onPressed != null;

  @override
  void activate() => widget.onPressed?.call();

  @override
  void didUpdateWidget(Button oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = isEnabled
        ? widget.color ?? theme.accent
        : theme.surfaceVariant;
    final label = isEnabled
        ? widget.textColor ?? theme.accentForeground
        : theme.textMuted;

    return buildActivatable(
      autofocus: widget.autofocus,
      child: Container(
        color: fill,
        padding: widget.padding,
        child: Text(
          widget.label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: label,
            fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
