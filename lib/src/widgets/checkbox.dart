import '../core/color.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import 'activatable.dart';
import 'focus_node_owner_mixin.dart';
import 'input.dart';
import 'row_column.dart';
import 'text.dart';
import 'text_style.dart';
import 'theme.dart';

/// Glyphs are the geometric-shapes block, not the ballot box: `☐`/`☑` render
/// at double width in several terminals, which would shift the label by a cell
/// as the value changes.
const String _unchecked = '□'; // U+25A1
const String _checked = '■'; // U+25A0

/// A two-state box with an optional label, toggled by Space, Enter, or a click.
///
/// The value is caller-owned: [onChanged] reports the requested value and the
/// caller passes it back in through [value]. Leaving [onChanged] null disables
/// the checkbox, which mutes its colors and drops it out of Tab traversal.
///
/// While focused the checkbox renders bold, the affordance the terminal always
/// has regardless of color support.
///
/// ```dart
/// Checkbox(
///   value: _wrap,
///   label: 'Soft wrap',
///   onChanged: (next) => setState(() => _wrap = next),
/// )
/// ```
class Checkbox extends StatefulWidget {
  /// Configures a checkbox showing [value], disabled when [onChanged] is null.
  const Checkbox({
    required this.value,
    super.key,
    this.onChanged,
    this.label,
    this.color,
    this.checkedColor,
    this.focusNode,
    this.autofocus = false,
  });

  /// Whether the box renders as checked.
  final bool value;

  /// Called with the requested value when the user toggles the box. A null
  /// callback disables the checkbox.
  final ValueChanged<bool>? onChanged;

  /// Optional text rendered one cell after the box.
  final String? label;

  /// Color of the unchecked box and the label. Falls back to
  /// [ThemeData.text], then to [Color.white].
  final Color? color;

  /// Color of the checked box. Falls back to [ThemeData.accent], then to
  /// [color].
  final Color? checkedColor;

  /// Focus node controlling this checkbox. One is created if null.
  final FocusNode? focusNode;

  /// Whether this widget requests focus when first mounted. Ignored while the
  /// checkbox is disabled.
  final bool autofocus;

  @override
  State<Checkbox> createState() => _CheckboxState();
}

class _CheckboxState extends State<Checkbox>
    with FocusNodeOwnerStateMixin<Checkbox>, ActivatableStateMixin<Checkbox> {
  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  bool get isEnabled => widget.onChanged != null;

  @override
  void activate() => widget.onChanged?.call(!widget.value);

  @override
  void didUpdateWidget(Checkbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.maybeOf(context);
    final base = widget.color ?? theme?.text ?? Color.white;
    final boxColor = isEnabled
        ? (widget.value ? widget.checkedColor ?? theme?.accent ?? base : base)
        : theme?.textMuted ?? Color.gray;
    final labelColor = isEnabled ? base : theme?.textMuted ?? Color.gray;
    final weight = isFocused ? FontWeight.bold : FontWeight.normal;

    return buildActivatable(
      autofocus: widget.autofocus,
      child: Row(
        children: [
          Text(
            widget.value ? _checked : _unchecked,
            style: TextStyle(color: boxColor, fontWeight: weight),
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
