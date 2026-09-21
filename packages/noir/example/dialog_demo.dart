// Run with: dart run example/dialog_demo.dart
// Activate `Review deploy` to open the dialog. Tab and Shift+Tab remain inside
// it; Escape or Cancel closes it, and Deploy confirms. The full-screen pointer
// barrier keeps the underlying screen visible without letting it receive
// input.

import 'package:noir/noir.dart';

import 'src/shared/demo_scaffold.dart';

void main() => runTuiApp(const DialogDemoApp(), enableMouse: true);

/// A confirmation dialog composed from Noir's public overlay and focus APIs.
class DialogDemoApp extends StatefulWidget {
  const DialogDemoApp({super.key});

  @override
  State<DialogDemoApp> createState() => _DialogDemoAppState();
}

class _DialogDemoAppState extends State<DialogDemoApp> {
  final _modal = ModalController();
  final _reviewFocus = FocusNode(debugLabel: 'review-deploy');
  final _refreshFocus = FocusNode(debugLabel: 'refresh-release');
  final _cancelFocus = FocusNode(debugLabel: 'cancel-deploy');
  final _deployFocus = FocusNode(debugLabel: 'confirm-deploy');

  var _status = 'Production remains unchanged.';

  @override
  void dispose() {
    _reviewFocus.dispose();
    _refreshFocus.dispose();
    _cancelFocus.dispose();
    _deployFocus.dispose();
    super.dispose();
  }

  void _openDialog() => _modal.open();

  void _closeDialog() => _modal.close();

  void _refreshRelease() {
    setState(
      () => _status = 'Release data refreshed. Production is unchanged.',
    );
  }

  void _deploy() {
    setState(() {
      _status = 'Deployment scheduled for noir 0.0.3.';
    });
    _closeDialog();
  }

  @override
  Widget build(BuildContext context) => Modal(
    controller: _modal,
    initialFocusNode: _cancelFocus,
    modalBuilder: _buildDialog,
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
                    'noir 0.0.3 · ready for review',
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
            'Deploy noir 0.0.3 to production?',
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
