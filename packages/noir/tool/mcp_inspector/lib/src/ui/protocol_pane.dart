import 'dart:convert';

import 'package:noir/noir.dart';

import '../model/inspector_controller.dart';

/// The right pane for the protocol tab: the selected message as JSON.
class ProtocolPane extends StatelessWidget {
  /// Creates the pane over [controller].
  const ProtocolPane({
    required this.controller,
    required this.focusNode,
    super.key,
  });

  /// The state owner this pane reads.
  final InspectorController controller;

  /// The node that owns keyboard focus for the JSON view.
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = controller.selectedProtocolEntry;
    if (entry == null) {
      return Panel(
        title: 'Message',
        child: Text(
          'No message is selected.',
          style: TextStyle(color: theme.textMuted),
        ),
      );
    }
    return Panel(
      title: entry.label,
      focused: focusNode.hasFocus,
      child: CodeView(
        key: ValueKey<String>('message:${entry.sequence}'),
        code: const JsonEncoder.withIndent('  ').convert(entry.message),
        language: 'json',
        showLineNumbers: false,
        focusNode: focusNode,
      ),
    );
  }
}
