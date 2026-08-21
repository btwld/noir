import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

import '../core/color.dart';
import '../core/grapheme_metrics.dart';
import '../core/input.dart';
import '../foundation/selected_text.dart';
import '../foundation/text_index_map.dart';
import '../foundation/text_selection.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/box.dart';
import '../rendering/object.dart';
import '../rendering/proxy_box.dart';
import '../rendering/text_highlight.dart';
import 'document_view.dart';
import 'focus.dart';
import 'focus_node_owner_mixin.dart';
import 'pointer_listener.dart';
import 'text_layout.dart';
import 'text_span.dart';
import 'text_style.dart';
import 'text_table_model.dart';
import 'theme.dart';

/// Cell wrapping policy for [TextTable].
enum TextTableWrapMode {
  /// Keep each source line unwrapped and clip at the cell edge.
  none,

  /// Wrap at terminal grapheme boundaries.
  character,

  /// Prefer whitespace boundaries and fall back to grapheme boundaries.
  word,
}

/// How a table chooses its total width.
enum TextTableColumnWidthMode {
  /// Shrink to intrinsic column content when constraints allow.
  content,

  /// Consume the available bounded width.
  full,
}

/// How bounded content cells are distributed across columns.
enum TextTableColumnFitter {
  /// Weight widths by each column's intrinsic content.
  proportional,

  /// Keep column widths as even as possible.
  balanced,
}

/// A finite rich-text table with synchronized row layout and grid selection.
class TextTable extends StatefulWidget {
  /// Configures table content, fitting, chrome, focus, and grid selection.
  const TextTable({
    required this.content,
    super.key,
    this.wrapMode = TextTableWrapMode.word,
    this.columnWidthMode = TextTableColumnWidthMode.full,
    this.columnFitter = TextTableColumnFitter.proportional,
    this.cellPadding = 0,
    this.cellPaddingX,
    this.cellPaddingY,
    this.columnGap = 0,
    this.showBorders = true,
    this.outerBorder = true,
    this.borderColor = Color.white,
    this.selectable = true,
    this.selection,
    this.selectionForegroundColor,
    this.selectionBackgroundColor,
    this.focusNode,
    this.autofocus = false,
    this.onSelectionChanged,
    this.onCopy,
  }) : assert(cellPadding >= 0),
       assert(cellPaddingX == null || cellPaddingX >= 0),
       assert(cellPaddingY == null || cellPaddingY >= 0),
       assert(columnGap >= 0);

  /// Rows of nullable rich-text cells.
  final List<List<InlineSpan?>> content;

  /// Cell wrapping policy.
  final TextTableWrapMode wrapMode;

  /// Total-width policy.
  final TextTableColumnWidthMode columnWidthMode;

  /// Column allocation policy.
  final TextTableColumnFitter columnFitter;

  /// Default horizontal and vertical cell padding.
  final int cellPadding;

  /// Horizontal padding override.
  final int? cellPaddingX;

  /// Vertical padding override.
  final int? cellPaddingY;

  /// Extra cells between columns when borders are hidden.
  final int columnGap;

  /// Whether inner and outer single-line borders are painted.
  final bool showBorders;

  /// Whether the outer border is reserved and painted.
  final bool outerBorder;

  /// Border foreground.
  final Color borderColor;

  /// Whether pointer and keyboard selection are enabled.
  final bool selectable;

  /// Optional controlled highlight over row-major text.
  ///
  /// When absent, selection is owned internally or by an enclosing composed
  /// document. Supplying a value only controls paint; interaction callbacks
  /// continue to report the user-owned selection.
  final TextHighlight? selection;

  /// Selected text foreground override.
  final Color? selectionForegroundColor;

  /// Selected text background override.
  final Color? selectionBackgroundColor;

  /// Caller-owned focus node, or null for widget ownership.
  final FocusNode? focusNode;

  /// Whether the table requests focus after mounting.
  final bool autofocus;

  /// Receives null for no non-empty standalone selection.
  final void Function(SelectedText? selection)? onSelectionChanged;

  /// Receives explicit copy results for a standalone selection.
  final SelectionCopyCallback? onCopy;

  @override
  State<TextTable> createState() => _TextTableState();
}

