import '../core/color.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import 'activatable.dart';
import 'focus_node_owner_mixin.dart';
import 'icons.dart';
import 'row_column.dart';
import 'text.dart';
import 'text_input.dart';
import 'text_style.dart';
import 'theme.dart';

/// [Icons.circleOutline] and [Icons.circle] share one width class, so the
/// label never shifts as the value changes.
const String _off = Icons.circleOutline;
const String _on = Icons.circle;

/// A two-state toggle with an optional label, flipped by Space, Enter, or a
/// click.
///
/// [Switch] and [Checkbox] carry the same behavior and differ only in glyph:
/// a switch reads as an on/off device and a checkbox as a marked item. Pick by
/// what the value means, not by what it does.
///
/// The value is caller-owned: [onChanged] reports the requested value and the
/// caller passes it back in through [value]. Leaving [onChanged] null disables
/// the switch, which mutes its colors and drops it out of Tab traversal.
///
/// While focused the switch renders bold.
class Switch extends StatefulWidget {
  /// Configures a switch showing [value], disabled when [onChanged] is null.
  const Switch({
    required this.value,
    super.key,
    this.onChanged,
    this.label,
    this.color,
    this.activeColor,
    this.focusNode,
    this.autofocus = false,
  });

  /// Whether the switch renders as on.
  final bool value;

  /// Called with the requested value when the user flips the switch. A null
  /// callback disables the switch.
  final ValueChanged<bool>? onChanged;

  /// Optional text rendered one cell after the switch.
  final String? label;

  /// Color of the off circle and the label. Falls back to [ThemeData.text].
  final Color? color;

  /// Color of the on circle. Falls back to [ThemeData.success].
  final Color? activeColor;

  /// Focus node controlling this switch. One is created if null.
  final FocusNode? focusNode;

  /// Whether this widget requests focus when first mounted. Ignored while the
  /// switch is disabled.
  final bool autofocus;

  @override
  State<Switch> createState() => _SwitchState();
}

class _SwitchState extends State<Switch>
    with FocusNodeOwnerStateMixin<Switch>, ActivatableStateMixin<Switch> {
  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  bool get isEnabled => widget.onChanged != null;

  @override
  void activate() => widget.onChanged?.call(!widget.value);

  @override
  void didUpdateWidget(Switch oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = widget.color ?? theme.text;
    final knobColor = isEnabled
        ? (widget.value ? widget.activeColor ?? theme.success : base)
        : theme.textMuted;
    final labelColor = isEnabled ? base : theme.textMuted;
    final weight = isFocused ? FontWeight.bold : FontWeight.normal;

    return buildActivatable(
      autofocus: widget.autofocus,
      child: Row(
        children: [
          Text(
            widget.value ? _on : _off,
            style: TextStyle(color: knobColor, fontWeight: weight),
          ),
          if (widget.label != null)
            Text(
              ' ${widget.label}',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(color: labelColor, fontWeight: weight),
            ),
        ],
      ),
    );
  }
}
