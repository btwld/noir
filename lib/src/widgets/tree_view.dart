// The item builder keeps `selected` positional beside the node it describes.
// ignore_for_file: avoid_positional_boolean_parameters

import 'dart:async';

import '../core/color.dart';
import '../core/input.dart';
import '../foundation/change_notifier.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/key.dart';
import '../framework/widget.dart';
import 'actions.dart';
import 'flexible.dart';
import 'icons.dart';
import 'input.dart' show ValueChanged;
import 'intents.dart';
import 'list_view.dart';
import 'row_column.dart';
import 'shortcuts.dart';
import 'sized_box.dart';
import 'text.dart';
import 'text_style.dart';
import 'theme.dart';
import 'viewport.dart';

/// One immutable value in a [TreeView] hierarchy.
///
/// IDs are caller-owned equality keys and must be unique across every node
/// supplied to one [TreeViewController]. Values do not have to be unique.
/// Use [TreeNode.branch] for an expandable node, including an empty branch;
/// [TreeNode.leaf] deliberately remains distinguishable from that state.
final class TreeNode<T> {
  /// Creates a node that cannot own children or expansion state.
  TreeNode.leaf({required this.id, required this.value})
    : _children = List<TreeNode<T>>.unmodifiable(const []),
      isBranch = false;

  /// Creates an expandable node and snapshots [children].
  TreeNode.branch({
    required this.id,
    required this.value,
    Iterable<TreeNode<T>> children = const [],
  }) : _children = List<TreeNode<T>>.unmodifiable(children),
       isBranch = true;

  /// Stable caller-provided equality key for this position in the tree.
  final Object id;

  /// Caller-owned value presented by a [TreeViewItemBuilder].
  final T value;

  final List<TreeNode<T>> _children;

  /// Immutable snapshot of this branch's children, or an empty list for a leaf.
  List<TreeNode<T>> get children => _children;

  /// Whether this node owns expansion state, even when [children] is empty.
  final bool isBranch;
}

/// Owns generic expansion and selection state for a [TreeView].
///
/// Construction and [updateRoots] validate the complete tree before
/// publishing any state. Flattening is iterative, so deeply nested input does
/// not consume the Dart call stack.
final class TreeViewController<T> extends ChangeNotifier {
  /// Creates a controller from snapshotted [roots].
  ///
  /// Missing or hidden [initialSelection] falls back to the first visible
  /// root. [initiallyExpanded] keeps only IDs that identify branches.
  TreeViewController({
    required List<TreeNode<T>> roots,
    Iterable<Object> initiallyExpanded = const [],
    Object? initialSelection,
  }) {
    _snapshot = _TreeSnapshot<T>.build(roots);
    _expanded = Set<Object>.of(initiallyExpanded)
      ..removeWhere((id) => !_snapshot.branchIds.contains(id));
    _publishVisible(_flatten(_snapshot, _expanded));
    _selectedId =
        initialSelection != null &&
            _visibleIndexById.containsKey(initialSelection)
        ? initialSelection
        : (_visibleEntries.isEmpty ? null : _visibleEntries.first.node.id);
  }

  late _TreeSnapshot<T> _snapshot;
  late Set<Object> _expanded;
  late List<_TreeEntry<T>> _visibleEntries;
  late List<TreeNode<T>> _visibleNodes;
  late Map<Object, int> _visibleIndexById;
  Object? _selectedId;

  /// Immutable root snapshot currently owned by this controller.
  List<TreeNode<T>> get roots => _snapshot.roots;

  /// Immutable preorder list after applying current expansion state.
  List<TreeNode<T>> get visibleNodes => _visibleNodes;

  /// Immutable snapshot of IDs currently marked expanded.
  Set<Object> get expandedIds => Set<Object>.unmodifiable(_expanded);

  /// ID of the selected visible node, or null when the tree is empty.
  Object? get selectedId => _selectedId;

  /// Selected visible node, or null when the tree is empty.
  TreeNode<T>? get selectedNode {
    final id = _selectedId;
    return id == null ? null : _snapshot.nodesById[id];
  }

