import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';
import 'src/modal_overlay.dart';

void main() => runTuiApp(const FilePickerDemoApp(), enableMouse: true);

/// One deterministic file or directory in the example-owned project tree.
final class DemoFileNode {
  const DemoFileNode.file({required this.name, required this.preview})
    : children = null;

  const DemoFileNode.directory({required this.name, required this.children})
    : preview = null;

  final String name;
  final String? preview;
  final List<DemoFileNode>? children;

  bool get isDirectory => children != null;
}

/// A visible flattened row derived from a [DemoFileNode] tree.
final class DemoFileEntry {
  const DemoFileEntry({
    required this.node,
    required this.depth,
    required this.path,
    this.parentPath,
  });

  final DemoFileNode node;
  final int depth;
  final String path;
  final String? parentPath;
}

/// Owns expansion and selection while the ListView owns viewport mechanics.
final class FilePickerController extends ChangeNotifier {
  FilePickerController({
    required List<DemoFileNode> roots,
    Iterable<String> initiallyExpanded = const [],
    String? initialPath,
  }) : _roots = List<DemoFileNode>.unmodifiable(roots),
       _expanded = Set<String>.of(initiallyExpanded) {
    _rebuild(preferredPath: initialPath);
  }

  final List<DemoFileNode> _roots;
  final Set<String> _expanded;
  var _visible = const <DemoFileEntry>[];
  var _selectedIndex = 0;

  List<DemoFileEntry> get visibleEntries => _visible;
  int get selectedIndex => _selectedIndex;
  DemoFileEntry? get selectedEntry => _visible.isEmpty
      ? null
      : _visible[_selectedIndex.clamp(0, _visible.length - 1)];

  bool isExpanded(DemoFileEntry entry) => _expanded.contains(entry.path);

  void highlight(int index) {
    if (_visible.isEmpty) return;
    final next = index.clamp(0, _visible.length - 1);
    if (next == _selectedIndex) return;
    _selectedIndex = next;
    notifyListeners();
  }

  bool toggleHighlighted() {
    final entry = selectedEntry;
    if (entry == null || !entry.node.isDirectory) return false;
    if (!_expanded.remove(entry.path)) _expanded.add(entry.path);
    _rebuild(preferredPath: entry.path);
    notifyListeners();
    return true;
  }

  bool expandHighlighted() {
    final entry = selectedEntry;
    if (entry == null || !entry.node.isDirectory) return false;
    if (isExpanded(entry)) return true;
    _expanded.add(entry.path);
    _rebuild(preferredPath: entry.path);
    notifyListeners();
    return true;
  }

  bool collapseOrSelectParent() {
    final entry = selectedEntry;
    if (entry == null) return false;
    if (entry.node.isDirectory && _expanded.remove(entry.path)) {
      _rebuild(preferredPath: entry.path);
      notifyListeners();
      return true;
    }

    final parentPath = entry.parentPath;
    if (parentPath == null) return false;
    final parent = _visible.indexWhere((item) => item.path == parentPath);
    if (parent < 0) return false;
    _selectedIndex = parent;
    notifyListeners();
    return true;
  }

  void _rebuild({String? preferredPath}) {
    final flattened = <DemoFileEntry>[];

    void visit(DemoFileNode node, int depth, String? parentPath) {
      final path = parentPath == null ? node.name : '$parentPath/${node.name}';
      flattened.add(
        DemoFileEntry(
          node: node,
          depth: depth,
          path: path,
          parentPath: parentPath,
        ),
      );
      if (!node.isDirectory || !_expanded.contains(path)) return;
      for (final child in node.children!) {
        visit(child, depth + 1, path);
      }
    }

    for (final root in _roots) {
      visit(root, 0, null);
    }
    _visible = List<DemoFileEntry>.unmodifiable(flattened);
    if (_visible.isEmpty) {
      _selectedIndex = 0;
      return;
    }
    final preferred = preferredPath == null
        ? -1
        : _visible.indexWhere((entry) => entry.path == preferredPath);
    _selectedIndex = preferred >= 0
        ? preferred
        : _selectedIndex.clamp(0, _visible.length - 1);
  }
}