final class _TextTableState extends State<TextTable>
    with FocusNodeOwnerStateMixin<TextTable> {
  TextSelection? _selection;
  bool _dragging = false;

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  void didUpdateWidget(TextTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
    final plainText = serializeTextTableContent(widget.content);
    final selection = _selection;
    if (selection != null && selection.end > plainText.length) {
      _selection = null;
      widget.onSelectionChanged?.call(null);
    }
  }

  SelectedText? _selectedText(String plainText) {
    final selection = _selection;
    if (selection == null || selection.isCollapsed) return null;
    return SelectedText(
      selection: selection,
      text: plainText.substring(selection.start, selection.end),
    );
  }

  void _setSelection(String plainText, TextSelection? selection) {
    if (_selection == selection) return;
    setState(() => _selection = selection);
    widget.onSelectionChanged?.call(_selectedText(plainText));
  }

  RenderTextTable? _renderTable(BuildContext context) {
    var current = context.findRenderObject();
    while (current != null) {
      if (current is RenderTextTable) return current;
      if (current is! RenderProxyBox) return null;
      current = current.child;
    }
    return null;
  }

  TextSelection? _readSelection(DocumentSelectionScope? scope) =>
      scope?.selection ?? _selection;

  void _setEffectiveSelection(
    DocumentSelectionScope? scope,
    String plainText,
    TextSelection? selection,
  ) {
    if (scope == null) {
      _setSelection(plainText, selection);
    } else {
      scope.onSelectionChanged(selection);
    }
  }

  bool _readDragging(DocumentSelectionScope? scope) =>
      scope?.dragging ?? _dragging;

  void _setDragging(DocumentSelectionScope? scope, {required bool dragging}) {
    if (scope == null) {
      _dragging = dragging;
    } else {
      scope.onDraggingChanged(dragging: dragging);
    }
  }

  void _pointerDown(
    BuildContext context,
    DocumentSelectionScope? scope,
    String plainText,
    MouseEvent event,
  ) {
    if (event.button != MouseButton.left) return;
    focusNode.requestFocus();
    if (!widget.selectable) return;
    final table = _renderTable(context);
    if (table == null) return;
    _setDragging(scope, dragging: true);
    _setEffectiveSelection(
      scope,
      plainText,
      TextSelection.collapsed(
        offset:
            (scope?.sourceBase ?? 0) +
            table.sourceOffsetAt(event.localPosition),
      ),
    );
  }

  void _pointerMove(
    BuildContext context,
    DocumentSelectionScope? scope,
    String plainText,
    MouseEvent event,
  ) {
    if (!widget.selectable || !_readDragging(scope)) return;
    final selection = _readSelection(scope);
    final table = _renderTable(context);
    if (selection == null || table == null) return;
    _setEffectiveSelection(
      scope,
      plainText,
      TextSelection(
        baseOffset: selection.baseOffset,
        extentOffset:
            (scope?.sourceBase ?? 0) +
            table.sourceOffsetAt(event.localPosition),
        isDirectional: true,
      ),
    );
  }

  void _pointerUp(
    BuildContext context,
    DocumentSelectionScope? scope,
    String plainText,
    MouseEvent event,
  ) {
    if (!_readDragging(scope)) return;
    _pointerMove(context, scope, plainText, event);
    _setDragging(scope, dragging: false);
  }

  @override
  Widget build(BuildContext context) {
    final scope = DocumentSelectionScope.maybeOf(context);
    final plainText = serializeTextTableContent(widget.content);
    final effectiveSelection = scope == null
        ? _selection
        : scope.selectionForBlock(plainText.length);
    final theme = Theme.of(context);
    final paintSelection =
        widget.selection ??
        (effectiveSelection == null || effectiveSelection.isCollapsed
            ? null
            : TextHighlight(
                start: effectiveSelection.start,
                end: effectiveSelection.end,
                foregroundColor:
                    widget.selectionForegroundColor ?? theme.selectedForeground,
                backgroundColor:
                    widget.selectionBackgroundColor ?? theme.selectedBackground,
              ));
    return DocumentSelectionControls(
      documentText: scope?.documentText ?? plainText,
      selectable: widget.selectable,
      readSelection: () => _readSelection(scope),
      onSelectionChanged: (selection) =>
          _setEffectiveSelection(scope, plainText, selection),
      onCopy: scope?.onCopy ?? widget.onCopy,
      focusNode: focusNode,
      child: Focus(
        focusNode: focusNode,
        autofocus: widget.autofocus,
        child: PointerListener(
          onPointerDown: (event) =>
              _pointerDown(context, scope, plainText, event),
          onPointerMove: (event) =>
              _pointerMove(context, scope, plainText, event),
          onPointerUp: (event) => _pointerUp(context, scope, plainText, event),
          child: _TextTableLeaf(
            content: widget.content,
            wrapMode: widget.wrapMode,
            columnWidthMode: widget.columnWidthMode,
            columnFitter: widget.columnFitter,
            cellPaddingX: widget.cellPaddingX ?? widget.cellPadding,
            cellPaddingY: widget.cellPaddingY ?? widget.cellPadding,
            columnGap: widget.columnGap,
            showBorders: widget.showBorders,
            outerBorder: widget.outerBorder,
            borderColor: widget.borderColor,
            selectable: widget.selectable,
            selection: paintSelection,
          ),
        ),
      ),
    );
  }
}