  /// Selected index in [visibleNodes], or `-1` when the tree is empty.
  int get selectedIndex {
    final id = _selectedId;
    return id == null ? -1 : _visibleIndexById[id] ?? -1;
  }

  /// Whether the branch identified by [id] is marked expanded.
  bool isExpanded(Object id) => _expanded.contains(id);

  /// Selects a currently visible node.
  ///
  /// Returns true and notifies once when selection changes. Hidden, missing,
  /// and already-selected IDs are no-ops.
  bool select(Object id) {
    if (!_visibleIndexById.containsKey(id) || id == _selectedId) return false;
    _selectedId = id;
    notifyListeners();
    return true;
  }

  /// Applies [expanded] to a branch.
  ///
  /// Returns true and notifies once for an effective mutation. Missing IDs,
  /// leaves, and an already-matching state are no-ops. Collapsing an ancestor
  /// of the selection moves selection to its nearest visible ancestor.
  bool setExpanded(Object id, {required bool expanded}) {
    if (!_snapshot.branchIds.contains(id) ||
        _expanded.contains(id) == expanded) {
      return false;
    }

    if (expanded) {
      _expanded.add(id);
    } else {
      _expanded.remove(id);
    }
    _publishVisible(_flatten(_snapshot, _expanded));
    _repairSelectionAfterVisibilityChange();
    notifyListeners();
    return true;
  }

  /// Toggles one branch, returning false for a missing ID or leaf.
  bool toggle(Object id) {
    if (!_snapshot.branchIds.contains(id)) return false;
    return setExpanded(id, expanded: !_expanded.contains(id));
  }

  /// Atomically replaces the complete tree with a snapshot of [roots].
  ///
  /// Expansion survives only for IDs that remain branches. A selected node
  /// that stays visible is preserved; a surviving hidden node selects its
  /// nearest visible ancestor; a removed node selects the new visible row at
  /// the prior clamped index. An empty replacement clears selection.
  void updateRoots(List<TreeNode<T>> roots) {
    final candidate = _TreeSnapshot<T>.build(roots);
    final candidateExpanded = Set<Object>.of(_expanded)
      ..removeWhere((id) => !candidate.branchIds.contains(id));
    final candidateEntries = _flatten(candidate, candidateExpanded);
    final candidateIndexes = _indexVisible(candidateEntries);
    final previousIndex = selectedIndex;

    Object? candidateSelection;
    final selected = _selectedId;
    if (selected != null && candidateIndexes.containsKey(selected)) {
      candidateSelection = selected;
    } else if (selected != null && candidate.nodesById.containsKey(selected)) {
      candidateSelection = _nearestVisibleAncestor(
        selected,
        candidate,
        candidateIndexes,
      );
    } else if (candidateEntries.isNotEmpty) {
      final index = previousIndex.clamp(0, candidateEntries.length - 1);
      candidateSelection = candidateEntries[index].node.id;
    }

    if (_sameNodeSequence(_snapshot.roots, candidate.roots) &&
        _sameSet(_expanded, candidateExpanded) &&
        _selectedId == candidateSelection) {
      return;
    }

    _snapshot = candidate;
    _expanded = candidateExpanded;
    _publishVisible(candidateEntries, indexes: candidateIndexes);
    _selectedId = candidateSelection;
    notifyListeners();
  }

  void _repairSelectionAfterVisibilityChange() {
    if (_visibleEntries.isEmpty) {
      _selectedId = null;
      return;
    }
    final selected = _selectedId;
    if (selected != null && _visibleIndexById.containsKey(selected)) return;
    if (selected != null) {
      final ancestor = _nearestVisibleAncestor(
        selected,
        _snapshot,
        _visibleIndexById,
      );
      if (ancestor != null) {
        _selectedId = ancestor;
        return;
      }
    }
    _selectedId = _visibleEntries.first.node.id;
  }

