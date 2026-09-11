import '../core/input.dart';
import '../framework/build_context.dart';
import '../framework/element.dart';
import '../framework/widget.dart';
import 'intents.dart';

/// Function used by [CallbackAction].
typedef ActionCallback<T extends Intent> =
    KeyEventResult Function(T intent, BuildContext context);

/// Handles semantic intents.
abstract class Action<T extends Intent> {
  /// Initializes a typed action that is enabled unless a subclass says otherwise.
  const Action();

  /// Whether this action can handle [intent].
  bool isEnabled(T intent) => true;

  /// Invokes this action.
  KeyEventResult invoke(T intent, BuildContext context);

  /// Invokes this action after a dynamic intent lookup.
  KeyEventResult invokeIntent(Intent intent, BuildContext context) {
    final typed = intent as T;
    if (!isEnabled(typed)) return KeyEventResult.ignored;
    return invoke(typed, context);
  }
}

/// Action backed by a Dart callback.
class CallbackAction<T extends Intent> extends Action<T> {
  /// Delegates typed intent invocation to [onInvoke].
  const CallbackAction(this.onInvoke);

  /// Callback that handles the typed intent.
  final ActionCallback<T> onInvoke;

  @override
  KeyEventResult invoke(T intent, BuildContext context) =>
      onInvoke(intent, context);
}

/// Inherited map from intent type to [Action].
class Actions extends InheritedWidget {
  /// Creates an Actions widget.
  const Actions({required this.actions, required super.child, super.key});

  /// Available actions keyed by intent runtime type.
  final Map<Type, Action<Intent>> actions;

  /// Finds the nearest action for [intentType].
  static Action<Intent>? maybeFind(BuildContext context, Type intentType) {
    Action<Intent>? found;
    context.visitAncestorElements((element) {
      if (element is InheritedElement && element.widget is Actions) {
        final widget = element.widget as Actions;
        final action = widget.actions[intentType];
        if (action != null) {
          found = action;
          return false;
        }
      }
      return true;
    });
    return found;
  }

  /// Finds the nearest action for [intentType] or throws.
  ///
  /// Flutter-parity member; kept for API parity — see Flutter's
  /// `Actions.find`.
  static Action<Intent> find(BuildContext context, Type intentType) {
    final action = maybeFind(context, intentType);
    if (action == null) {
      throw StateError('No Action registered for $intentType.');
    }
    return action;
  }

  /// Invokes the nearest action matching [intent], if any.
  static KeyEventResult maybeInvoke(BuildContext context, Intent intent) {
    final action = maybeFind(context, intent.runtimeType);
    if (action == null) return KeyEventResult.ignored;
    return action.invokeIntent(intent, context);
  }

  /// Invokes the nearest action matching [intent].
  ///
  /// Flutter-parity member; kept for API parity — see Flutter's
  /// `Actions.invoke`.
  static KeyEventResult invoke(BuildContext context, Intent intent) {
    final action = find(context, intent.runtimeType);
    return action.invokeIntent(intent, context);
  }

  @override
  bool updateShouldNotify(covariant Actions oldWidget) =>
      actions != oldWidget.actions;
}