final class _TextTableLeaf extends RenderObjectWidget {
  const _TextTableLeaf({
    required this.content,
    required this.wrapMode,
    required this.columnWidthMode,
    required this.columnFitter,
    required this.cellPaddingX,
    required this.cellPaddingY,
    required this.columnGap,
    required this.showBorders,
    required this.outerBorder,
    required this.borderColor,
    required this.selectable,
    required this.selection,
  });

  final List<List<InlineSpan?>> content;
  final TextTableWrapMode wrapMode;
  final TextTableColumnWidthMode columnWidthMode;
  final TextTableColumnFitter columnFitter;
  final int cellPaddingX;
  final int cellPaddingY;
  final int columnGap;
  final bool showBorders;
  final bool outerBorder;
  final Color borderColor;
  final bool selectable;
  final TextHighlight? selection;

  @override
  @internal
  RenderObject createRenderObject(BuildContext context) => RenderTextTable(
    content: content,
    wrapMode: wrapMode,
    columnWidthMode: columnWidthMode,
    columnFitter: columnFitter,
    cellPaddingX: cellPaddingX,
    cellPaddingY: cellPaddingY,
    columnGap: columnGap,
    showBorders: showBorders,
    outerBorder: outerBorder,
    borderColor: borderColor,
    selectable: selectable,
    selection: selection,
  );

  @override
  @internal
  void updateRenderObject(BuildContext context, RenderTextTable renderObject) {
    renderObject.update(
      content: content,
      wrapMode: wrapMode,
      columnWidthMode: columnWidthMode,
      columnFitter: columnFitter,
      cellPaddingX: cellPaddingX,
      cellPaddingY: cellPaddingY,
      columnGap: columnGap,
      showBorders: showBorders,
      outerBorder: outerBorder,
      borderColor: borderColor,
      selectable: selectable,
      selection: selection,
    );
  }
}

/// Render object that owns one table measurement and paint model.
final class RenderTextTable extends RenderBox {
  /// Creates a render table from immutable snapshots of [content].
  RenderTextTable({
    required List<List<InlineSpan?>> content,
    required TextTableWrapMode wrapMode,
    required TextTableColumnWidthMode columnWidthMode,
    required TextTableColumnFitter columnFitter,
    required int cellPaddingX,
    required int cellPaddingY,
    required int columnGap,
    required bool showBorders,
    required bool outerBorder,
    required Color borderColor,
    required bool selectable,
    required TextHighlight? selection,
  }) : _content = _snapshotContent(content),
       _wrapMode = wrapMode,
       _columnWidthMode = columnWidthMode,
       _columnFitter = columnFitter,
       _cellPaddingX = _nonNegative(cellPaddingX, 'cellPaddingX'),
       _cellPaddingY = _nonNegative(cellPaddingY, 'cellPaddingY'),
       _columnGap = _nonNegative(columnGap, 'columnGap'),
       _showBorders = showBorders,
       _outerBorder = outerBorder,
       _borderColor = borderColor,
       _selectable = selectable,
       _selection = selection;

  List<List<InlineSpan?>> _content;
  TextTableWrapMode _wrapMode;
  TextTableColumnWidthMode _columnWidthMode;
  TextTableColumnFitter _columnFitter;
  int _cellPaddingX;
  int _cellPaddingY;
  int _columnGap;
  bool _showBorders;
  bool _outerBorder;
  Color _borderColor;
  bool _selectable;
  TextHighlight? _selection;
  List<int> _columnWidths = const <int>[];
  List<int> _rowHeights = const <int>[];
  List<_TableCellLayout> _cells = const <_TableCellLayout>[];

