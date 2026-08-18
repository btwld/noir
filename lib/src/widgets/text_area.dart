// ignore_for_file: avoid_setters_without_getters
import 'package:characters/characters.dart';

import '../core/color.dart';
import '../core/cursor.dart';
import '../core/grapheme_metrics.dart';
import '../foundation/text_editing_controller.dart';
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
import 'theme.dart';
import 'viewport.dart';

/// Multi-line text input, parity with OpenTUI-React `<textarea>`.
///
/// Keys (when focused):
/// - Printable chars insert at cursor.
/// - Backspace / Delete edit characters and join lines.
/// - Enter inserts a newline; Ctrl+Enter fires [onSubmit].
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
    this.width,
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
       assert(width == null || width >= 0);

  /// The controller that owns this field's text and selection.
  final TextEditingController? controller;

  /// Initial/current value when [controller] is not supplied.
  final String? value;

  /// Dimmed hint text shown when the field is empty and unfocused.
  final String? placeholder;

  /// Visible height of the field in rows. Defaults to 5.
  final int height;

  /// Explicit width in cells. Expands to available width when null.
  final int? width;

  /// When true, the field renders text but rejects edits. Defaults to false.
  final bool readOnly;

  /// Number of spaces inserted for a tab. Defaults to 2.
  final int tabSize;

  /// Foreground color of the text. Falls back to [ThemeData.text], then to
  /// [Color.white].
  final Color? color;

  /// Fill color painted behind the field. No fill when null.
  final Color? backgroundColor;

  /// Color of the cursor. Falls back to [ThemeData.cursor], then to
  /// [Color.white].
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

  /// Total content height in lines (1 row per model line — no wrap yet).
  int _contentLineCount() => controller.lines.length;

  /// Scrolls the vertical and horizontal viewports so the cursor's line and
  /// column are visible. The horizontal content extent is derived from the
  /// cursor cell alone, since "scroll into view" only cares about the cursor.
  void _ensureCursorVisible() {
    final cells = _viewportCells;
    _vViewport.viewportExtent = cells.height;
    _vViewport.contentExtent = _contentLineCount();
    _vViewport.ensureVisible(controller.line, controller.line + 1);

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

  @override
  Widget build(BuildContext context) {
    requireUsableSelectionForBuild();
    final conn = connection;
    final theme = Theme.maybeOf(context);
    return Shortcuts(
      shortcuts: conn.shortcuts,
      child: Actions(
        actions: conn.actions,
        child: Focus(
          focusNode: focusNode,
          autofocus: widget.autofocus,
          onFocusChange: handleFocusChange,
          child: PointerListener(
            onPointerDown: handlePointerDown,
            child: _TextAreaLeaf(
              layoutMetrics: _layoutMetrics,
              lines: controller.lines,
              cursorLine: controller.line,
              cursorColumn: controller.col,
              placeholder: widget.placeholder,
              height: widget.height,
              width: widget.width,
              color: widget.color ?? theme?.text ?? Color.white,
              // `maybeOf`, not `of`: an unthemed field keeps its original
              // no-fill rendering rather than gaining a surface.
              backgroundColor: widget.backgroundColor ?? theme?.surface,
              cursorColor: widget.cursorColor ?? theme?.cursor ?? Color.white,
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
    required this.placeholder,
    required this.height,
    required this.width,
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
  final String? placeholder;
  final int height;
  final int? width;
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
        placeholder: placeholder,
        heightLines: height,
        explicitWidth: width,
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
      ..lines = lines
      ..cursorLine = cursorLine
      ..cursorColumn = cursorColumn
      ..placeholder = placeholder
      ..heightLines = height
      ..explicitWidth = width
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
         placeholder: placeholder,
         heightLines: heightLines,
         explicitWidth: explicitWidth,
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
  }) : _layoutMetrics = layoutMetrics,
       _cursorController = cursorController,
       _lines = List<String>.unmodifiable(lines),
       _cursorLine = cursorLine,
       _cursorColumn = cursorColumn,
       _placeholder = placeholder,
       _heightLines = heightLines,
       _explicitWidth = explicitWidth,
       _color = color,
       _backgroundColor = backgroundColor,
       _cursorColor = cursorColor,
       _cursorStyle = cursorStyle,
       _focused = focused,
       _scrollLine = scrollLine,
       _scrollCell = scrollCell {
    requireNonNegativeExtent(_heightLines, 'heightLines');
    _requireNonNegativeNullableExtent(_explicitWidth, 'explicitWidth');
  }

  final _TextAreaLayoutMetrics? _layoutMetrics;
  final CursorController _cursorController;
  List<String> _lines;
  int _cursorLine;
  int _cursorColumn;
  String? _placeholder;
  int _heightLines;
  int? _explicitWidth;
  Color _color;
  Color? _backgroundColor;
  Color _cursorColor;
  CursorStyle _cursorStyle;
  bool _focused;
  int _scrollLine;
  int _scrollCell;

  set lines(List<String> v) {
    if (_sameLines(_lines, v)) return;
    _lines = List<String>.unmodifiable(v);
    markNeedsPaint();
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

  set placeholder(String? v) {
    if (_placeholder == v) return;
    _placeholder = v;
    markNeedsPaint();
  }

  set heightLines(int v) {
    requireNonNegativeExtent(v, 'heightLines');
    if (_heightLines == v) return;
    _heightLines = v;
    markNeedsLayout();
  }

  set explicitWidth(int? v) {
    _requireNonNegativeNullableExtent(v, 'explicitWidth');
    if (_explicitWidth == v) return;
    _explicitWidth = v;
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
    size = Size(
      constraints.constrainWidth(w),
      constraints.constrainHeight(_heightLines),
    );
    _layoutMetrics?.publish(size);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final originX = offset.dx + x;
    final originY = offset.dy + y;
    final canvas = context.canvas;

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
        canvas.setCell(
          Offset(originX + col, originY),
          cluster,
          dim,
          _backgroundColor ?? Color.transparent,
          0,
        );
        col += cw;
      }
    } else {
      for (var row = 0; row < height; row++) {
        final lineIdx = _scrollLine + row;
        if (lineIdx >= _lines.length) break;
        final line = _lines[lineIdx];
        var cellAccum = 0;
        var paintedCol = 0;
        for (final cluster in line.characters) {
          final cw = terminalCellWidth(cluster);
          if (cellAccum + cw <= _scrollCell) {
            cellAccum += cw;
            continue;
          }
          // The cluster crosses or starts past the scroll boundary. If it
          // straddles the left edge (wide cluster at the boundary), drop it.
          if (cellAccum < _scrollCell) {
            cellAccum += cw;
            continue;
          }
          if (paintedCol + cw > width) break;
          canvas.setCell(
            Offset(originX + paintedCol, originY + row),
            cluster,
            _color,
            _backgroundColor ?? Color.transparent,
            0,
          );
          paintedCol += cw;
          cellAccum += cw;
        }
      }
    }

    if (_focused) {
      final cursorRow = _cursorLine - _scrollLine;
      final line = _lines[_cursorLine.clamp(0, _lines.length - 1)];
      final cursorAbsoluteCell = graphemeIndexToCell(line, _cursorColumn);
      final cursorCol = cursorAbsoluteCell - _scrollCell;
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
}

void _requireNonNegativeNullableExtent(int? value, String name) {
  if (value != null) {
    requireNonNegativeExtent(value, name);
  }
}
