// The row builder takes `selected` positionally, beside the positional
// `index`: a row builder reads as a coordinate list, not a config object.
// ignore_for_file: avoid_positional_boolean_parameters

import 'dart:math' as math;

import '../core/color.dart';
import '../core/input.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import 'actions.dart';
import 'container.dart';
import 'flexible.dart';
import 'focus.dart';
import 'focus_node_owner_mixin.dart';
import 'input.dart';
import 'intents.dart';
import 'pointer_listener.dart';
import 'row_column.dart';
import 'shortcuts.dart';
import 'sized_box.dart';
import 'text.dart';
import 'text_style.dart';
import 'theme.dart';
import 'viewport.dart';

/// Signature for building one row of a [ListView].
///
/// [index] is the position in the full list, not in the visible window, and
/// [selected] is true only for the highlighted row of a selectable list.
typedef ListViewItemBuilder =
    Widget Function(BuildContext context, int index, bool selected);

/// A vertically scrolling list that builds only the rows currently on screen.
///
/// Unlike wrapping a `Column` in a `ScrollBox`, this widget never inflates the
/// off-screen rows: it asks [itemBuilder] only for the half-open window
/// `[scrollOffset, scrollOffset + visibleRows)`, so a list of a million items
/// costs the same as a list of ten. That is the whole reason it exists — a
/// `ScrollBox` would have to lay out every child to know its scroll extent.
///
/// The list has two modes, chosen by [selectedIndex]:
///
/// - **Selectable** ([selectedIndex] is non-null): arrows, `j`/`k`, PageUp,
///   PageDown, Home, and End move a highlight, which auto-scrolls to stay in
///   view. Enter or a left click confirms it. [onChanged] reports the moved
///   highlight and [onSelect] reports a confirmation.
/// - **Plain scroll** ([selectedIndex] is null): the same keys move the window
///   directly and no row is highlighted.
///
/// The mouse wheel scrolls the window in both modes without moving the
/// highlight.
///
/// The list occupies exactly [height] rows. A parent that offers fewer rows
/// clips the overflow rather than shrinking the window, so give the list a
/// height its parent can honor.
///
/// Rows are rebuilt as the window moves, so give each row a stable
/// `key: ValueKey(id)` when it owns `State` that must survive scrolling.
class ListView extends StatefulWidget {
  /// Configures a windowed list of [itemCount] rows, selectable when
  /// [selectedIndex] is non-null.
  const ListView({
    required this.itemCount,
    required this.itemBuilder,
    super.key,
    this.itemExtent = 1,
    this.height = 8,
    this.controller,
    this.selectedIndex,
    this.showScrollIndicator = false,
    this.backgroundColor,
    this.selectedBackgroundColor,
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.onSelect,
  }) : assert(itemCount >= 0),
       assert(itemExtent >= 1),
       assert(height >= 0);

  /// Total number of rows in the list.
  final int itemCount;

  /// Builds the row at a given index; called only for visible rows.
  final ListViewItemBuilder itemBuilder;

  /// Rows of terminal height occupied by each item.
  final int itemExtent;

  /// Rows of terminal height occupied by the whole list.
  final int height;

  /// Scroll position shared with the caller. One is created internally when
  /// null; a supplied controller is not disposed by this widget.
  final ViewportController? controller;

  /// Index highlighted when the list is first built, or null for a list with
  /// no selection. A later change to this value moves the highlight.
  final int? selectedIndex;

  /// Whether to reserve the last column for scroll-direction arrows.
  final bool showScrollIndicator;

  /// Fill painted behind the whole list. Falls back to [ThemeData.surface]
  /// under a [Theme]; with neither, the list paints no fill. Pass
  /// [Color.transparent] for an explicitly unfilled list inside a themed
  /// subtree.
  final Color? backgroundColor;

  /// Fill painted behind the highlighted row. Falls back to
  /// [ThemeData.selectedBackground].
  final Color? selectedBackgroundColor;

  /// Focus node controlling this list's keyboard input. One is created if null.
  final FocusNode? focusNode;

  /// Whether this widget requests focus when first mounted.
  final bool autofocus;

  /// Called with the new index whenever the highlight moves. Never called in
  /// plain-scroll mode.
  final ValueChanged<int>? onChanged;

  /// Called with the highlighted index when the user presses Enter or clicks a
  /// row. Never called in plain-scroll mode.
  final ValueChanged<int>? onSelect;