  void _publishVisible(
    List<_TreeEntry<T>> entries, {
    Map<Object, int>? indexes,
  }) {
    _visibleEntries = List<_TreeEntry<T>>.unmodifiable(entries);
    _visibleNodes = List<TreeNode<T>>.unmodifiable(
      entries.map((entry) => entry.node),
    );
    _visibleIndexById = Map<Object, int>.unmodifiable(
      indexes ?? _indexVisible(entries),
    );
  }
}

/// Builds caller-owned content for one [TreeView] row.
///
/// [selected] is true for the controller's selected visible node. The tree
/// owns indentation, marker, and disclosure glyphs; this builder owns value
/// presentation and overflow behavior.
typedef TreeViewItemBuilder<T> =
    Widget Function(BuildContext context, TreeNode<T> node, bool selected);

/// A virtualized, keyboard- and pointer-navigable tree.
///
/// [TreeView] composes [ListView] and borrows its [controller], optional focus
/// node, and optional viewport controller. Up and Down move through visible
/// rows. Right expands a selected branch; Left collapses it or selects its
/// visible parent. Enter and primary click toggle branches or invoke
/// [onActivate] for leaves through the same activation path.
///
/// A null [onActivate] is the defined disabled leaf-action state: selection
/// remains available and activation is consumed without invoking a callback.
class TreeView<T> extends StatefulWidget {
  /// Creates a controlled tree over [controller].
  const TreeView({
    required this.controller,
    required this.itemBuilder,
    super.key,
    this.height = 8,
    this.indentation = 2,
    this.viewportController,
    this.focusNode,
    this.autofocus = false,
    this.showScrollIndicator = false,
    this.backgroundColor,
    this.selectedBackgroundColor,
    this.onSelectionChanged,
    this.onActivate,
  }) : assert(height >= 0),
       assert(indentation >= 0);

  /// Borrowed owner of roots, expansion, and selection.
  final TreeViewController<T> controller;

  /// Builds the caller-owned content portion of one visible row.
  final TreeViewItemBuilder<T> itemBuilder;

  /// Number of visible rows. Must be non-negative.
  final int height;

  /// Horizontal cells added for each depth level. Must be non-negative.
  final int indentation;

  /// Borrowed viewport owner, or null to let the internal [ListView] own one.
  final ViewportController? viewportController;

  /// Borrowed focus node, or null to let the internal [ListView] own one.
  final FocusNode? focusNode;

  /// Whether the internal list requests focus when first mounted.
  final bool autofocus;

  /// Whether the internal list reserves a scroll-indicator gutter.
  final bool showScrollIndicator;

  /// Fill delegated to the internal [ListView].
  final Color? backgroundColor;

  /// Focused selection fill delegated to the internal [ListView].
  final Color? selectedBackgroundColor;

  /// Reports selection changes caused by keyboard or primary-click input.
  ///
  /// Direct mutations of [controller] do not invoke this callback.
  final ValueChanged<TreeNode<T>>? onSelectionChanged;

  /// Invoked for leaf activation by Enter or primary click.
  ///
  /// Branches toggle instead. Null disables the leaf action without disabling
  /// selection or allowing the activation key to escape.
  final ValueChanged<TreeNode<T>>? onActivate;

  @override
  State<TreeView<T>> createState() => _TreeViewState<T>();
}

class _TreeViewState<T> extends State<TreeView<T>> {
  TreeNode<T>? _pendingActivationNode;

