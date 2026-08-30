import 'dart:async';

import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';

void main() => runTuiApp(const FilePickerDemoApp(), enableMouse: true);

/// One deterministic file or directory in the example-owned project tree.
final class DemoFileNode {
  const DemoFileNode({required this.name, this.preview});

  final String name;
  final String? preview;
}

TreeNode<DemoFileNode> _directory(
  String path,
  String name, {
  required List<TreeNode<DemoFileNode>> children,
}) => TreeNode<DemoFileNode>.branch(
  id: path,
  value: DemoFileNode(name: name),
  children: children,
);

TreeNode<DemoFileNode> _file(String path, String name, String preview) =>
    TreeNode<DemoFileNode>.leaf(
      id: path,
      value: DemoFileNode(name: name, preview: preview),
    );

final _demoProject = <TreeNode<DemoFileNode>>[
  _directory(
    'lib',
    'lib',
    children: [
      _directory(
        'lib/src',
        'src',
        children: [
          _directory(
            'lib/src/app',
            'app',
            children: [
              _file(
                'lib/src/app/tui_binding.dart',
                'tui_binding.dart',
                'Owns the frame lifecycle, input manager, and root terminal constraints.',
              ),
            ],
          ),
          _directory(
            'lib/src/widgets',
            'widgets',
            children: [
              _file(
                'lib/src/widgets/menu_anchor.dart',
                'menu_anchor.dart',
                'Anchors an overlay surface to a launcher and restores focus on close.',
              ),
              _file(
                'lib/src/widgets/overlay.dart',
                'overlay.dart',
                'Hosts logical descendants above the application through the root overlay.',
              ),
            ],
          ),
        ],
      ),
      _file(
        'lib/noir.dart',
        'noir.dart',
        "Exports Noir's supported high-level application and widget surface.",
      ),
    ],
  ),
  _directory(
    'test',
    'test',
    children: [
      _file(
        'test/widget_test.dart',
        'widget_test.dart',
        'Exercises layout, input, and captured terminal cells.',
      ),
    ],
  ),
  _directory(
    'example',
    'example',
    children: [
      _file(
        'example/main.dart',
        'main.dart',
        'The canonical minimal Noir application entry point.',
      ),
    ],
  ),
  _file(
    'README.md',
    'README.md',
    'Package installation, supported surfaces, and terminal guidance.',
  ),
];

/// A split tree and preview presented inside the shared modal composition.
class FilePickerDemoApp extends StatefulWidget {
  const FilePickerDemoApp({super.key});

  @override
  State<FilePickerDemoApp> createState() => _FilePickerDemoAppState();
}

class _FilePickerDemoAppState extends State<FilePickerDemoApp> {
  final _modal = ModalController();
  final _launcherFocus = FocusNode(debugLabel: 'open-file-launcher');
  final _treeFocus = FocusNode(debugLabel: 'project-tree');
  final _cancelFocus = FocusNode(debugLabel: 'cancel-file-picker');
  final _openFocus = FocusNode(debugLabel: 'open-selected-file');
  late final TreeViewController<DemoFileNode> _tree;

  var _openedPath = 'No file opened.';

  @override
  void initState() {
    super.initState();
    _tree = TreeViewController<DemoFileNode>(
      roots: _demoProject,
      initiallyExpanded: const {'lib', 'lib/src', 'lib/src/widgets'},
      initialSelection: 'lib/src/widgets/menu_anchor.dart',
    )..addListener(_handleChanged);
    _treeFocus.addListener(_handleChanged);
    Timer.run(() {
      if (mounted) _modal.open();
    });
  }

  @override
  void dispose() {
    _tree
      ..removeListener(_handleChanged)
      ..dispose();
    _treeFocus
      ..removeListener(_handleChanged)
      ..dispose();
    _launcherFocus.dispose();
    _cancelFocus.dispose();
    _openFocus.dispose();
    super.dispose();
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  void _openPicker() => _modal.open();

  void _closePicker() => _modal.close();

  void _openSelected() {
    final selected = _tree.selectedNode;
    if (selected == null) return;
    _openNode(selected);
  }

  void _openNode(TreeNode<DemoFileNode> node) {
    if (node.isBranch) return;
    setState(() => _openedPath = 'Opened ${node.id}');
    _closePicker();
  }

  @override
  Widget build(BuildContext context) => Modal(
    controller: _modal,
    initialFocusNode: _treeFocus,
    modalBuilder: _buildPicker,
    child: DemoScaffold(
      title: 'Editor workspace',
      hint: 'Choose a project file without leaving the current screen.',
      child: Panel(
        title: 'Current file',
        child: Row(
          spacing: 1,
          children: [
            Expanded(child: Text(_openedPath)),
            Button(
              key: const ValueKey<String>('open-file-picker'),
              label: 'Open a file',
              focusNode: _launcherFocus,
              autofocus: true,
              onPressed: _openPicker,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildPicker(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _tree.selectedNode;
    final selectedPath = selected == null ? null : selected.id as String;
    return Panel(
      title: 'Open file',
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 1,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 11,
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _treeFocus.hasFocus ? '› Project' : 'Project',
                        style: TextStyle(
                          color: _treeFocus.hasFocus
                              ? theme.accent
                              : theme.textMuted,
                          fontWeight: _treeFocus.hasFocus
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      TreeView<DemoFileNode>(
                        key: const ValueKey<String>('file-tree'),
                        controller: _tree,
                        itemBuilder: _buildTreeRow,
                        height: 10,
                        focusNode: _treeFocus,
                        showScrollIndicator: true,
                        backgroundColor: Color.transparent,
                        onActivate: _openNode,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 11, child: Divider(axis: Axis.vertical)),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.only(left: 1),
                    child: Column(
                      spacing: 1,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Preview',
                          style: TextStyle(color: theme.textMuted),
                        ),
                        Text(
                          selectedPath ?? 'No selection',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          selected?.value.preview ??
                              'Expand a folder or choose a file to preview it.',
                          maxLines: 7,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: theme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            selectedPath ?? 'No project entries',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.textMuted),
          ),
          Row(
            spacing: 1,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Button(
                key: const ValueKey<String>('cancel-file-picker'),
                label: 'Cancel',
                focusNode: _cancelFocus,
                color: theme.surfaceVariant,
                textColor: theme.text,
                onPressed: _closePicker,
              ),
              Button(
                key: const ValueKey<String>('open-selected-file'),
                label: 'Open',
                focusNode: _openFocus,
                onPressed: selected == null || selected.isBranch
                    ? null
                    : _openSelected,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTreeRow(
    BuildContext context,
    TreeNode<DemoFileNode> node,
    bool selected,
  ) {
    final theme = Theme.of(context);
    final color = selected ? theme.selectedForeground : theme.text;
    return Container(
      padding: const EdgeInsets.only(right: 1),
      child: Text(
        node.value.name,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
