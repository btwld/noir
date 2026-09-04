import 'package:noir/noir.dart';

import '../model/inspector_controller.dart';
import '../session/mcp_session.dart';
import 'form_view.dart';

/// The modal body that answers one server-initiated input request.
///
/// The panel shrink-wraps inside [Modal], which owns the centring, the closed
/// focus loop, and the blocked background input. Escape maps to
/// [ElicitationAction.cancel] explicitly, so the request always resolves.
class ElicitationModal extends StatelessWidget {
  /// Creates the modal body over [pending].
  const ElicitationModal({
    required this.pending,
    required this.focusNodeFor,
    required this.onChanged,
    required this.onResolve,
    super.key,
  });

  /// The request awaiting an answer.
  final PendingElicitation pending;

  /// Supplies the focus node for the field named by its argument.
  final FocusNode Function(String name) focusNodeFor;

  /// Called after a control changes a value, so the owner can rebuild.
  final VoidCallback onChanged;

  /// Answers the request.
  final void Function(ElicitationAction action) onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = pending.prompt.url;
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>((intent, context) {
            onResolve(ElicitationAction.cancel);
            return KeyEventResult.handled;
          }),
        },
        child: Panel(
          title: 'Server request',
          width: 56,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 1,
            children: <Widget>[
              Text(pending.prompt.message, maxLines: 3),
              if (url != null)
                Text(
                  'URL mode is not supported: $url',
                  style: TextStyle(color: theme.warning),
                  maxLines: 2,
                ),
              FormView(
                model: pending.form,
                focusNodeFor: focusNodeFor,
                onChanged: onChanged,
                keyPrefix: 'elicit:field',
              ),
              Row(
                spacing: 1,
                children: <Widget>[
                  Button(
                    key: const ValueKey<String>('elicit:accept'),
                    label: 'Accept',
                    onPressed: () => onResolve(ElicitationAction.accept),
                  ),
                  Button(
                    key: const ValueKey<String>('elicit:decline'),
                    label: 'Decline',
                    color: theme.surfaceVariant,
                    textColor: theme.text,
                    onPressed: () => onResolve(ElicitationAction.decline),
                  ),
                  Button(
                    key: const ValueKey<String>('elicit:cancel'),
                    label: 'Cancel',
                    color: theme.surfaceVariant,
                    textColor: theme.text,
                    onPressed: () => onResolve(ElicitationAction.cancel),
                  ),
                ],
              ),
              Text(
                'Escape cancels. Tab moves between the fields and buttons.',
                style: TextStyle(color: theme.textMuted),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
