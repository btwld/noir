import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';
import 'src/modal_overlay.dart';

void main() => runTuiApp(const DialogDemoApp(), enableMouse: true);

/// A confirmation dialog composed from Noir's public overlay and focus APIs.
class DialogDemoApp extends StatefulWidget {
  const DialogDemoApp({super.key});

  @override
  State<DialogDemoApp> createState() => _DialogDemoAppState();
}

class _DialogDemoAppState extends State<DialogDemoApp> {
  final _overlay = OverlayPortalController(debugLabel: 'deployment-dialog');
  final _reviewFocus = FocusNode(debugLabel: 'review-deploy');
  final _refreshFocus = FocusNode(debugLabel: 'refresh-release');
  final _cancelFocus = FocusNode(debugLabel: 'cancel-deploy');
  final _deployFocus = FocusNode(debugLabel: 'confirm-deploy');
  late final DemoClosedLoopTraversalPolicy _dialogTraversal =
      DemoClosedLoopTraversalPolicy([_cancelFocus, _deployFocus]);

  var _status = 'Production remains unchanged.';

  @override
  void dispose() {
    _reviewFocus.dispose();
    _refreshFocus.dispose();
    _cancelFocus.dispose();
    _deployFocus.dispose();
    super.dispose();
  }

  void _openDialog() => _overlay.show();

  void _closeDialog() {
    _overlay.hide();
    if (_reviewFocus.isAttached && _reviewFocus.canRequestFocus) {
      _reviewFocus.requestFocus();
    }
  }

  void _refreshRelease() {
    setState(
      () => _status = 'Release data refreshed. Production is unchanged.',
    );
  }

  void _deploy() {
    setState(() {
      _status = 'Deployment scheduled for noir 0.0.1-alpha.3.';
    });
    _closeDialog();
  }

  @override
  Widget build(BuildContext context) => DemoModalOverlay(
    controller: _overlay,
    onDismiss: _closeDialog,
    traversalPolicy: _dialogTraversal,
    dialog: _buildDialog(context),
    child: DemoScaffold(
      title: 'Deployment control',
      hint: 'Review the current release before changing production.',
      child: Panel(
        title: 'Release',
        child: Column(
          spacing: 1,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              spacing: 1,
              children: [
                const Expanded(
                  child: Text(
                    'noir 0.0.1-alpha.3 · ready for review',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Button(
                  key: const ValueKey<String>('refresh-release'),
                  label: 'Refresh',
                  focusNode: _refreshFocus,
                  color: Theme.of(context).surfaceVariant,
                  textColor: Theme.of(context).text,
                  onPressed: _refreshRelease,
                ),
                Button(
                  key: const ValueKey<String>('open-dialog'),
                  label: 'Review deploy',
                  focusNode: _reviewFocus,
                  autofocus: true,
                  onPressed: _openDialog,
                ),
              ],
            ),
            Text(_status, style: TextStyle(color: Theme.of(context).textMuted)),
          ],
        ),
      ),
    ),
  );

  Widget _buildDialog(BuildContext context) {
    final theme = Theme.of(context);
    return Panel(
      title: 'Confirm deployment',
      focused: true,
      width: 54,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 1,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Deploy noir 0.0.1-alpha.3 to production?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            'Target  production · us-east-1 · live release',
            style: TextStyle(color: theme.warning),
          ),
          Row(
            spacing: 1,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Button(
                key: const ValueKey<String>('cancel-deploy'),
                label: 'Cancel',
                focusNode: _cancelFocus,
                autofocus: true,
                color: theme.surfaceVariant,
                textColor: theme.text,
                onPressed: _closeDialog,
              ),
              Button(
                key: const ValueKey<String>('confirm-deploy'),
                label: 'Deploy',
                focusNode: _deployFocus,
                onPressed: _deploy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
