import 'package:meta/meta.dart';

import '../core/input.dart';
import '../core/mouse_cursor.dart';
import '../framework/widget.dart';
import 'actions.dart';
import 'focus.dart';
import 'focus_node_owner_mixin.dart';
import 'intents.dart';
import 'pointer_listener.dart';
import 'shortcuts.dart';

/// Shared focus and activation wiring for the leaf controls — [Checkbox],
/// [Switch], and [Button].
///
/// All three answer the same three gestures with one [activate] call: Space,
/// Enter, and a left click. All three are disabled the same way, by leaving
/// their callback null, which also drops them out of Tab traversal. Keeping
/// that in one place is what stops the three controls from drifting apart on
/// which key activates what.
///
/// A mixing state supplies [activate] and [isEnabled] and wraps its visuals in
/// [buildActivatable]. [isFocused] is available for a focus affordance.
@internal
mixin ActivatableStateMixin<T extends StatefulWidget>
    on State<T>, FocusNodeOwnerStateMixin<T> {
  bool _focused = false;

  /// Whether the control currently holds primary focus.
  bool get isFocused => _focused;

  /// Whether the control responds to Space, Enter, and clicks. A disabled
  /// control also refuses focus, so Tab skips it.
  bool get isEnabled;

  /// Invoked once per Space, Enter, or left click while [isEnabled].
  void activate();

  static const Map<ShortcutActivator, Intent> _shortcuts = {
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  };

  Map<Type, Action<Intent>> get _actions => {
    ActivateIntent: CallbackAction<ActivateIntent>((intent, context) {
      if (!isEnabled) return KeyEventResult.ignored;
      activate();
      return KeyEventResult.handled;
    }),
  };

  void _handlePointerDown(MouseEvent event) {
    if (event.button != MouseButton.left || !isEnabled) return;
    if (!focusNode.hasFocus) focusNode.requestFocus();
    activate();
  }

  void _handleFocusChange(bool hasFocus) {
    if (_focused == hasFocus) return;
    setState(() => _focused = hasFocus);
  }

  /// Wraps [child] in the shared shortcut, action, focus, and pointer layers.
  Widget buildActivatable({required Widget child, required bool autofocus}) =>
      Shortcuts(
        shortcuts: _shortcuts,
        child: Actions(
          actions: _actions,
          child: Focus(
            focusNode: focusNode,
            autofocus: autofocus && isEnabled,
            canRequestFocus: isEnabled,
            onFocusChange: _handleFocusChange,
            child: PointerListener(
              mouseCursor: isEnabled ? MouseCursor.pointer : MouseCursor.basic,
              onPointerDown: _handlePointerDown,
              child: child,
            ),
          ),
        ),
      );
}
