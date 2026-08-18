// ignore_for_file: avoid_setters_without_getters
import 'dart:math' as math;

import 'package:characters/characters.dart';

import '../core/color.dart';
import '../core/grapheme_metrics.dart';
import '../core/input.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/box.dart';
import '../rendering/object.dart';
import 'actions.dart';
import 'focus.dart';
import 'focus_node_owner_mixin.dart';
import 'intents.dart';
import 'pointer_listener.dart';
import 'shortcuts.dart';
import 'viewport.dart';

/// A single option in a [Select] list.
class SelectOption<T> {
  /// Stores the rendered [name], optional [description], and callback [value].
  const SelectOption({required this.name, this.description, this.value});

  /// The label rendered for this option.
  final String name;

  /// Optional secondary description rendered after the name.
  final String? description;

  /// The value associated with this option, returned via callbacks.
  final T? value;
}

/// Signature for callbacks invoked when the highlighted option changes.
typedef SelectChanged<T> = void Function(int index, SelectOption<T> option);

/// Signature for callbacks invoked when the user confirms a selection.
typedef SelectConfirmed<T> = void Function(int index, SelectOption<T> option);

/// A scrollable list-of-options selector, parity with OpenTUI-React `<select>`.
///
/// Behavior:
/// - Arrow keys / `j`/`k` move the highlight by one item and fire [onChanged].
/// - PageUp/Down move the highlight by the viewport row count (read from the
///   laid-out [RenderSelect], not a constructor-time constant).
/// - Home/End jump to bounds.
/// - Enter (or single mouse click on a row) confirms and fires [onSelect].
/// - When the list is taller than [height], the visible window auto-scrolls
///   via a shared [ViewportController] to keep the highlight in view.
class Select<T> extends StatefulWidget {
  /// Configures a focusable selector with a non-negative visible [height].
  const Select({
    required this.options,
    super.key,
    this.selectedIndex = 0,
    this.height = 8,
    this.showScrollIndicator = false,
    this.color = Color.white,
    this.backgroundColor,
    this.selectedBackgroundColor = const Color(0.2, 0.4, 0.8),
    this.selectedTextColor = Color.white,
    this.descriptionColor = const Color(0.6, 0.6, 0.6),
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.onSelect,
  }) : assert(height >= 0);

  /// Options displayed in the list.
  final List<SelectOption<T>> options;

  /// Index of the initially highlighted option.
  final int selectedIndex;

  /// Maximum number of visible option rows.
  final int height;

  /// Whether to render scroll-direction arrows in the last column when the list overflows.
  final bool showScrollIndicator;

  /// Foreground color of unselected option text.
  final Color color;

  /// Fill color behind the entire list. No fill when null.
  final Color? backgroundColor;

  /// Fill color behind the highlighted row.
  final Color selectedBackgroundColor;

  /// Foreground color of text on the highlighted row.
  final Color selectedTextColor;

  /// Color of the secondary description text on unhighlighted rows.
  final Color descriptionColor;

  /// Focus node controlling this widget's focus. One is created if null.
  final FocusNode? focusNode;

  /// Whether this widget requests focus when first mounted.
  final bool autofocus;

  /// Called when the highlighted option changes.
  final SelectChanged<T>? onChanged;

  /// Called when the user confirms the currently highlighted option.
  final SelectConfirmed<T>? onSelect;

  @override
  State<Select<T>> createState() => _SelectState<T>();
}

class _SelectLayoutMetrics {
  int? _lastCompletedRows;

  int? get lastCompletedRows => _lastCompletedRows;

  // A verb expresses one-way publication more clearly than a writable API.
  // ignore: use_setters_to_change_properties
  void publish(int rows) {
    _lastCompletedRows = rows;
  }
}