  @override
  State<ListView> createState() => _ListViewState();
}

class _ListViewState extends State<ListView>
    with FocusNodeOwnerStateMixin<ListView> {
  late ViewportController _viewport;
  late bool _ownsViewport;
  int _highlighted = 0;

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  bool get _selectable => widget.selectedIndex != null;

  int get _visibleRows => widget.height ~/ widget.itemExtent;

  int get _maxIndex => widget.itemCount == 0 ? 0 : widget.itemCount - 1;

  @override
  void initState() {
    super.initState();
    _highlighted = (widget.selectedIndex ?? 0).clamp(0, _maxIndex);
    _viewport = widget.controller ?? ViewportController();
    _ownsViewport = widget.controller == null;
    _adoptViewport();
  }

  /// Brings a just-installed controller in line with this list, then starts
  /// listening. Positioning first matters: the notification would arrive
  /// before the list has ever built and only schedule a redundant rebuild.
  void _adoptViewport() {
    _syncViewportExtents();
    _viewport
      ..ensureVisible(_highlighted, _highlighted + 1)
      ..addListener(_handleViewportChanged);
  }

  @override
  void didUpdateWidget(ListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
    if (!identical(oldWidget.controller, widget.controller)) {
      _viewport.removeListener(_handleViewportChanged);
      if (_ownsViewport) _viewport.dispose();
      // A fresh controller starts at offset zero and knows nothing about the
      // highlight, so adopt it exactly as initState would.
      _viewport = widget.controller ?? ViewportController();
      _ownsViewport = widget.controller == null;
      _adoptViewport();
    }
    _syncViewportExtents();
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _highlighted = (widget.selectedIndex ?? 0).clamp(0, _maxIndex);
      _viewport.ensureVisible(_highlighted, _highlighted + 1);
    } else if (widget.itemCount != oldWidget.itemCount) {
      _highlighted = _highlighted.clamp(0, _maxIndex);
      _viewport.ensureVisible(_highlighted, _highlighted + 1);
    }
  }

  @override
  void dispose() {
    _viewport.removeListener(_handleViewportChanged);
    if (_ownsViewport) _viewport.dispose();
    super.dispose();
  }

  void _syncViewportExtents() {
    _viewport
      ..contentExtent = widget.itemCount
      ..viewportExtent = _visibleRows;
  }

  void _handleViewportChanged() {
    if (mounted) setState(() {});
  }

  void _setHighlighted(int index) {
    if (widget.itemCount == 0) return;
    final next = index.clamp(0, _maxIndex);
    if (next == _highlighted) return;
    setState(() {
      _highlighted = next;
      _viewport.ensureVisible(_highlighted, _highlighted + 1);
    });
    widget.onChanged?.call(_highlighted);
  }

  /// Reports the highlighted row. A plain-scroll list has no highlight, so
  /// there is nothing to confirm and Enter is left for an ancestor to handle.
  KeyEventResult _confirm() {
    if (!_selectable) return KeyEventResult.ignored;
    if (widget.itemCount == 0) return KeyEventResult.ignored;
    widget.onSelect?.call(_highlighted);
    return KeyEventResult.handled;
  }

  /// Applies [target] to whichever position this list owns: the highlight in a
  /// selectable list, the window offset in a plain one. Both clamp internally,
  /// so callers never have to know which mode they are in.
  KeyEventResult _jumpTo(int target) {
    if (_selectable) {
      _setHighlighted(target);
    } else {
      _viewport.jumpTo(target);
    }
    return KeyEventResult.handled;
  }

  /// Moves by [rows] from whichever position this list owns.
  KeyEventResult _moveBy(int rows) => _jumpTo(
    _selectable ? _highlighted + rows : _viewport.scrollOffset + rows,
  );

  int get _pageRows => _visibleRows > 0 ? _visibleRows : 1;

  Map<Type, Action<Intent>> get _actions => {
    MoveSelectionUpIntent: CallbackAction<MoveSelectionUpIntent>(
      (intent, context) => _moveBy(-1),
    ),
    MoveSelectionDownIntent: CallbackAction<MoveSelectionDownIntent>(
      (intent, context) => _moveBy(1),
    ),
    MoveSelectionPageUpIntent: CallbackAction<MoveSelectionPageUpIntent>(
      (intent, context) => _moveBy(-_pageRows),
    ),
    MoveSelectionPageDownIntent: CallbackAction<MoveSelectionPageDownIntent>(
      (intent, context) => _moveBy(_pageRows),
    ),
    MoveSelectionFirstIntent: CallbackAction<MoveSelectionFirstIntent>(
      (intent, context) => _jumpTo(0),
    ),
    MoveSelectionLastIntent: CallbackAction<MoveSelectionLastIntent>(
      (intent, context) => _jumpTo(_maxIndex),
    ),
    ActivateIntent: CallbackAction<ActivateIntent>(
      (intent, context) => _confirm(),
    ),
  };

  // Deliberately the same activator set as Select, so a list and a selector
  // never disagree about what ArrowDown or PageUp does.
  static const Map<ShortcutActivator, Intent> _shortcuts = {
    SingleActivator(LogicalKeyboardKey.arrowUp): MoveSelectionUpIntent(),
    CharacterActivator('k'): MoveSelectionUpIntent(),
    SingleActivator(LogicalKeyboardKey.arrowDown): MoveSelectionDownIntent(),
    CharacterActivator('j'): MoveSelectionDownIntent(),
    SingleActivator(LogicalKeyboardKey.pageUp): MoveSelectionPageUpIntent(),
    SingleActivator(LogicalKeyboardKey.pageDown): MoveSelectionPageDownIntent(),
    SingleActivator(LogicalKeyboardKey.home): MoveSelectionFirstIntent(),
    SingleActivator(LogicalKeyboardKey.end): MoveSelectionLastIntent(),
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  };

  void _handlePointerDown(MouseEvent event) {
    if (event.button != MouseButton.left) return;
    if (!focusNode.hasFocus) focusNode.requestFocus();
    if (!_selectable) return;
    final row = event.localPosition.dy ~/ widget.itemExtent;
    if (row < 0 || row >= _visibleRows) return;
    final index = _viewport.scrollOffset + row;
    if (index > _maxIndex) return;
    _setHighlighted(index);
    _confirm();
  }

  void _handlePointerScroll(MouseEvent event) {
    final scroll = event.scroll;
    if (scroll == null) return;
    final sign = switch (scroll.direction) {
      MouseScrollDirection.up => -1,
      MouseScrollDirection.down => 1,
      MouseScrollDirection.left || MouseScrollDirection.right => 0,
    };
    if (sign == 0) return;
    if (_viewport.jumpTo(_viewport.scrollOffset + sign * scroll.magnitude)) {
      event.consume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.maybeOf(context);
    final palette = theme ?? ThemeData.dark;
    // `theme?.surface`, not `palette.surface`: no ancestor Theme has to keep
    // meaning "no fill", which no color can express.
    final background = widget.backgroundColor ?? theme?.surface;
    final selectedBackground =
        widget.selectedBackgroundColor ?? palette.selectedBackground;

    final start = _viewport.scrollOffset;
    final end = math.min(widget.itemCount, start + _visibleRows);

    Widget rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = start; index < end; index++)
          SizedBox(
            height: widget.itemExtent,
            child: _selectable && index == _highlighted
                ? Container(
                    color: selectedBackground,
                    child: widget.itemBuilder(context, index, true),
                  )
                : widget.itemBuilder(context, index, false),
          ),
      ],
    );

    if (widget.showScrollIndicator) {
      rows = Row(
        children: [
          Expanded(child: rows),
          SizedBox(
            width: 1,
            child: Column(
              children: [
                for (var row = 0; row < _visibleRows; row++)
                  Text(
                    _indicatorGlyph(row),
                    style: TextStyle(color: palette.text),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    Widget list = SizedBox(height: widget.height, child: rows);
    if (background != null) {
      list = Container(color: background, child: list);
    }

    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions,
        child: Focus(
          focusNode: focusNode,
          autofocus: widget.autofocus,
          child: PointerListener(
            onPointerDown: _handlePointerDown,
            onPointerScroll: _handlePointerScroll,
            child: list,
          ),
        ),
      ),
    );
  }

  /// Arrow for one row of the indicator gutter. The bottom row wins when the
  /// list is only one row tall and can scroll both ways.
  String _indicatorGlyph(int row) {
    final isLast = row == _visibleRows - 1;
    if (isLast && _viewport.scrollOffset < _viewport.maxScrollOffset) {
      return '▼';
    }
    if (row == 0 && _viewport.scrollOffset > 0) return '▲';
    return ' ';
  }
}
