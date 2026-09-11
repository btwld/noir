// ignore_for_file: avoid_setters_without_getters
import 'package:characters/characters.dart';

import '../core/color.dart';
import '../core/cursor.dart';
import '../core/grapheme_metrics.dart';
import '../core/input.dart';
import '../core/mouse_cursor.dart';
import '../foundation/text_editing_controller.dart';
import '../foundation/text_selection.dart';
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
import 'text_editing_owner_mixin.dart';
import 'text_input_connection.dart';
import 'text_layout.dart';
import 'text_span.dart';
import 'theme.dart';
import 'viewport.dart';

/// Multi-line text input, parity with OpenTUI-React `<textarea>`.
///
/// Keys (when focused):
/// - Printable chars insert at cursor.
/// - Backspace / Delete edit characters and join lines.
/// - By default, Enter inserts a newline and Ctrl+Enter fires [onSubmit].
/// - With [submitOnEnter], Enter submits and Ctrl+J inserts a newline.
/// - Arrow keys, Home/End, Ctrl+Home/End move the cursor.
/// - An [InsertTabIntent] inserts [tabSize] spaces.
///
/// Controller selections use UTF-16 offsets. Rendering derives
/// grapheme-cluster line/column positions from the controller helpers.
class TextArea extends StatefulWidget {
  /// Configures a multiline editor; [controller] and initial [value] are
  /// mutually exclusive. Supplied controllers and focus nodes are caller-owned;
  /// omitted ones are created and owned by widget state.
  const TextArea({
    super.key,
    this.controller,
    this.value,
    this.placeholder,
    this.height = 5,
    this.maxHeight,
    this.width,
    this.softWrap = false,
    this.submitOnEnter = false,
    this.readOnly = false,
    this.tabSize = 2,
    this.color,
    this.backgroundColor,
    this.cursorColor,
    this.cursorStyle = CursorStyle.block,
    this.maxLength,
    this.onChanged,
    this.onSubmit,
    this.focusNode,
    this.autofocus = false,
  }) : assert(
         controller == null || value == null,
         'TextArea cannot be given both controller and value.',
       ),
       assert(height >= 0),
       assert(maxHeight == null || maxHeight >= height),
       assert(width == null || width >= 0);

  /// The controller that owns this field's text and selection.
  final TextEditingController? controller;

  /// Initial/current value when [controller] is not supplied.
  final String? value;

  /// Dimmed hint text shown when the field is empty and unfocused.
  final String? placeholder;

  /// Visible height of the field in rows. Defaults to 5.
  ///
  /// This remains an exact height when [maxHeight] is null. When [maxHeight]
  /// is set, it is the minimum height used for bounded content growth.
  final int height;

  /// Optional maximum height for content-driven growth.
  ///
  /// Must be at least [height]. When set, the field grows from [height] to
  /// this many visual rows before scrolling internally.
  final int? maxHeight;

  /// Explicit width in cells. Expands to available width when null.
  final int? width;

  /// Whether long logical lines wrap at grapheme boundaries and terminal
  /// cell widths instead of scrolling horizontally.
  final bool softWrap;

  /// Whether plain Enter submits instead of inserting a newline.
  ///
  /// In this mode a distinguishable Ctrl+J inserts a newline. Multiline paste
  /// remains allowed.
  final bool submitOnEnter;

  /// When true, the field renders text but rejects edits. Defaults to false.
  final bool readOnly;

  /// Number of spaces inserted for a tab. Defaults to 2.
  final int tabSize;

  /// Foreground color of the text. Falls back to [ThemeData.text].
  final Color? color;

  /// Fill color painted behind the field. Falls back to [ThemeData.surface]
  /// under a [Theme]; with neither, the field paints no fill. Pass
  /// [Color.transparent] for an explicitly unfilled field inside a themed
  /// subtree.
  final Color? backgroundColor;

  /// Color of the cursor. Falls back to [ThemeData.cursor].
  final Color? cursorColor;

  /// Shape drawn for the cursor. Defaults to [CursorStyle.block].
  final CursorStyle cursorStyle;

  /// Maximum number of characters accepted. Unlimited when null.
  final int? maxLength;

  /// Called whenever the text value changes.
  final void Function(String value)? onChanged;

  /// Called when the user submits the current text value.
  final void Function()? onSubmit;

  /// Focus node controlling this field's focus. One is created if null.
  final FocusNode? focusNode;