class _SelectState<T> extends State<Select<T>>
    with FocusNodeOwnerStateMixin<Select<T>> {
  late int _highlighted;
  late final ViewportController _viewport;
  final _SelectLayoutMetrics _layoutMetrics = _SelectLayoutMetrics();

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  void initState() {
    super.initState();
    _highlighted = widget.selectedIndex.clamp(0, _maxIndex);
    _viewport = ViewportController(
      contentExtent: widget.options.length,
      viewportExtent: widget.height,
    );
    _viewport.ensureVisible(_highlighted, _highlighted + 1);
  }

  @override
  void didUpdateWidget(Select<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
    _viewport.contentExtent = widget.options.length;
    // Don't fight ourselves: if the host hasn't laid us out yet, default to
    // the constructor hint. The render object reports the actual viewport
    // size after first paint via _refreshViewportFromLayout().
    if (_viewport.viewportExtent == 0) {
      _viewport.viewportExtent = widget.height;
    }
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _highlighted = widget.selectedIndex.clamp(0, _maxIndex);
      _viewport.ensureVisible(_highlighted, _highlighted + 1);
    } else if (widget.options.length != oldWidget.options.length) {
      _highlighted = _highlighted.clamp(0, _maxIndex);
      _viewport.ensureVisible(_highlighted, _highlighted + 1);
    }
  }

  int get _maxIndex => widget.options.isEmpty ? 0 : widget.options.length - 1;

  /// Read the painted option row count from the [RenderSelect] after layout.
  /// Tight root constraints may make the render box taller than the logical
  /// option viewport, so cap the page size at [widget.height].
  int _refreshViewportFromLayout() {
    final rows = _paintedViewportRows();
    _viewport.viewportExtent = rows;
    return rows;
  }

  int _paintedViewportRows() {
    final published = _layoutMetrics.lastCompletedRows;
    final laidOutRows = published != null && published > 0
        ? published
        : widget.height;
    return math.max(0, math.min(laidOutRows, widget.height));
  }

  void _move(int delta) {
    _setHighlighted(_highlighted + delta);
  }

  void _setHighlighted(int index) {
    if (widget.options.isEmpty) return;
    final next = index.clamp(0, _maxIndex);
    if (next == _highlighted) return;
    _refreshViewportFromLayout();
    setState(() {
      _highlighted = next;
      _viewport.ensureVisible(_highlighted, _highlighted + 1);
    });
    widget.onChanged?.call(_highlighted, widget.options[_highlighted]);
  }

  void _pageBy(int pages) {
    if (widget.options.isEmpty) return;
    final rows = _refreshViewportFromLayout();
    final delta = pages * (rows > 0 ? rows : widget.height);
    _setHighlighted(_highlighted + delta);
  }

  void _confirm() {
    if (widget.options.isEmpty) return;
    widget.onSelect?.call(_highlighted, widget.options[_highlighted]);
  }

  Map<Type, Action<Intent>> get _actions => {
    MoveSelectionUpIntent: CallbackAction<MoveSelectionUpIntent>((
      intent,
      context,
    ) {
      _move(-1);
      return KeyEventResult.handled;
    }),
    MoveSelectionDownIntent: CallbackAction<MoveSelectionDownIntent>((
      intent,
      context,
    ) {
      _move(1);
      return KeyEventResult.handled;
    }),
    MoveSelectionPageUpIntent: CallbackAction<MoveSelectionPageUpIntent>((
      intent,
      context,
    ) {
      _pageBy(-1);
      return KeyEventResult.handled;
    }),
    MoveSelectionPageDownIntent: CallbackAction<MoveSelectionPageDownIntent>((
      intent,
      context,
    ) {
      _pageBy(1);
      return KeyEventResult.handled;
    }),
    MoveSelectionFirstIntent: CallbackAction<MoveSelectionFirstIntent>((
      intent,
      context,
    ) {
      _setHighlighted(0);
      return KeyEventResult.handled;
    }),
    MoveSelectionLastIntent: CallbackAction<MoveSelectionLastIntent>((
      intent,
      context,
    ) {
      _setHighlighted(_maxIndex);
      return KeyEventResult.handled;
    }),
    ActivateIntent: CallbackAction<ActivateIntent>((intent, context) {
      _confirm();
      return KeyEventResult.handled;
    }),
  };

  Map<ShortcutActivator, Intent> get _shortcuts => const {
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
    if (!focusNode.hasFocus) {
      focusNode.requestFocus();
    }
    final localY = event.localPosition.dy;
    final rows = _paintedViewportRows();
    if (localY < 0 || localY >= rows) return;
    final index = _viewport.scrollOffset + localY;
    if (index < 0 || index > _maxIndex) return;
    _setHighlighted(index);
    _confirm();
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: _shortcuts,
    child: Actions(
      actions: _actions,
      child: Focus(
        focusNode: focusNode,
        autofocus: widget.autofocus,
        child: PointerListener(
          onPointerDown: _handlePointerDown,
          child: _SelectLeaf<T>(
            options: widget.options,
            highlighted: _highlighted,
            scrollOffset: _viewport.scrollOffset,
            height: widget.height,
            showScrollIndicator: widget.showScrollIndicator,
            color: widget.color,
            backgroundColor: widget.backgroundColor,
            selectedBackgroundColor: widget.selectedBackgroundColor,
            selectedTextColor: widget.selectedTextColor,
            descriptionColor: widget.descriptionColor,
            layoutMetrics: _layoutMetrics,
          ),
        ),
      ),
    ),
  );
}