  @override
  void initState() {
    super.initState();
    _validateConfiguration();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(TreeView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _validateConfiguration();
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  void _validateConfiguration() {
    if (widget.height < 0) {
      throw ArgumentError.value(
        widget.height,
        'height',
        'must be non-negative',
      );
    }
    if (widget.indentation < 0) {
      throw ArgumentError.value(
        widget.indentation,
        'indentation',
        'must be non-negative',
      );
    }
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  _TreeEntry<T>? get _selectedEntry {
    final index = widget.controller.selectedIndex;
    if (index < 0 || index >= widget.controller._visibleEntries.length) {
      return null;
    }
    return widget.controller._visibleEntries[index];
  }

  bool _selectIndex(int index) {
    if (index < 0 || index >= widget.controller._visibleEntries.length) {
      return false;
    }
    final node = widget.controller._visibleEntries[index].node;
    if (!widget.controller.select(node.id)) return false;
    _pendingActivationNode = node;
    scheduleMicrotask(() {
      if (identical(_pendingActivationNode, node)) {
        _pendingActivationNode = null;
      }
    });
    widget.onSelectionChanged?.call(node);
    return true;
  }

  void _activateIndex(int index) {
    var node = _pendingActivationNode;
    _pendingActivationNode = null;
    if (node == null) {
      if (index < 0 || index >= widget.controller._visibleEntries.length) {
        return;
      }
      node = widget.controller._visibleEntries[index].node;
    }
    if (node.isBranch) {
      widget.controller.toggle(node.id);
    } else {
      widget.onActivate?.call(node);
    }
  }

  KeyEventResult _expandSelected() {
    final entry = _selectedEntry;
    if (entry == null || !entry.node.isBranch) {
      return KeyEventResult.ignored;
    }
    if (!widget.controller.isExpanded(entry.node.id)) {
      widget.controller.setExpanded(entry.node.id, expanded: true);
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _collapseOrSelectParent() {
    final entry = _selectedEntry;
    if (entry == null) return KeyEventResult.ignored;
    if (entry.node.isBranch && widget.controller.isExpanded(entry.node.id)) {
      widget.controller.setExpanded(entry.node.id, expanded: false);
      return KeyEventResult.handled;
    }
    final parentId = entry.parentId;
    if (parentId == null) return KeyEventResult.ignored;
    final parentIndex = widget.controller._visibleIndexById[parentId];
    if (parentIndex == null) return KeyEventResult.ignored;
    _selectIndex(parentIndex);
    return KeyEventResult.handled;
  }

  Widget _buildRow(BuildContext context, int index, bool selected) {
    final entry = widget.controller._visibleEntries[index];
    final palette = Theme.maybeOf(context) ?? ThemeData.dark;
    final chromeStyle = TextStyle(
      color: selected ? palette.selectedForeground : palette.text,
      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
    );
    final disclosure = entry.node.isBranch
        ? (widget.controller.isExpanded(entry.node.id)
              ? Icons.caretDown
              : Icons.caretRight)
        : ' ';
    return Row(
      key: ValueKey<Object>(entry.node.id),
      children: [
        SizedBox(width: entry.depth * widget.indentation),
        Text(selected ? Icons.chevronRight : ' ', style: chromeStyle),
        const SizedBox(width: 1),
        Text(disclosure, style: chromeStyle),
        const SizedBox(width: 1),
        Expanded(child: widget.itemBuilder(context, entry.node, selected)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: _treeShortcuts,
    child: Actions(
      actions: <Type, Action<Intent>>{
        _ExpandTreeIntent: CallbackAction<_ExpandTreeIntent>(
          (intent, context) => _expandSelected(),
        ),
        _CollapseTreeIntent: CallbackAction<_CollapseTreeIntent>(
          (intent, context) => _collapseOrSelectParent(),
        ),
      },
      child: ListView(
        itemCount: widget.controller._visibleEntries.length,
        height: widget.height,
        controller: widget.viewportController,
        selectedIndex: widget.controller.selectedIndex < 0
            ? 0
            : widget.controller.selectedIndex,
        showScrollIndicator: widget.showScrollIndicator,
        backgroundColor: widget.backgroundColor,
        selectedBackgroundColor: widget.selectedBackgroundColor,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onChanged: _selectIndex,
        onSelect: _activateIndex,
        itemBuilder: _buildRow,
      ),
    ),
  );

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }
}

const Map<ShortcutActivator, Intent> _treeShortcuts = {
  SingleActivator(LogicalKeyboardKey.arrowRight): _ExpandTreeIntent(),
  SingleActivator(LogicalKeyboardKey.arrowLeft): _CollapseTreeIntent(),
};

class _ExpandTreeIntent extends Intent {
  const _ExpandTreeIntent();
}

class _CollapseTreeIntent extends Intent {
  const _CollapseTreeIntent();
}

final class _TreeSnapshot<T> {
  const _TreeSnapshot({
    required this.roots,
    required this.nodesById,
    required this.parentById,
    required this.depthById,
    required this.branchIds,
  });

  factory _TreeSnapshot.build(List<TreeNode<T>> roots) {
    final rootSnapshot = List<TreeNode<T>>.unmodifiable(roots);
    final nodes = <Object, TreeNode<T>>{};
    final parents = <Object, Object?>{};
    final depths = <Object, int>{};
    final branches = <Object>{};
    final pending = <_PendingTreeNode<T>>[];
    for (var index = rootSnapshot.length - 1; index >= 0; index--) {
      pending.add(_PendingTreeNode(rootSnapshot[index], null, 0));
    }

    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      final node = current.node;
      if (nodes.containsKey(node.id)) {
        throw ArgumentError(
          'Tree node IDs must be unique; duplicate ID: ${node.id}',
        );
      }
      nodes[node.id] = node;
      parents[node.id] = current.parentId;
      depths[node.id] = current.depth;
      if (!node.isBranch) continue;
      branches.add(node.id);
      for (var index = node.children.length - 1; index >= 0; index--) {
        pending.add(
          _PendingTreeNode(node.children[index], node.id, current.depth + 1),
        );
      }
    }

    return _TreeSnapshot<T>(
      roots: rootSnapshot,
      nodesById: Map<Object, TreeNode<T>>.unmodifiable(nodes),
      parentById: Map<Object, Object?>.unmodifiable(parents),
      depthById: Map<Object, int>.unmodifiable(depths),
      branchIds: Set<Object>.unmodifiable(branches),
    );
  }

  final List<TreeNode<T>> roots;
  final Map<Object, TreeNode<T>> nodesById;
  final Map<Object, Object?> parentById;
  final Map<Object, int> depthById;
  final Set<Object> branchIds;
}

final class _PendingTreeNode<T> {
  const _PendingTreeNode(this.node, this.parentId, this.depth);

  final TreeNode<T> node;
  final Object? parentId;
  final int depth;
}

final class _TreeEntry<T> {
  const _TreeEntry({
    required this.node,
    required this.depth,
    required this.parentId,
  });

  final TreeNode<T> node;
  final int depth;
  final Object? parentId;
}

List<_TreeEntry<T>> _flatten<T>(
  _TreeSnapshot<T> snapshot,
  Set<Object> expanded,
) {
  final result = <_TreeEntry<T>>[];
  final pending = <TreeNode<T>>[];
  for (var index = snapshot.roots.length - 1; index >= 0; index--) {
    pending.add(snapshot.roots[index]);
  }
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    result.add(
      _TreeEntry<T>(
        node: node,
        depth: snapshot.depthById[node.id]!,
        parentId: snapshot.parentById[node.id],
      ),
    );
    if (!node.isBranch || !expanded.contains(node.id)) continue;
    for (var index = node.children.length - 1; index >= 0; index--) {
      pending.add(node.children[index]);
    }
  }
  return result;
}

Map<Object, int> _indexVisible<T>(List<_TreeEntry<T>> entries) => {
  for (var index = 0; index < entries.length; index++)
    entries[index].node.id: index,
};

Object? _nearestVisibleAncestor<T>(
  Object id,
  _TreeSnapshot<T> snapshot,
  Map<Object, int> visibleIndexes,
) {
  var current = snapshot.parentById[id];
  while (current != null) {
    if (visibleIndexes.containsKey(current)) return current;
    current = snapshot.parentById[current];
  }
  return null;
}

bool _sameNodeSequence<T>(List<TreeNode<T>> a, List<TreeNode<T>> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (!identical(a[index], b[index])) return false;
  }
  return true;
}

bool _sameSet(Set<Object> a, Set<Object> b) {
  if (a.length != b.length) return false;
  return a.every(b.contains);
}
