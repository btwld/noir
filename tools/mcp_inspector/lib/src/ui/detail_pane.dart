import 'package:noir/noir.dart';

import '../model/inspector_controller.dart';
import '../session/mcp_session.dart';
import 'form_view.dart';

/// The right pane for the tools, resources, and prompts tabs.
///
/// It shows the selected primitive's description, its generated form, the Run
/// action, and the last result.
class DetailPane extends StatelessWidget {
  /// Creates the pane over [controller].
  const DetailPane({
    required this.controller,
    required this.focusNodeFor,
    required this.runFocusNode,
    required this.resultFocusNode,
    required this.schemaFocusNode,
    required this.onChanged,
    super.key,
  });

  /// The state owner this pane reads.
  final InspectorController controller;

  /// Supplies the focus node for the form field named by its argument.
  final FocusNode Function(String name) focusNodeFor;

  /// The node that owns keyboard focus for the Run action.
  final FocusNode runFocusNode;

  /// The node that owns keyboard focus for the result view.
  final FocusNode resultFocusNode;

  /// The node that owns keyboard focus for the raw-schema view.
  final FocusNode schemaFocusNode;

  /// Called after a control changes a value, so the owner can rebuild.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _title;
    if (title == null) {
      return Panel(
        title: 'Detail',
        child: Text(
          'Select a row on the left.',
          style: TextStyle(color: theme.textMuted),
        ),
      );
    }
    final form = controller.form;
    final schemaText = controller.visibleSchemaText;
    return Panel(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 1,
        children: <Widget>[
          Text(
            _description ?? 'No description',
            style: TextStyle(color: theme.textMuted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          // The schema takes the form's place, not the whole pane, so the
          // reader keeps the Run action and the last result while reading it.
          // It outweighs the result three to one: a schema worth opening is
          // longer than the pane, and the result below it is usually empty.
          if (schemaText != null)
            Expanded(
              flex: 3,
              child: Panel(
                title: 'Schema',
                focused: schemaFocusNode.hasFocus,
                child: CodeView(
                  key: const ValueKey<String>('schema'),
                  code: schemaText,
                  showLineNumbers: false,
                  focusNode: schemaFocusNode,
                  // The view takes focus as it mounts, the same way each tab
                  // region does. That keeps a node focused across the swap and
                  // makes the schema scrollable without hunting for it.
                  autofocus: true,
                ),
              ),
            )
          // The form owns scrolling inside this bound; Run and the result
          // retain their own space while focus reveals each field.
          else if (form != null)
            Flexible(
              child: FormView(
                model: form,
                focusNodeFor: focusNodeFor,
                onChanged: onChanged,
              ),
            ),
          Row(
            spacing: 1,
            children: <Widget>[
              // The button stays enabled while a request is in flight. A
              // disabled Button drops primary focus, and every `Shortcuts`
              // binding stops working while no node is focused.
              // `InspectorController.run` already ignores a second call.
              Button(
                key: const ValueKey<String>('run'),
                label: _runLabel,
                focusNode: runFocusNode,
                onPressed: controller.run,
              ),
              if (controller.isRunning) Spinner(color: theme.accent),
            ],
          ),
          Expanded(child: _result(context)),
        ],
      ),
    );
  }

  Widget _result(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = controller.outcome;
    if (outcome == null) {
      return Panel(
        title: 'Result',
        child: Text(
          'Press $_runLabel or Ctrl+R to send the request.',
          style: TextStyle(color: theme.textMuted),
        ),
      );
    }
    return Panel(
      title: 'Result (${outcome.elapsed.inMilliseconds} ms)',
      focused: resultFocusNode.hasFocus,
      borderColor: outcome.isError ? theme.danger : null,
      child: CodeView(
        key: const ValueKey<String>('result'),
        code: outcome.text,
        showLineNumbers: false,
        focusNode: resultFocusNode,
        style: outcome.isError ? TextStyle(color: theme.danger) : null,
      ),
    );
  }

  String get _runLabel => switch (controller.activeTab) {
    InspectorTab.resources => 'Read',
    InspectorTab.prompts => 'Get',
    _ => 'Run',
  };

  String? get _title => switch (controller.activeTab) {
    InspectorTab.tools => controller.selectedTool?.name,
    InspectorTab.resources => controller.selectedResource?.name,
    InspectorTab.prompts => controller.selectedPrompt?.name,
    InspectorTab.protocol || InspectorTab.console => null,
  };

  String? get _description => switch (controller.activeTab) {
    InspectorTab.tools => controller.selectedTool?.description,
    InspectorTab.resources => _resourceDescription(controller.selectedResource),
    InspectorTab.prompts => controller.selectedPrompt?.description,
    InspectorTab.protocol || InspectorTab.console => null,
  };

  static String? _resourceDescription(McpResourceInfo? resource) {
    if (resource == null) return null;
    final mimeType = resource.mimeType;
    final description = resource.description ?? resource.uri;
    return mimeType == null ? description : '$description  ($mimeType)';
  }
}