  /// Last completed content widths, excluding padding and borders.
  @visibleForTesting
  List<int> get debugColumnWidths => List<int>.unmodifiable(_columnWidths);

  /// Maps a table-local cell position to row-major UTF-16 text coordinates.
  int sourceOffsetAt(Offset position) {
    if (_cells.isEmpty) return 0;
    final columnStarts = _columnStarts();
    final rowStarts = _rowStarts();
    final column = _partAt(position.dx, columnStarts, _columnWidths);
    final row = _partAt(position.dy, rowStarts, _rowHeights);
    final cell = _cells[row * _columnWidths.length + column];
    final lineIndex = (position.dy - rowStarts[row] - _cellPaddingY).clamp(
      0,
      cell.layout.lines.length - 1,
    );
    final line = cell.layout.lines[lineIndex];
    final targetCell = math.max(
      0,
      position.dx - columnStarts[column] - _cellPaddingX,
    );
    var paintedCell = 0;
    for (final run in line.runs) {
      var sourceOffset = run.sourceStart;
      for (final grapheme in run.text.characters) {
        final width = terminalCellWidth(grapheme);
        if (targetCell < paintedCell + math.max(1, width)) {
          return cell.sourceBase + sourceOffset;
        }
        paintedCell += width;
        sourceOffset += grapheme.length;
      }
    }
    final lineEnd = line.runs.isEmpty ? 0 : line.runs.last.sourceEnd;
    return cell.sourceBase + lineEnd;
  }

  /// Atomically replaces the table configuration and invalidates layout.
  void update({
    required List<List<InlineSpan?>> content,
    required TextTableWrapMode wrapMode,
    required TextTableColumnWidthMode columnWidthMode,
    required TextTableColumnFitter columnFitter,
    required int cellPaddingX,
    required int cellPaddingY,
    required int columnGap,
    required bool showBorders,
    required bool outerBorder,
    required Color borderColor,
    required bool selectable,
    required TextHighlight? selection,
  }) {
    _content = _snapshotContent(content);
    _wrapMode = wrapMode;
    _columnWidthMode = columnWidthMode;
    _columnFitter = columnFitter;
    _cellPaddingX = _nonNegative(cellPaddingX, 'cellPaddingX');
    _cellPaddingY = _nonNegative(cellPaddingY, 'cellPaddingY');
    _columnGap = _nonNegative(columnGap, 'columnGap');
    _showBorders = showBorders;
    _outerBorder = outerBorder;
    _borderColor = borderColor;
    _selectable = selectable;
    _selection = selection;
    markNeedsLayout();
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final columns = _content.fold<int>(
      0,
      (count, row) => math.max(count, row.length),
    );
    if (columns == 0 || _content.isEmpty) {
      _columnWidths = const <int>[];
      _rowHeights = const <int>[];
      _cells = const <_TableCellLayout>[];
      size = Size(
        constraints.constrainWidth(0),
        constraints.constrainHeight(0),
      );
      return;
    }

    final intrinsic = List<int>.filled(columns, 1);
    for (final row in _content) {
      for (var column = 0; column < row.length; column++) {
        final span = row[column];
        if (span == null) continue;
        final layout = const TextLayoutEngine().layout(
          span,
          const BoxConstraints(),
        );
        intrinsic[column] = math.max(intrinsic[column], layout.maxLineWidth);
      }
    }
    final outer = _outerBorder && _showBorders ? 2 : 0;
    final separators = columns - 1;
    final separatorWidth = _showBorders ? 1 : _columnGap;
    final structural =
        outer + separators * separatorWidth + columns * _cellPaddingX * 2;
    final intrinsicContent = intrinsic.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final boundedContent = constraints.maxWidth == null
        ? intrinsicContent
        : math.max(columns, constraints.maxWidth! - structural);
    if (intrinsicContent < boundedContent) {
      _columnWidths = _columnWidthMode == TextTableColumnWidthMode.full
          ? _expandWidths(intrinsic, boundedContent)
          : List<int>.unmodifiable(intrinsic);
    } else if (intrinsicContent > boundedContent &&
        _wrapMode != TextTableWrapMode.none) {
      _columnWidths = _fitWidths(intrinsic, boundedContent, _columnFitter);
    } else {
      _columnWidths = List<int>.unmodifiable(intrinsic);
    }

    final cells = <_TableCellLayout>[];
    final rowHeights = <int>[];
    var sourceBase = 0;
    for (var rowIndex = 0; rowIndex < _content.length; rowIndex++) {
      final row = _content[rowIndex];
      var rowHeight = 1 + _cellPaddingY * 2;
      for (var column = 0; column < columns; column++) {
        final span = column < row.length ? row[column] : null;
        final effective = span ?? const TextSpan(text: '');
        final layout = _layoutCell(effective, _columnWidths[column], _wrapMode);
        cells.add(
          _TableCellLayout(
            row: rowIndex,
            column: column,
            layout: layout,
            sourceBase: sourceBase,
          ),
        );
        rowHeight = math.max(rowHeight, layout.lineCount + _cellPaddingY * 2);
        sourceBase += layout.text.length;
        if (column < columns - 1) sourceBase++;
      }
      rowHeights.add(rowHeight);
      if (rowIndex < _content.length - 1) sourceBase++;
    }
    _rowHeights = List<int>.unmodifiable(rowHeights);
    _cells = List<_TableCellLayout>.unmodifiable(cells);

    final width =
        structural + _columnWidths.fold<int>(0, (sum, value) => sum + value);
    final horizontalRules = _showBorders
        ? (_outerBorder ? 2 : 0) + (_content.length - 1)
        : 0;
    final height =
        horizontalRules + rowHeights.fold<int>(0, (sum, value) => sum + value);
    size = Size(
      constraints.constrainWidth(width),
      constraints.constrainHeight(height),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_columnWidths.isEmpty || size.width <= 0 || size.height <= 0) return;
    final origin = offset + Offset(x, y);
    context.canvas.save();
    try {
      context.canvas.clipRect(origin & size);
      final columnStarts = _columnStarts();
      final rowStarts = _rowStarts();
      if (_showBorders) {
        _paintBorders(context, origin, columnStarts, rowStarts);
      }
      for (final cell in _cells) {
        final x = columnStarts[cell.column] + _cellPaddingX;
        final y = rowStarts[cell.row] + _cellPaddingY;
        final localSelection = _localSelection(cell);
        context.canvas.drawTextLayout(
          cell.layout,
          Offset(origin.dx + x, origin.dy + y),
          sourceRect: Rect.fromLTWH(
            0,
            0,
            _columnWidths[cell.column],
            _rowHeights[cell.row] - _cellPaddingY * 2,
          ),
          selection: localSelection,
        );
      }
    } finally {
      context.canvas.restore();
    }
  }

