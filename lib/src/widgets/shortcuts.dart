import '../core/input.dart';
import '../framework/build_context.dart';
import '../framework/element.dart';
import '../framework/widget.dart';
import 'actions.dart';
import 'intents.dart';

/// Matches a [KeyEvent] and chooses a semantic [Intent].
abstract class ShortcutActivator {
  /// Initializes the base contract for matching a key event to an intent.
  const ShortcutActivator();

  /// Whether [event] matches this activator.
  bool accepts(KeyEvent event);
}

/// Matches a logical key plus optional exact modifiers.
final class SingleActivator extends ShortcutActivator {
  /// Matches [trigger] with exact modifiers and configurable repeat handling.
  const SingleActivator(
    this.trigger, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
    this.includeRepeats = true,
  });

  /// Logical key that triggers the shortcut.
  final LogicalKeyboardKey trigger;

  /// Whether Control must be pressed.
  final bool control;

  /// Whether Shift must be pressed.
  final bool shift;

  /// Whether Alt must be pressed.
  final bool alt;

  /// Whether Meta must be pressed.
  final bool meta;

  /// Whether repeated key events are accepted.
  final bool includeRepeats;

  @override
  bool accepts(KeyEvent event) =>
      event.isPress &&
      event.logicalKey == trigger &&
      (includeRepeats || !event.isRepeat) &&
      _modifiersMatch(
        event,
        shift: shift,
        control: control,
        alt: alt,
        meta: meta,
      );
}

/// Matches a printable character plus optional exact modifiers.
final class CharacterActivator extends ShortcutActivator {
  /// Matches [character] and exact non-Shift modifiers, optionally excluding repeats.
  const CharacterActivator(
    this.character, {
    this.control = false,
    this.alt = false,
    this.meta = false,
    this.includeRepeats = true,
  });

  /// Printable character that triggers the shortcut.
  final String character;

  /// Whether Control must be pressed.
  final bool control;

  /// Whether Alt must be pressed.
  final bool alt;

  /// Whether Meta must be pressed.
  final bool meta;

  /// Whether repeated key events are accepted.
  final bool includeRepeats;

  @override
  bool accepts(KeyEvent event) =>
      event.isPress &&
      event.character == character &&
      (includeRepeats || !event.isRepeat) &&
      _modifiersMatch(
        event,
        shift: event.isShiftPressed,
        control: control,
        alt: alt,
        meta: meta,
      );
}

/// Inherited map from keyboard activators to semantic intents.
class Shortcuts extends InheritedWidget {
  /// Creates a Shortcuts widget.
  const Shortcuts({required this.shortcuts, required super.child, super.key});

  /// Available shortcuts in lookup order.
  final Map<ShortcutActivator, Intent> shortcuts;

  /// Dispatch [event] through nearest shortcut and action maps.
  static KeyEventResult handleKeyEvent(BuildContext context, KeyEvent event) {
    var result = KeyEventResult.ignored;
    context.visitAncestorElements((element) {
      if (element is InheritedElement && element.widget is Shortcuts) {
        final widget = element.widget as Shortcuts;
        for (final entry in widget.shortcuts.entries) {
          if (!entry.key.accepts(event)) continue;
          result = Actions.maybeInvoke(context, entry.value);
          return false;
        }
      }
      return true;
    });
    return result;
  }

  @override
  bool updateShouldNotify(covariant Shortcuts oldWidget) =>
      shortcuts != oldWidget.shortcuts;
}

bool _modifiersMatch(
  KeyEvent event, {
  required bool shift,
  required bool control,
  required bool alt,
  required bool meta,
}) =>
    event.isShiftPressed == shift &&
    event.isControlPressed == control &&
    event.isAltPressed == alt &&
    event.isMetaPressed == meta;