class _SelectLeaf<T> extends RenderObjectWidget {
  const _SelectLeaf({
    required this.options,
    required this.highlighted,
    required this.scrollOffset,
    required this.height,
    required this.showScrollIndicator,
    required this.color,
    required this.backgroundColor,
    required this.selectedBackgroundColor,
    required this.selectedTextColor,
    required this.descriptionColor,
    required this.layoutMetrics,
  });

  final List<SelectOption<T>> options;
  final int highlighted;
  final int scrollOffset;
  final int height;
  final bool showScrollIndicator;
  final Color color;
  final Color? backgroundColor;
  final Color selectedBackgroundColor;
  final Color selectedTextColor;
  final Color descriptionColor;
  final _SelectLayoutMetrics layoutMetrics;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSelect<T>._forWidget(
        layoutMetrics: layoutMetrics,
        options: options,
        highlighted: highlighted,
        scrollOffset: scrollOffset,
        visibleRows: height,
        showScrollIndicator: showScrollIndicator,
        color: color,
        backgroundColor: backgroundColor,
        selectedBackgroundColor: selectedBackgroundColor,
        selectedTextColor: selectedTextColor,
        descriptionColor: descriptionColor,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderSelect<T> renderObject,
  ) {
    renderObject
      ..options = options
      ..highlighted = highlighted
      ..scrollOffset = scrollOffset
      ..visibleRows = height
      ..showScrollIndicator = showScrollIndicator
      ..color = color
      ..backgroundColor = backgroundColor
      ..selectedBackgroundColor = selectedBackgroundColor
      ..selectedTextColor = selectedTextColor
      ..descriptionColor = descriptionColor;
  }
}

/// RenderBox that paints a [Select] list. Validates visible rows during
/// construction and passively publishes the completed option-row count so
/// widget state can read it after layout; list painting never reads it.
class RenderSelect<T> extends RenderBox {
  /// Validates a non-negative [visibleRows] and snapshots list styling.
  RenderSelect({
    required List<SelectOption<T>> options,
    required int highlighted,
    required int scrollOffset,
    required int visibleRows,
    required bool showScrollIndicator,
    required Color color,
    required Color? backgroundColor,
    required Color selectedBackgroundColor,
    required Color selectedTextColor,
    required Color descriptionColor,
  }) : this._forWidget(
         layoutMetrics: null,
         options: options,
         highlighted: highlighted,
         scrollOffset: scrollOffset,
         visibleRows: visibleRows,
         showScrollIndicator: showScrollIndicator,
         color: color,
         backgroundColor: backgroundColor,
         selectedBackgroundColor: selectedBackgroundColor,
         selectedTextColor: selectedTextColor,
         descriptionColor: descriptionColor,
       );

  RenderSelect._forWidget({
    required _SelectLayoutMetrics? layoutMetrics,
    required List<SelectOption<T>> options,
    required int highlighted,
    required int scrollOffset,
    required int visibleRows,
    required bool showScrollIndicator,
    required Color color,
    required Color? backgroundColor,
    required Color selectedBackgroundColor,
    required Color selectedTextColor,
    required Color descriptionColor,
  }) : _layoutMetrics = layoutMetrics,
       _options = options,
       _highlighted = highlighted,
       _scrollOffset = scrollOffset,
       _visibleRows = visibleRows,
       _showScrollIndicator = showScrollIndicator,
       _color = color,
       _backgroundColor = backgroundColor,
       _selectedBackgroundColor = selectedBackgroundColor,
       _selectedTextColor = selectedTextColor,
       _descriptionColor = descriptionColor {
    requireNonNegativeExtent(_visibleRows, 'visibleRows');
  }

  final _SelectLayoutMetrics? _layoutMetrics;
  List<SelectOption<T>> _options;
  int _highlighted;
  int _scrollOffset;
  int _visibleRows;
  bool _showScrollIndicator;
  Color _color;
  Color? _backgroundColor;
  Color _selectedBackgroundColor;
  Color _selectedTextColor;
  Color _descriptionColor;

  set options(List<SelectOption<T>> v) {
    if (identical(_options, v)) return;
    _options = v;
    markNeedsLayout();
  }

  set highlighted(int v) {
    if (_highlighted == v) return;
    _highlighted = v;
    markNeedsPaint();
  }

  set scrollOffset(int v) {
    if (_scrollOffset == v) return;
    _scrollOffset = v;
    markNeedsPaint();
  }

  set visibleRows(int v) {
    requireNonNegativeExtent(v, 'visibleRows');
    if (_visibleRows == v) return;
    _visibleRows = v;
    markNeedsLayout();
  }