  /// Whether the field requests focus when first mounted. Defaults to false.
  final bool autofocus;

  @override
  State<TextArea> createState() => _TextAreaState();
}

class _TextAreaLayoutMetrics {
  Size? _lastCompletedSize;

  Size? get lastCompletedSize => _lastCompletedSize;

  // A verb expresses one-way publication more clearly than a writable API.
  // ignore: use_setters_to_change_properties
  void publish(Size size) {
    _lastCompletedSize = size;
  }
}

class _TextAreaState extends State<TextArea>
    with
        FocusNodeOwnerStateMixin<TextArea>,
        TextEditingOwnerStateMixin<TextArea> {
  // Vertical viewport: row units (1 row per line).
  final ViewportController _vViewport = ViewportController();
  // Horizontal viewport: terminal cell units.
  final ViewportController _hViewport = ViewportController();
  final _TextAreaLayoutMetrics _layoutMetrics = _TextAreaLayoutMetrics();

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  TextEditingController? get widgetController => widget.controller;

  @override
  String? get widgetValue => widget.value;

  @override
  void initState() {
    super.initState();
    initController();
  }

  @override
  void didUpdateWidget(TextArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
    syncController(oldWidget.controller, oldWidget.value);
  }

  @override
  void onControllerChanged() => _ensureCursorVisible();

  /// Visible viewport size in cells from the latest completed layout.
  /// Falls back to the constructor hints before a usable layout completes.
  ({int width, int height}) get _viewportCells {
    final completedSize = _layoutMetrics.lastCompletedSize;
    if (completedSize != null &&
        completedSize.width > 0 &&
        completedSize.height > 0) {
      return (width: completedSize.width, height: completedSize.height);
    }
    return (width: widget.width ?? 80, height: widget.height);
  }

  /// Painted cell column of the cursor on its line. Computed from raw text
  /// + grapheme cell widths (so wide CJK characters contribute 2 cells).
  int _cursorCellCol() {
    final line = controller.lines[controller.line];
    return graphemeIndexToCell(line, controller.col);
  }

  _TextAreaVisualLayout _visualLayout(int width) =>
      _TextAreaVisualLayout.compute(
        controller.text,
        width: width,
        softWrap: widget.softWrap,
      );

  /// Scrolls the vertical and horizontal viewports so the cursor's line and
  /// column are visible. The horizontal content extent is derived from the
  /// cursor cell alone, since "scroll into view" only cares about the cursor.
  void _ensureCursorVisible() {
    final cells = _viewportCells;
    final visualLayout = _visualLayout(cells.width);
    final cursor = visualLayout.positionForOffset(
      controller.selection.extentOffset,
      affinity: controller.selection.affinity,
    );
    _vViewport.viewportExtent = cells.height;
    _vViewport.contentExtent = visualLayout.lines.length;
    _vViewport.ensureVisible(cursor.row, cursor.row + 1);

    if (widget.softWrap) {
      _hViewport.viewportExtent = cells.width;
      _hViewport.contentExtent = cells.width;
      _hViewport.jumpTo(0);
      return;
    }

    // Horizontal: ensure the cursor column is visible. Content extent is
    // at least cursor cell + 1 so ensureVisible can actually scroll.
    final cursorCell = _cursorCellCol();
    _hViewport.viewportExtent = cells.width;
    _hViewport.contentExtent = cursorCell + 1 > _hViewport.contentExtent
        ? cursorCell + 1
        : _hViewport.contentExtent;
    _hViewport.ensureVisible(cursorCell, cursorCell + 1);
  }

  @override
  TextInputConnection get connection => TextInputConnection(
    controller: controller,
    readOnly: widget.readOnly,
    maxLength: widget.maxLength,
    tabSize: widget.tabSize,
    onChanged: widget.onChanged,
    onSubmit: widget.onSubmit,
  );

  KeyEventResult _moveByVisualRow(int delta) {
    if (!controller.selectionWithinText) {
      throw StateError(
        'TextArea requires an in-range controller selection for visual '
        'cursor movement.',
      );
    }
    final layout = _visualLayout(_viewportCells.width);
    final current = layout.positionForOffset(
      controller.selection.extentOffset,
      affinity: controller.selection.affinity,
    );
    final targetRow = (current.row + delta).clamp(0, layout.lines.length - 1);
    if (targetRow == current.row) return KeyEventResult.ignored;
    final target = layout.lines[targetRow].sourceOffsetForCell(current.cell);
    final targetAffinity = layout.affinityForPosition(targetRow, target);
    final before = controller.selection;
    controller.selection = TextSelection.collapsed(
      offset: target,
      affinity: targetAffinity,
    );
    return controller.selection == before
        ? KeyEventResult.ignored
        : KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    requireUsableSelectionForBuild();
    final conn = connection;
    final shortcuts = conn.shortcuts;
    if (widget.submitOnEnter) {
      shortcuts
        ..[const SingleActivator(LogicalKeyboardKey.enter)] =
            const SubmitTextIntent()
        ..[const SingleActivator(LogicalKeyboardKey.keyJ, control: true)] =
            const InsertTextIntent('\n');
    }
    final actions = conn.actions;
    if (widget.softWrap) {
      actions
        ..[MoveCaretUpIntent] = CallbackAction<MoveCaretUpIntent>(
          (intent, context) => _moveByVisualRow(-1),
        )
        ..[MoveCaretDownIntent] = CallbackAction<MoveCaretDownIntent>(
          (intent, context) => _moveByVisualRow(1),
        );
    }
    final theme = Theme.maybeOf(context);
    final palette = theme ?? ThemeData.dark;
    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: actions,
        child: Focus(
          focusNode: focusNode,
          autofocus: widget.autofocus,
          onFocusChange: handleFocusChange,
          child: PointerListener(
            mouseCursor: MouseCursor.text,
            onPointerDown: handlePointerDown,
            child: _TextAreaLeaf(
              layoutMetrics: _layoutMetrics,
              lines: controller.lines,
              cursorLine: controller.line,
              cursorColumn: controller.col,
              cursorAffinity: controller.selection.affinity,
              placeholder: widget.placeholder,
              height: widget.height,
              maxHeight: widget.maxHeight,
              width: widget.width,
              softWrap: widget.softWrap,
              color: widget.color ?? palette.text,
              // `theme?.surface`, not `palette.surface`: with no ancestor
              // Theme the field must keep painting no fill at all, which no
              // color can express.
              backgroundColor: widget.backgroundColor ?? theme?.surface,
              cursorColor: widget.cursorColor ?? palette.cursor,
              cursorStyle: widget.cursorStyle,
              focused: focusNode.hasFocus,
              scrollLine: _vViewport.scrollOffset,
              scrollCell: _hViewport.scrollOffset,
            ),
          ),
        ),
      ),
    );
  }
}