  List<int> _columnStarts() {
    final starts = <int>[];
    var cursor = _showBorders && _outerBorder ? 1 : 0;
    for (var index = 0; index < _columnWidths.length; index++) {
      starts.add(cursor);
      cursor += _columnWidths[index] + _cellPaddingX * 2;
      if (index < _columnWidths.length - 1) {
        cursor += _showBorders ? 1 : _columnGap;
      }
    }
    return starts;
  }

  List<int> _rowStarts() {
    final starts = <int>[];
    var cursor = _showBorders && _outerBorder ? 1 : 0;
    for (var index = 0; index < _rowHeights.length; index++) {
      starts.add(cursor);
      cursor += _rowHeights[index];
      if (_showBorders && index < _rowHeights.length - 1) cursor++;
    }
    return starts;
  }

  void _paintBorders(
    PaintingContext context,
    Offset origin,
    List<int> columnStarts,
    List<int> rowStarts,
  ) {
    final verticals = <int>[];
    if (_outerBorder) verticals.add(0);
    for (var column = 1; column < columnStarts.length; column++) {
      verticals.add(columnStarts[column] - 1);
    }
    if (_outerBorder) verticals.add(size.width - 1);

    final horizontals = <int>[];
    if (_outerBorder) horizontals.add(0);
    for (var row = 1; row < rowStarts.length; row++) {
      horizontals.add(rowStarts[row] - 1);
    }
    if (_outerBorder) horizontals.add(size.height - 1);

    for (final y in horizontals) {
      context.canvas.drawText(
        List<String>.filled(size.width, '─').join(),
        Offset(origin.dx, origin.dy + y),
        _borderColor,
      );
    }
    for (final x in verticals) {
      for (var y = 0; y < size.height; y++) {
        context.canvas.drawText(
          '│',
          Offset(origin.dx + x, origin.dy + y),
          _borderColor,
        );
      }
    }
    for (var row = 0; row < horizontals.length; row++) {
      for (var column = 0; column < verticals.length; column++) {
        final char = _junction(
          top: row > 0 || !_outerBorder,
          bottom: row < horizontals.length - 1 || !_outerBorder,
          left: column > 0 || !_outerBorder,
          right: column < verticals.length - 1 || !_outerBorder,
        );
        context.canvas.drawText(
          char,
          Offset(origin.dx + verticals[column], origin.dy + horizontals[row]),
          _borderColor,
        );
      }
    }
  }

