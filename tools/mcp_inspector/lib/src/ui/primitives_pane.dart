import 'package:noir/noir.dart';

import '../model/inspector_controller.dart';

/// Greatest number of rows the primitives list shows at once.
///
/// `ListView` occupies exactly its `height`, and `package:noir/noir.dart`
/// exposes no terminal size to an application, so this budget is chosen for
/// the 60x18 floor the drive checks use.
const primitiveListRows = 12;

/// The left pane: the rows of the active tab.
///
/// Moving the highlight selects the row, so the detail pane always describes
/// what the list shows. Enter reports through [onActivate].
class PrimitivesPane extends StatelessWidget {
  /// Creates the pane over [controller].
  const PrimitivesPane({
    required this.controller,
    required this.focusNode,
    required this.onActivate,
    super.key,
  });

  /// The state owner this pane reads and selects into.
  final InspectorController controller;

  /// The node that owns keyboard focus for the list.
  final FocusNode focusNode;

  /// Called when the user presses Enter or clicks a row.
  final void Function(int index) onActivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = controller.itemCount;
    return Panel(
      title: _title,
      focused: focusNode.hasFocus,
      width: 26,
      child: count == 0
          ? Text(_empty, style: TextStyle(color: theme.textMuted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ListView(
                  itemCount: count,
                  height: count < primitiveListRows ? count : primitiveListRows,
                  selectedIndex: controller.selectedIndex,
                  focusNode: focusNode,
                  showScrollIndicator: count > primitiveListRows,
                  autofocus: true,
                  itemBuilder: _buildRow,
                  onChanged: controller.select,
                  onSelect: onActivate,
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
    );
  }

  // `Align` fills the row, so the list paints its highlight across the whole
  // pane rather than only behind the label.
  Widget _buildRow(BuildContext context, int index, bool selected) => Align(
    key: ValueKey<String>(_rowKey(index)),
    alignment: Alignment.centerLeft,
    child: Text(
      _labelAt(index),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    ),
  );

  String get _title => switch (controller.activeTab) {
    InspectorTab.tools => 'Tools',
    InspectorTab.resources => 'Resources',
    InspectorTab.prompts => 'Prompts',
    InspectorTab.protocol => 'Protocol',
    InspectorTab.console => 'Console',
  };

  String get _empty => switch (controller.activeTab) {
    InspectorTab.tools => 'No tools',
    InspectorTab.resources => 'No resources',
    InspectorTab.prompts => 'No prompts',
    InspectorTab.protocol => 'No messages yet',
    InspectorTab.console => 'No output yet',
  };

  String _labelAt(int index) => switch (controller.activeTab) {
    InspectorTab.tools => controller.tools[index].name,
    InspectorTab.resources => controller.resources[index].uri,
    InspectorTab.prompts => controller.prompts[index].name,
    InspectorTab.protocol => controller.protocolEntries[index].label,
    InspectorTab.console => controller.consoleLines[index],
  };

  String _rowKey(int index) => switch (controller.activeTab) {
    InspectorTab.tools => 'primitive:${controller.tools[index].name}',
    InspectorTab.resources => 'primitive:${controller.resources[index].uri}',
    InspectorTab.prompts => 'primitive:${controller.prompts[index].name}',
    InspectorTab.protocol =>
      'protocol:${controller.protocolEntries[index].sequence}',
    InspectorTab.console => 'console:$index',
  };
}