class _TextAreaLeaf extends RenderObjectWidget {
  const _TextAreaLeaf({
    required this.layoutMetrics,
    required this.lines,
    required this.cursorLine,
    required this.cursorColumn,
    required this.cursorAffinity,
    required this.placeholder,
    required this.height,
    required this.maxHeight,
    required this.width,
    required this.softWrap,
    required this.color,
    required this.backgroundColor,
    required this.cursorColor,
    required this.cursorStyle,
    required this.focused,
    required this.scrollLine,
    required this.scrollCell,
  });

  final _TextAreaLayoutMetrics layoutMetrics;
  final List<String> lines;
  final int cursorLine;
  final int cursorColumn;
  final TextAffinity cursorAffinity;
  final String? placeholder;
  final int height;
  final int? maxHeight;
  final int? width;
  final bool softWrap;
  final Color color;
  final Color? backgroundColor;
  final Color cursorColor;
  final CursorStyle cursorStyle;
  final bool focused;
  final int scrollLine;
  final int scrollCell;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderTextArea._forWidget(
        layoutMetrics: layoutMetrics,
        cursorController: context.owner.cursorController,
        lines: lines,
        cursorLine: cursorLine,
        cursorColumn: cursorColumn,
        cursorAffinity: cursorAffinity,
        placeholder: placeholder,
        heightLines: height,
        maxHeightLines: maxHeight,
        explicitWidth: width,
        softWrap: softWrap,
        color: color,
        backgroundColor: backgroundColor,
        cursorColor: cursorColor,
        cursorStyle: cursorStyle,
        focused: focused,
        scrollLine: scrollLine,
        scrollCell: scrollCell,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderTextArea renderObject,
  ) {
    renderObject
      .._updateWidgetGeometry(
        heightLines: height,
        maxHeightLines: maxHeight,
        explicitWidth: width,
        softWrap: softWrap,
      )
      ..lines = lines
      ..cursorLine = cursorLine
      ..cursorColumn = cursorColumn
      ..cursorAffinity = cursorAffinity
      ..placeholder = placeholder
      ..color = color
      ..backgroundColor = backgroundColor
      ..cursorColor = cursorColor
      ..cursorStyle = cursorStyle
      ..focused = focused
      ..scrollLine = scrollLine
      ..scrollCell = scrollCell;
  }
}