  TextHighlight? _localSelection(_TableCellLayout cell) {
    final selection = _selectable ? _selection : null;
    if (selection == null) return null;
    final start = math.max(selection.start, cell.sourceBase);
    final end = math.min(
      selection.end,
      cell.sourceBase + cell.layout.text.length,
    );
    if (start >= end) return null;
    return TextHighlight(
      start: start - cell.sourceBase,
      end: end - cell.sourceBase,
      foregroundColor: selection.foregroundColor,
      backgroundColor: selection.backgroundColor,
    );
  }
}

int _partAt(int position, List<int> starts, List<int> sizes) {
  for (var index = 0; index < starts.length; index++) {
    if (position < starts[index] + sizes[index]) return index;
  }
  return starts.length - 1;
}

final class _TableCellLayout {
  const _TableCellLayout({
    required this.row,
    required this.column,
    required this.layout,
    required this.sourceBase,
  });
  final int row;
  final int column;
  final TextLayout layout;
  final int sourceBase;
}

List<List<InlineSpan?>> _snapshotContent(List<List<InlineSpan?>> content) =>
    List<List<InlineSpan?>>.unmodifiable(
      content.map(
        (row) => List<InlineSpan?>.unmodifiable(
          row.map((cell) => cell == null ? null : snapshotInlineSpan(cell)),
        ),
      ),
    );

int _nonNegative(int value, String name) {
  if (value < 0) throw ArgumentError.value(value, name, 'must be non-negative');
  return value;
}

List<int> _expandWidths(List<int> widths, int target) {
  final expanded = widths.map((width) => math.max(1, width)).toList();
  final current = expanded.fold<int>(0, (sum, width) => sum + width);
  if (current >= target || expanded.isEmpty) {
    return List<int>.unmodifiable(expanded);
  }
  final extra = target - current;
  final shared = extra ~/ expanded.length;
  final remainder = extra % expanded.length;
  for (var index = 0; index < expanded.length; index++) {
    expanded[index] += shared + (index < remainder ? 1 : 0);
  }
  return List<int>.unmodifiable(expanded);
}

List<int> _fitWidths(
  List<int> intrinsic,
  int target,
  TextTableColumnFitter fitter,
) {
  if (intrinsic.isEmpty) return const <int>[];
  final usable = math.max(intrinsic.length, target);
  return switch (fitter) {
    TextTableColumnFitter.proportional => _fitProportionalWidths(
      intrinsic,
      usable,
    ),
    TextTableColumnFitter.balanced => _fitBalancedWidths(intrinsic, usable),
  };
}

List<int> _fitBalancedWidths(List<int> widths, int target) {
  final baseWidths = widths.map((width) => math.max(1, width)).toList();
  final totalBase = baseWidths.fold<int>(0, (sum, width) => sum + width);
  if (baseWidths.isEmpty || totalBase <= target) {
    return List<int>.unmodifiable(baseWidths);
  }

  final evenShare = math.max(1, target ~/ baseWidths.length);
  final preferredFloors = baseWidths
      .map((width) => math.min(width, evenShare))
      .toList();
  final preferredTotal = preferredFloors.fold<int>(
    0,
    (sum, width) => sum + width,
  );
  final floorWidths = preferredTotal <= target
      ? preferredFloors
      : List<int>.filled(baseWidths.length, 1);
  final floorTotal = floorWidths.fold<int>(0, (sum, width) => sum + width);
  final clampedTarget = math.max(floorTotal, target);
  if (totalBase <= clampedTarget) {
    return List<int>.unmodifiable(baseWidths);
  }

  final shrinkable = List<int>.generate(
    baseWidths.length,
    (index) => baseWidths[index] - floorWidths[index],
  );
  final shrink = _allocateShrink(shrinkable, totalBase - clampedTarget);
  return List<int>.unmodifiable(
    List<int>.generate(
      baseWidths.length,
      (index) =>
          math.max(floorWidths[index], baseWidths[index] - shrink[index]),
    ),
  );
}