const _demoProject = <DemoFileNode>[
  DemoFileNode.directory(
    name: 'lib',
    children: [
      DemoFileNode.directory(
        name: 'src',
        children: [
          DemoFileNode.directory(
            name: 'app',
            children: [
              DemoFileNode.file(
                name: 'tui_binding.dart',
                preview:
                    'Owns the frame lifecycle, input manager, and root terminal constraints.',
              ),
            ],
          ),
          DemoFileNode.directory(
            name: 'widgets',
            children: [
              DemoFileNode.file(
                name: 'menu_anchor.dart',
                preview:
                    'Anchors an overlay surface to a launcher and restores focus on close.',
              ),
              DemoFileNode.file(
                name: 'overlay.dart',
                preview:
                    'Hosts logical descendants above the application through the root overlay.',
              ),
            ],
          ),
        ],
      ),
      DemoFileNode.file(
        name: 'noir.dart',
        preview:
            "Exports Noir's supported high-level application and widget surface.",
      ),
    ],
  ),
  DemoFileNode.directory(
    name: 'test',
    children: [
      DemoFileNode.file(
        name: 'widget_test.dart',
        preview: 'Exercises layout, input, and captured terminal cells.',
      ),
    ],
  ),
  DemoFileNode.directory(
    name: 'example',
    children: [
      DemoFileNode.file(
        name: 'main.dart',
        preview: 'The canonical minimal Noir application entry point.',
      ),
    ],
  ),
  DemoFileNode.file(
    name: 'README.md',
    preview: 'Package installation, supported surfaces, and terminal guidance.',
  ),
];

/// A split tree and preview presented inside the shared modal composition.
class FilePickerDemoApp extends StatefulWidget {
  const FilePickerDemoApp({super.key});

  @override
  State<FilePickerDemoApp> createState() => _FilePickerDemoAppState();
}

class _FilePickerDemoAppState extends State<FilePickerDemoApp> {
  final _overlay = OverlayPortalController(debugLabel: 'file-picker');
  final _launcherFocus = FocusNode(debugLabel: 'open-file-launcher');
  final _treeFocus = FocusNode(debugLabel: 'project-tree');
  final _cancelFocus = FocusNode(debugLabel: 'cancel-file-picker');
  final _openFocus = FocusNode(debugLabel: 'open-selected-file');
  late final FilePickerController _picker;
  late final DemoClosedLoopTraversalPolicy _dialogTraversal =
      DemoClosedLoopTraversalPolicy([_treeFocus, _cancelFocus, _openFocus]);

  var _openedPath = 'No file opened.';

  @override
  void initState() {
    super.initState();
    _picker = FilePickerController(
      roots: _demoProject,
      initiallyExpanded: const {'lib', 'lib/src', 'lib/src/widgets'},
      initialPath: 'lib/src/widgets/menu_anchor.dart',
    )..addListener(_handleChanged);
    _treeFocus.addListener(_handleChanged);
    _overlay.show();
  }

  @override
  void dispose() {
    _picker
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

  void _openPicker() => _overlay.show();

  void _closePicker() {
    _overlay.hide();
    if (_launcherFocus.isAttached && _launcherFocus.canRequestFocus) {
      _launcherFocus.requestFocus();
    }
  }

  void _openSelected() {
    final entry = _picker.selectedEntry;
    if (entry == null || entry.node.isDirectory) return;
    setState(() => _openedPath = 'Opened ${entry.path}');
    _closePicker();
  }

  KeyEventResult _handleTreeKeys(FocusNode node, KeyEvent event) {
    if (!event.isPress || !_treeFocus.hasFocus) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      return _picker.expandHighlighted()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      return _picker.collapseOrSelectParent()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => DemoModalOverlay(
    controller: _overlay,
    onDismiss: _closePicker,
    traversalPolicy: _dialogTraversal,
    dialog: Focus(
      canRequestFocus: false,
      onKeyEvent: _handleTreeKeys,
      child: _buildPicker(context),
    ),
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
    final selected = _picker.selectedEntry;
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
                      ListView(
                        key: const ValueKey<String>('file-tree'),
                        itemCount: _picker.visibleEntries.length,
                        height: 10,
                        selectedIndex: _picker.selectedIndex,
                        focusNode: _treeFocus,
                        autofocus: true,
                        showScrollIndicator: true,
                        backgroundColor: Color.transparent,
                        onChanged: _picker.highlight,
                        onSelect: (index) {
                          _picker.highlight(index);
                          _picker.toggleHighlighted();
                        },
                        itemBuilder: _buildTreeRow,
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
                          selected?.path ?? 'No selection',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          selected?.node.preview ??
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
            selected?.path ?? 'No project entries',
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
                onPressed: selected == null || selected.node.isDirectory
                    ? null
                    : _openSelected,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTreeRow(BuildContext context, int index, bool selected) {
    final theme = Theme.of(context);
    final entry = _picker.visibleEntries[index];
    final indent = List<String>.filled(entry.depth, '  ').join();
    final disclosure = entry.node.isDirectory
        ? (_picker.isExpanded(entry) ? Icons.caretDown : Icons.caretRight)
        : ' ';
    final color = selected ? theme.selectedForeground : theme.text;
    return Container(
      padding: const EdgeInsets.only(right: 1),
      child: Text(
        '${selected ? Icons.chevronRight : ' '} $indent$disclosure ${entry.node.name}',
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