/// RenderBox behind [TextArea]. Paints the visible window of [_lines]
/// and drives cursor visibility. Scroll offsets are computed by the State
/// before each rebuild. The render object passively publishes completed
/// layout dimensions but never schedules State work.
///
/// Horizontal scroll is in TERMINAL CELLS (so wide CJK glyphs contribute 2
/// cells), vertical scroll is in lines.
class RenderTextArea extends RenderBox {
  /// Snapshots [lines], validates extents, and borrows the cursor controller.
  RenderTextArea({
    required CursorController cursorController,
    required List<String> lines,
    required int cursorLine,
    required int cursorColumn,
    required String? placeholder,
    required int heightLines,
    required int? explicitWidth,
    required Color color,
    required Color? backgroundColor,
    required Color cursorColor,
    required CursorStyle cursorStyle,
    required bool focused,
    required int scrollLine,
    required int scrollCell,
  }) : this._forWidget(
         layoutMetrics: null,
         cursorController: cursorController,
         lines: lines,
         cursorLine: cursorLine,
         cursorColumn: cursorColumn,
         cursorAffinity: TextAffinity.downstream,
         placeholder: placeholder,
         heightLines: heightLines,
         maxHeightLines: null,
         explicitWidth: explicitWidth,
         softWrap: false,
         color: color,
         backgroundColor: backgroundColor,
         cursorColor: cursorColor,
         cursorStyle: cursorStyle,
         focused: focused,
         scrollLine: scrollLine,
         scrollCell: scrollCell,
       );

  RenderTextArea._forWidget({
    required _TextAreaLayoutMetrics? layoutMetrics,
    required CursorController cursorController,
    required List<String> lines,
    required int cursorLine,
    required int cursorColumn,
    required TextAffinity cursorAffinity,
    required String? placeholder,
    required int heightLines,
    required int? maxHeightLines,
    required int? explicitWidth,
    required bool softWrap,
    required Color color,
    required Color? backgroundColor,
    required Color cursorColor,
    required CursorStyle cursorStyle,
    required bool focused,
    required int scrollLine,
    required int scrollCell,
  }) : _layoutMetrics = layoutMetrics,
       _cursorController = cursorController,
       _lines = List<String>.unmodifiable(lines),
       _cursorLine = cursorLine,
       _cursorColumn = cursorColumn,
       _cursorAffinity = cursorAffinity,
       _placeholder = placeholder,
       _heightLines = heightLines,
       _maxHeightLines = maxHeightLines,
       _explicitWidth = explicitWidth,
       _softWrap = softWrap,
       _color = color,
       _backgroundColor = backgroundColor,
       _cursorColor = cursorColor,
       _cursorStyle = cursorStyle,
       _focused = focused,
       _scrollLine = scrollLine,
       _scrollCell = scrollCell {
    requireNonNegativeExtent(_heightLines, 'heightLines');
    _requireValidMaxHeight(_heightLines, _maxHeightLines);
    _requireNonNegativeNullableExtent(_explicitWidth, 'explicitWidth');
  }

  final _TextAreaLayoutMetrics? _layoutMetrics;
  final CursorController _cursorController;
  List<String> _lines;
  int _cursorLine;
  int _cursorColumn;
  TextAffinity _cursorAffinity;
  String? _placeholder;
  int _heightLines;
  int? _maxHeightLines;
  int? _explicitWidth;
  bool _softWrap;
  Color _color;
  Color? _backgroundColor;
  Color _cursorColor;
  CursorStyle _cursorStyle;
  bool _focused;
  int _scrollLine;
  int _scrollCell;
  _TextAreaVisualLayout? _visualLayout;
  int? _visualLayoutWidth;