List<int> _allocateShrink(List<int> shrinkable, int target) {
  final shrink = List<int>.filled(shrinkable.length, 0);
  if (target <= 0) return shrink;
  final weights = shrinkable
      .map((value) => value <= 0 ? 0.0 : math.sqrt(value))
      .toList();
  final totalWeight = weights.fold<double>(0, (sum, weight) => sum + weight);
  if (totalWeight <= 0) return shrink;

  final fractions = List<double>.filled(shrinkable.length, 0);
  var used = 0;
  for (var index = 0; index < shrinkable.length; index++) {
    if (shrinkable[index] <= 0 || weights[index] <= 0) continue;
    final exact = weights[index] / totalWeight * target;
    final whole = math.min(shrinkable[index], exact.floor());
    shrink[index] = whole;
    fractions[index] = exact - whole;
    used += whole;
  }
  for (var remaining = target - used; remaining > 0; remaining--) {
    var best = -1;
    var bestFraction = -1.0;
    for (var index = 0; index < shrinkable.length; index++) {
      if (shrinkable[index] <= shrink[index]) continue;
      if (best == -1 ||
          fractions[index] > bestFraction ||
          (fractions[index] == bestFraction &&
              shrinkable[index] > shrinkable[best])) {
        best = index;
        bestFraction = fractions[index];
      }
    }
    if (best == -1) break;
    shrink[best]++;
    fractions[best] = 0;
  }
  return shrink;
}

List<int> _fitProportionalWidths(List<int> widths, int target) {
  const minWidth = 1;
  final baseWidths = widths.map((width) => math.max(minWidth, width)).toList();
  final capacity = baseWidths.map((width) => width - minWidth).toList();
  final totalCapacity = capacity.fold<int>(0, (sum, width) => sum + width);
  final available = (target - minWidth * baseWidths.length).clamp(
    0,
    totalCapacity,
  );
  if (available == 0) {
    return List<int>.filled(baseWidths.length, minWidth);
  }
  if (available == totalCapacity) {
    return List<int>.unmodifiable(baseWidths);
  }

  final weights = capacity.map(math.sqrt).toList();
  final active = <({int index, int capacity, double weight})>[
    for (var index = 0; index < capacity.length; index++)
      if (capacity[index] > 0)
        (index: index, capacity: capacity[index], weight: weights[index]),
  ]..sort((left, right) => left.weight.compareTo(right.weight));
  final growth = List<int>.filled(baseWidths.length, 0);
  if (active.length == capacity.length &&
      capacity.every((width) => width == capacity.first)) {
    final shared = available ~/ capacity.length;
    final remainder = available % capacity.length;
    return List<int>.generate(
      capacity.length,
      (index) => minWidth + shared + (index < remainder ? 1 : 0),
      growable: false,
    );
  }

  var remaining = available;
  var totalWeight = active.fold<double>(
    0,
    (sum, column) => sum + column.weight,
  );
  for (final column in active) {
    if (remaining / totalWeight <= column.weight) break;
    growth[column.index] = column.capacity;
    remaining -= column.capacity;
    totalWeight -= column.weight;
  }
  final level = remaining / totalWeight;
  for (final column in active) {
    if (growth[column.index] == column.capacity) continue;
    growth[column.index] = math.min(
      column.capacity,
      (level * column.weight).floor(),
    );
  }

  var allocated = growth.fold<int>(0, (sum, width) => sum + width);
  while (allocated > available) {
    var worst = -1;
    for (var index = 0; index < baseWidths.length; index++) {
      if (growth[index] == 0) continue;
      final comparison = worst == -1
          ? 1
          : _compareGrowthPriority(
              growth[index],
              capacity[index],
              growth[worst],
              capacity[worst],
            );
      if (comparison > 0 || (comparison == 0 && index > worst)) {
        worst = index;
      }
    }
    if (worst == -1) break;
    growth[worst]--;
    allocated--;
  }
  while (allocated < available) {
    var best = -1;
    for (var index = 0; index < baseWidths.length; index++) {
      if (growth[index] >= capacity[index]) continue;
      final comparison = best == -1
          ? -1
          : _compareGrowthPriority(
              growth[index] + 1,
              capacity[index],
              growth[best] + 1,
              capacity[best],
            );
      if (comparison < 0) best = index;
    }
    if (best == -1) break;
    growth[best]++;
    allocated++;
  }
  return List<int>.generate(
    growth.length,
    (index) => growth[index] + minWidth,
    growable: false,
  );
}