  set showScrollIndicator(bool v) {
    if (_showScrollIndicator == v) return;
    _showScrollIndicator = v;
    markNeedsLayout();
  }

  set color(Color v) {
    if (_color == v) return;
    _color = v;
    markNeedsPaint();
  }

  set backgroundColor(Color? v) {
    if (_backgroundColor == v) return;
    _backgroundColor = v;
    markNeedsPaint();
  }

  set selectedBackgroundColor(Color v) {
    if (_selectedBackgroundColor == v) return;
    _selectedBackgroundColor = v;
    markNeedsPaint();
  }

  set selectedTextColor(Color v) {
    if (_selectedTextColor == v) return;
    _selectedTextColor = v;
    markNeedsPaint();
  }

  set descriptionColor(Color v) {
    if (_descriptionColor == v) return;
    _descriptionColor = v;
    markNeedsPaint();
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    var desiredWidth = 0;
    for (final opt in _options) {
      final nameW = terminalStringWidth(opt.name);
      final descW = opt.description != null
          ? terminalStringWidth(opt.description!) + 1
          : 0;
      final segLen = nameW + descW;
      if (segLen > desiredWidth) desiredWidth = segLen;
    }
    if (_showScrollIndicator) desiredWidth += 1;
    final w = constraints.constrainWidth(
      desiredWidth == 0 ? constraints.minWidth : desiredWidth,
    );
    final h = constraints.constrainHeight(_visibleRows);
    size = Size(w, h);
    _layoutMetrics?.publish(math.max(0, math.min(h, _visibleRows)));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (width <= 0 || height <= 0) {
      return;
    }
    final originX = offset.dx + x;
    final originY = offset.dy + y;
    final canvas = context.canvas;

    final rowBg = _backgroundColor ?? Color.transparent;
    if (_backgroundColor != null) {
      canvas.fillRect(
        Rect.fromLTWH(originX, originY, width, height),
        _backgroundColor!,
      );
    }

    final usableWidth = _showScrollIndicator ? width - 1 : width;
    // Rows layout actually granted, which is what `_SelectState` scrolls
    // against: the height hint is an upper bound, and a tight parent can hand
    // back fewer rows. Painting and the arrows must describe the same window,
    // otherwise a constrained list scrolls with no indication that it did.
    final paintedRows = math.min(height, _visibleRows);
    for (var row = 0; row < paintedRows; row++) {
      final index = _scrollOffset + row;
      if (index >= _options.length) break;
      final opt = _options[index];
      final isHighlighted = index == _highlighted;
      final fg = isHighlighted ? _selectedTextColor : _color;
      final bg = isHighlighted ? _selectedBackgroundColor : rowBg;

      if (isHighlighted) {
        canvas.fillRect(
          Rect.fromLTWH(originX, originY + row, usableWidth, 1),
          _selectedBackgroundColor,
        );
      }

      // Paint name cluster-by-cluster (each grapheme → its cell width).
      var col = 0;
      for (final cluster in opt.name.characters) {
        final cw = terminalCellWidth(cluster);
        if (col + cw > usableWidth) break;
        canvas.setCell(
          Offset(originX + col, originY + row),
          cluster,
          fg,
          bg,
          0,
        );
        col += cw;
      }

      // Description (gap + dim color).
      if (opt.description != null && col < usableWidth) {
        canvas.setCell(Offset(originX + col, originY + row), ' ', fg, bg, 0);
        col++;
        final descColor = isHighlighted
            ? _selectedTextColor
            : _descriptionColor;
        for (final cluster in opt.description!.characters) {
          final cw = terminalCellWidth(cluster);
          if (col + cw > usableWidth) break;
          canvas.setCell(
            Offset(originX + col, originY + row),
            cluster,
            descColor,
            bg,
            0,
          );
          col += cw;
        }
      }
    }

    // Scroll indicator (always last column when enabled and overflow). A box
    // taller than a zero-row hint paints no options at all, so there is no
    // window for an arrow to describe and no row of ours to put one on.
    if (_showScrollIndicator &&
        paintedRows > 0 &&
        _options.length > paintedRows) {
      final indCol = originX + width - 1;
      // Up arrow at top if scrollable up
      canvas.setCell(
        Offset(indCol, originY),
        _scrollOffset > 0 ? '▲' : ' ',
        _color,
        rowBg,
        0,
      );
      // Down arrow on the last painted row if scrollable down
      final lastVisible = _scrollOffset + paintedRows;
      canvas.setCell(
        Offset(indCol, originY + paintedRows - 1),
        lastVisible < _options.length ? '▼' : ' ',
        _color,
        rowBg,
        0,
      );
    }
  }
}