  set lines(List<String> v) {
    if (_sameLines(_lines, v)) return;
    _lines = List<String>.unmodifiable(v);
    _invalidateVisualLayout();
    if (_softWrap || _maxHeightLines != null) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  set cursorLine(int v) {
    if (_cursorLine == v) return;
    _cursorLine = v;
    markNeedsPaint();
  }

  set cursorColumn(int v) {
    if (_cursorColumn == v) return;
    _cursorColumn = v;
    markNeedsPaint();
  }

  set cursorAffinity(TextAffinity v) {
    if (_cursorAffinity == v) return;
    _cursorAffinity = v;
    markNeedsPaint();
  }

  set placeholder(String? v) {
    if (_placeholder == v) return;
    _placeholder = v;
    markNeedsPaint();
  }

  set heightLines(int v) {
    requireNonNegativeExtent(v, 'heightLines');
    _requireValidMaxHeight(v, _maxHeightLines);
    if (_heightLines == v) return;
    _heightLines = v;
    markNeedsLayout();
  }

  set explicitWidth(int? v) {
    _requireNonNegativeNullableExtent(v, 'explicitWidth');
    if (_explicitWidth == v) return;
    _explicitWidth = v;
    _invalidateVisualLayout();
    markNeedsLayout();
  }

  void _updateWidgetGeometry({
    required int heightLines,
    required int? maxHeightLines,
    required int? explicitWidth,
    required bool softWrap,
  }) {
    requireNonNegativeExtent(heightLines, 'heightLines');
    _requireValidMaxHeight(heightLines, maxHeightLines);
    _requireNonNegativeNullableExtent(explicitWidth, 'explicitWidth');
    final changed =
        _heightLines != heightLines ||
        _maxHeightLines != maxHeightLines ||
        _explicitWidth != explicitWidth ||
        _softWrap != softWrap;
    if (!changed) return;
    _heightLines = heightLines;
    _maxHeightLines = maxHeightLines;
    _explicitWidth = explicitWidth;
    _softWrap = softWrap;
    _invalidateVisualLayout();
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

  set cursorColor(Color v) {
    if (_cursorColor == v) return;
    _cursorColor = v;
    markNeedsPaint();
  }

  set cursorStyle(CursorStyle v) {
    if (_cursorStyle == v) return;
    _cursorStyle = v;
    markNeedsPaint();
  }

  set focused(bool v) {
    if (_focused == v) return;
    _focused = v;
    markNeedsPaint();
  }

  set scrollLine(int v) {
    if (_scrollLine == v) return;
    _scrollLine = v;
    markNeedsPaint();
  }

  set scrollCell(int v) {
    if (_scrollCell == v) return;
    _scrollCell = v;
    markNeedsPaint();
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    // Fall back to minWidth when both the explicit width and the parent's
    // maxWidth are unspecified so we still produce a definite size.
    final w = _explicitWidth ?? constraints.maxWidth ?? constraints.minWidth;
    final constrainedWidth = constraints.constrainWidth(w);
    final layout = _ensureVisualLayout(constrainedWidth);
    final desiredHeight = _maxHeightLines == null
        ? _heightLines
        : layout.lines.length.clamp(_heightLines, _maxHeightLines!);
    size = Size(constrainedWidth, constraints.constrainHeight(desiredHeight));
    _layoutMetrics?.publish(size);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final originX = offset.dx + x;
    final originY = offset.dy + y;
    final canvas = context.canvas;
    final visualLayout = _ensureVisualLayout(width);
    final cursor = visualLayout.positionForOffset(
      _cursorSourceOffset(),
      affinity: _cursorAffinity,
    );
    var effectiveScrollLine = _scrollLine.clamp(
      0,
      (visualLayout.lines.length - height).clamp(0, visualLayout.lines.length),
    );
    if (_focused && (_softWrap || _maxHeightLines != null) && height > 0) {
      if (cursor.row < effectiveScrollLine) {
        effectiveScrollLine = cursor.row;
      } else if (cursor.row >= effectiveScrollLine + height) {
        effectiveScrollLine = cursor.row - height + 1;
      }
    }
    var effectiveScrollCell = _softWrap ? 0 : _scrollCell;
    if (_focused && _maxHeightLines != null && !_softWrap && width > 0) {
      if (cursor.cell < effectiveScrollCell) {
        effectiveScrollCell = cursor.cell;
      } else if (cursor.cell >= effectiveScrollCell + width) {
        effectiveScrollCell = cursor.cell - width + 1;
      }
    }

    if (_backgroundColor != null) {
      canvas.fillRect(
        Rect.fromLTWH(originX, originY, width, height),
        _backgroundColor!,
      );
    }

    final isEmpty = _lines.length == 1 && _lines[0].isEmpty;
    if (isEmpty && _placeholder != null && !_focused) {
      // Render placeholder dimmed on first row only, cell-aware.
      final dim = Color(
        _color.r * 0.5,
        _color.g * 0.5,
        _color.b * 0.5,
        _color.a,
      );
      final ph = _placeholder!;
      var col = 0;
      for (final cluster in ph.characters) {
        final cw = terminalCellWidth(cluster);
        if (col + cw > width) break;
        canvas.drawText(
          cluster,
          Offset(originX + col, originY),
          dim,
          background: _backgroundColor,
        );
        col += cw;
      }
    } else {
      for (var row = 0; row < height; row++) {
        final lineIdx = effectiveScrollLine + row;
        if (lineIdx >= visualLayout.lines.length) break;
        final line = visualLayout.lines[lineIdx];
        var cellAccum = 0;
        var paintedCol = 0;
        paintLine:
        for (final run in line.runs) {
          for (final cluster in run.text.characters) {
            final clusterWidth = terminalCellWidth(cluster);
            if (cellAccum + clusterWidth <= effectiveScrollCell) {
              cellAccum += clusterWidth;
              continue;
            }
            // If a wide cluster straddles the left edge, drop it whole.
            if (cellAccum < effectiveScrollCell) {
              cellAccum += clusterWidth;
              continue;
            }
            if (paintedCol + clusterWidth > width) break paintLine;
            canvas.drawText(
              cluster,
              Offset(originX + paintedCol, originY + row),
              _color,
              background: _backgroundColor,
            );
            paintedCol += clusterWidth;
            cellAccum += clusterWidth;
          }
        }
      }
    }

    if (_focused) {
      final cursorRow = cursor.row - effectiveScrollLine;
      final cursorCell = _softWrap && width > 0 && cursor.cell >= width
          ? width - 1
          : cursor.cell;
      final cursorCol = cursorCell - effectiveScrollCell;
      if (cursorRow >= 0 &&
          cursorRow < height &&
          cursorCol >= 0 &&
          cursorCol < width) {
        _cursorController.showCursor(
          this,
          originX + cursorCol,
          originY + cursorRow,
          style: _cursorStyle,
          color: _cursorColor,
        );
      } else {
        _cursorController.hideCursorFor(this);
      }
    } else {
      _cursorController.hideCursorFor(this);
    }
  }

  @override
  void detach() {
    _cursorController.hideCursorFor(this);
    super.detach();
  }

  static bool _sameLines(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  int _cursorSourceOffset() {
    if (_lines.isEmpty) return 0;
    final lineIndex = _cursorLine.clamp(0, _lines.length - 1);
    var offset = 0;
    for (var index = 0; index < lineIndex; index++) {
      offset += _lines[index].length + 1;
    }
    final line = _lines[lineIndex];
    final clampedColumn = _cursorColumn.clamp(0, line.characters.length);
    return offset + line.characters.take(clampedColumn).toString().length;
  }

  _TextAreaVisualLayout _ensureVisualLayout(int width) {
    final current = _visualLayout;
    if (current != null && _visualLayoutWidth == width) return current;
    final next = _TextAreaVisualLayout.compute(
      _lines.join('\n'),
      width: width,
      softWrap: _softWrap,
    );
    _visualLayout = next;
    _visualLayoutWidth = width;
    return next;
  }

  void _invalidateVisualLayout() {
    _visualLayout = null;
    _visualLayoutWidth = null;
  }
}

final class _TextAreaVisualLayout {
  const _TextAreaVisualLayout._({required this.text, required this.lines});

  factory _TextAreaVisualLayout.compute(
    String text, {
    required int width,
    required bool softWrap,
  }) {
    final maxWidth = softWrap && width > 0 ? width : null;
    final laidOut = const TextLayoutEngine().layout(
      TextSpan(text: text),
      BoxConstraints(maxWidth: maxWidth),
    );
    final hardBreakOffsets = '\n'
        .allMatches(text)
        .map((match) => match.start)
        .toSet();
    final lines = <_TextAreaVisualLine>[];
    var sourceCursor = 0;
    for (final line in laidOut.lines) {
      final sourceStart = line.runs.isEmpty
          ? sourceCursor
          : line.runs.first.sourceStart;
      final sourceEnd = line.runs.isEmpty
          ? sourceStart
          : line.runs.last.sourceEnd;
      lines.add(
        _TextAreaVisualLine(
          runs: line.runs,
          sourceStart: sourceStart,
          sourceEnd: sourceEnd,
          width: line.width,
        ),
      );
      sourceCursor = sourceEnd;
      if (hardBreakOffsets.contains(sourceCursor)) {
        sourceCursor++;
      }
    }
    if (text.endsWith('\n')) {
      lines.add(
        _TextAreaVisualLine(
          runs: const [],
          sourceStart: text.length,
          sourceEnd: text.length,
          width: 0,
        ),
      );
    } else if (softWrap &&
        width > 0 &&
        lines.isNotEmpty &&
        lines.last.width >= width &&
        lines.last.sourceEnd == text.length) {
      lines.add(
        _TextAreaVisualLine(
          runs: const [],
          sourceStart: text.length,
          sourceEnd: text.length,
          width: 0,
        ),
      );
    }
    return _TextAreaVisualLayout._(text: text, lines: List.unmodifiable(lines));
  }

  final String text;
  final List<_TextAreaVisualLine> lines;

  TextAffinity affinityForPosition(int row, int sourceOffset) {
    final line = lines[row];
    final nextRow = row + 1;
    final sharesNextBoundary =
        sourceOffset == line.sourceEnd &&
        nextRow < lines.length &&
        lines[nextRow].sourceStart == sourceOffset;
    return sharesNextBoundary ? TextAffinity.upstream : TextAffinity.downstream;
  }

  ({int row, int cell}) positionForOffset(
    int sourceOffset, {
    TextAffinity affinity = TextAffinity.downstream,
  }) {
    final offset = sourceOffset.clamp(0, text.length);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (offset < line.sourceEnd) {
        return (row: index, cell: line.cellForSourceOffset(offset));
      }
      if (offset == line.sourceEnd) {
        final hasNext = index + 1 < lines.length;
        final sharesSoftBoundary =
            hasNext && lines[index + 1].sourceStart == offset;
        if (sharesSoftBoundary && affinity == TextAffinity.downstream) {
          return (row: index + 1, cell: 0);
        }
        return (row: index, cell: line.width);
      }
    }
    final last = lines.last;
    return (row: lines.length - 1, cell: last.width);
  }
}

final class _TextAreaVisualLine {
  _TextAreaVisualLine({
    required List<TextLayoutRun> runs,
    required this.sourceStart,
    required this.sourceEnd,
    required this.width,
  }) : runs = List.unmodifiable(runs);

  final List<TextLayoutRun> runs;
  final int sourceStart;
  final int sourceEnd;
  final int width;

  int cellForSourceOffset(int offset) {
    var cell = 0;
    for (final run in runs) {
      var sourceOffset = run.sourceStart;
      for (final cluster in run.text.characters) {
        final sourceEnd = sourceOffset + cluster.length;
        if (offset < sourceEnd) return cell;
        cell += terminalCellWidth(cluster);
        sourceOffset = sourceEnd;
      }
    }
    return cell;
  }

  int sourceOffsetForCell(int targetCell) {
    if (runs.isEmpty || targetCell <= 0) return sourceStart;
    var cell = 0;
    for (final run in runs) {
      var sourceOffset = run.sourceStart;
      for (final cluster in run.text.characters) {
        final clusterWidth = terminalCellWidth(cluster);
        final cellEnd = cell + clusterWidth;
        final sourceEnd = sourceOffset + cluster.length;
        if (targetCell < cellEnd) {
          return targetCell - cell > cellEnd - targetCell
              ? sourceEnd
              : sourceOffset;
        }
        if (targetCell == cellEnd) return sourceEnd;
        cell = cellEnd;
        sourceOffset = sourceEnd;
      }
    }
    return sourceEnd;
  }
}

void _requireNonNegativeNullableExtent(int? value, String name) {
  if (value != null) {
    requireNonNegativeExtent(value, name);
  }
}

void _requireValidMaxHeight(int height, int? maxHeight) {
  if (maxHeight == null) return;
  requireNonNegativeExtent(maxHeight, 'maxHeightLines');
  if (maxHeight < height) {
    throw ArgumentError.value(
      maxHeight,
      'maxHeightLines',
      'must be greater than or equal to heightLines',
    );
  }
}