int _compareGrowthPriority(
  int leftGrowth,
  int leftCapacity,
  int rightGrowth,
  int rightCapacity,
) {
  final left = leftGrowth * leftGrowth * rightCapacity;
  final right = rightGrowth * rightGrowth * leftCapacity;
  return left.compareTo(right);
}

TextLayout _layoutCell(InlineSpan span, int width, TextTableWrapMode mode) =>
    switch (mode) {
      TextTableWrapMode.none => const TextLayoutEngine().layout(
        span,
        const BoxConstraints(),
      ),
      TextTableWrapMode.word => const TextLayoutEngine().layout(
        span,
        BoxConstraints(maxWidth: width),
      ),
      TextTableWrapMode.character => _characterLayout(span, width),
    };

TextLayout _characterLayout(InlineSpan span, int width) {
  final sourceRuns = <_CellSourceRun>[];
  final buffer = StringBuffer();
  _flattenCell(span, const TextStyle(), null, buffer, sourceRuns);
  final text = buffer.toString();
  final lines = <List<TextLayoutRun>>[];
  var current = <TextLayoutRun>[];
  var currentWidth = 0;

  void flush() {
    lines.add(current);
    current = <TextLayoutRun>[];
    currentWidth = 0;
  }

  for (final run in sourceRuns) {
    var sourceOffset = run.start;
    for (final grapheme in run.text.characters) {
      if (grapheme == '\n') {
        flush();
        sourceOffset += grapheme.length;
        continue;
      }
      final cellWidth = terminalCellWidth(grapheme);
      if (current.isNotEmpty && currentWidth + cellWidth > width) flush();
      current.add(
        TextLayoutRun(
          text: grapheme,
          style: run.style,
          uri: run.uri,
          sourceStart: sourceOffset,
          sourceEnd: sourceOffset + grapheme.length,
        ),
      );
      currentWidth += cellWidth;
      sourceOffset += grapheme.length;
    }
  }
  if (current.isNotEmpty || lines.isEmpty) flush();
  final layoutLines = lines
      .map(
        (runs) => TextLayoutLine(
          runs: runs,
          width: runs.fold<int>(
            0,
            (sum, run) => sum + terminalStringWidth(run.text),
          ),
        ),
      )
      .toList(growable: false);
  return TextLayout(
    text: text,
    style: span is TextSpan
        ? span.style ?? const TextStyle()
        : const TextStyle(),
    indexMap: TextIndexMap(text),
    lines: layoutLines,
    size: Size(
      layoutLines.fold<int>(0, (value, line) => math.max(value, line.width)),
      layoutLines.length,
    ),
  );
}

final class _CellSourceRun {
  const _CellSourceRun(this.text, this.style, this.uri, this.start);
  final String text;
  final TextStyle style;
  final Uri? uri;
  final int start;
}

void _flattenCell(
  InlineSpan span,
  TextStyle inherited,
  Uri? inheritedUri,
  StringBuffer buffer,
  List<_CellSourceRun> runs,
) {
  if (span is TextSpan) {
    final style = span.style ?? inherited;
    final uri = span.uri ?? inheritedUri;
    if (span.text case final text? when text.isNotEmpty) {
      final start = buffer.length;
      buffer.write(text);
      runs.add(_CellSourceRun(text, style, uri, start));
    }
    for (final child in span.children) {
      _flattenCell(child, style, uri, buffer, runs);
    }
    return;
  }
  final text = span.toPlainText();
  if (text.isNotEmpty) {
    final start = buffer.length;
    buffer.write(text);
    runs.add(_CellSourceRun(text, inherited, inheritedUri, start));
  }
}

String _junction({
  required bool top,
  required bool bottom,
  required bool left,
  required bool right,
}) => switch ((top, bottom, left, right)) {
  (false, true, false, true) => '┌',
  (false, true, true, false) => '┐',
  (true, false, false, true) => '└',
  (true, false, true, false) => '┘',
  (false, true, true, true) => '┬',
  (true, false, true, true) => '┴',
  (true, true, false, true) => '├',
  (true, true, true, false) => '┤',
  _ => '┼',
};
