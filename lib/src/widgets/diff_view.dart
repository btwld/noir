import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../core/color.dart';
import '../core/input.dart';
import '../core/terminal_style.dart';
import '../foundation/disposable.dart';
import '../foundation/selected_text.dart';
import '../foundation/text_selection.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import 'code_view.dart';
import 'document_view.dart';
import 'focus_node_owner_mixin.dart';
import 'pointer_listener.dart';
import 'row_column.dart';
import 'scroll_box.dart';
import 'text_span.dart';
import 'text_style.dart';
import 'theme.dart';

/// Presentation mode for [DiffView].
enum DiffViewMode {
  /// Show one prefixed stream of context, deletions, and additions.
  unified,

  /// Align deletion and addition runs into left and right columns.
  split,
}

/// Semantic kind of one unified-diff line.
enum DiffLineKind {
  /// Unchanged context present on both sides.
  context,

  /// A line present only in the new file.
  addition,

  /// A line present only in the old file.
  deletion,

  /// The `No newline at end of file` marker.
  noNewlineMarker,
}

/// Immutable line in a parsed diff hunk.
@immutable
final class DiffLine {
  /// Creates a presentation line with optional old/new source coordinates.
  const DiffLine({
    required this.kind,
    required this.text,
    this.oldLineNumber,
    this.newLineNumber,
  });

  /// Change kind.
  final DiffLineKind kind;

  /// Content without the unified-diff prefix.
  final String text;

  /// One-based old-file line number when present.
  final int? oldLineNumber;

  /// One-based new-file line number when present.
  final int? newLineNumber;
}

/// Immutable unified-diff hunk.
@immutable
final class DiffHunk {
  /// Creates a hunk and snapshots [lines].
  DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required List<DiffLine> lines,
    this.header = '',
  }) : lines = List<DiffLine>.unmodifiable(lines);

  /// One-based first old-file line.
  final int oldStart;

  /// Old-file range length.
  final int oldCount;

  /// One-based first new-file line.
  final int newStart;

  /// New-file range length.
  final int newCount;

  /// Optional trailing hunk heading.
  final String header;

  /// Lines in patch order.
  final List<DiffLine> lines;
}

/// Immutable file in a parsed diff document.
@immutable
final class DiffFile {
  /// Creates a file presentation and snapshots [hunks].
  DiffFile({
    required this.oldPath,
    required this.newPath,
    required List<DiffHunk> hunks,
  }) : hunks = List<DiffHunk>.unmodifiable(hunks);

  /// Old path, or null for an added file.
  final String? oldPath;

  /// New path, or null for a deleted file.
  final String? newPath;

  /// Parsed hunks.
  final List<DiffHunk> hunks;
}

/// Immutable collection of files parsed from one patch.
@immutable
final class DiffDocument {
  /// Creates a document and snapshots [files].
  DiffDocument(List<DiffFile> files)
    : files = List<DiffFile>.unmodifiable(files);

  /// Files in patch order.
  final List<DiffFile> files;
}

/// Parses standard and Git-flavoured unified patch text.
final class UnifiedDiffParser {
  /// Creates the dependency-free parser.
  const UnifiedDiffParser();

  /// Parses [patch], tolerating Git metadata outside hunks.
  DiffDocument parse(String patch) {
    final files = <DiffFile>[];
    String? oldPath;
    String? newPath;
    final hunks = <DiffHunk>[];

    void finishFile() {
      if (oldPath == null && newPath == null && hunks.isEmpty) return;
      files.add(DiffFile(oldPath: oldPath, newPath: newPath, hunks: hunks));
      oldPath = null;
      newPath = null;
      hunks.clear();
    }

    final lines = patch.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.startsWith('diff --git ')) {
        finishFile();
        final paths = _parseGitPathTokens(line.substring('diff --git '.length));
        if (paths.length >= 2) {
          oldPath = _normalizeDiffPath(paths[0]);
          newPath = _normalizeDiffPath(paths[1]);
        }
        continue;
      }
      if (line.startsWith('--- ')) {
        if (hunks.isNotEmpty) finishFile();
        oldPath = _parseHeaderPath(line.substring(4));
        continue;
      }
      if (line.startsWith('+++ ')) {
        newPath = _parseHeaderPath(line.substring(4));
        continue;
      }
      final match = _hunkHeader.firstMatch(line);
      if (match == null) continue;
      final oldStart = int.parse(match.group(1)!);
      final oldCount = int.parse(match.group(2) ?? '1');
      final newStart = int.parse(match.group(3)!);
      final newCount = int.parse(match.group(4) ?? '1');
      var oldLine = oldStart;
      var newLine = newStart;
      var oldConsumed = 0;
      var newConsumed = 0;
      final hunkLines = <DiffLine>[];
      index++;
      while (index < lines.length) {
        final value = lines[index];
        if (_hunkHeader.hasMatch(value) || value.startsWith('diff --git ')) {
          index--;
          break;
        }
        if (value.startsWith(r'\ No newline')) {
          hunkLines.add(
            DiffLine(kind: DiffLineKind.noNewlineMarker, text: value),
          );
        } else if (oldConsumed >= oldCount && newConsumed >= newCount) {
          index--;
          break;
        } else if (value.startsWith('+')) {
          hunkLines.add(
            DiffLine(
              kind: DiffLineKind.addition,
              text: value.substring(1),
              newLineNumber: newLine++,
            ),
          );
          newConsumed++;
        } else if (value.startsWith('-')) {
          hunkLines.add(
            DiffLine(
              kind: DiffLineKind.deletion,
              text: value.substring(1),
              oldLineNumber: oldLine++,
            ),
          );
          oldConsumed++;
        } else if (value.startsWith(' ')) {
          hunkLines.add(
            DiffLine(
              kind: DiffLineKind.context,
              text: value.substring(1),
              oldLineNumber: oldLine++,
              newLineNumber: newLine++,
            ),
          );
          oldConsumed++;
          newConsumed++;
        }
        index++;
      }
      hunks.add(
        DiffHunk(
          oldStart: oldStart,
          oldCount: oldCount,
          newStart: newStart,
          newCount: newCount,
          header: match.group(5)?.trim() ?? '',
          lines: hunkLines,
        ),
      );
    }
    finishFile();
    return DiffDocument(files);
  }
}

final _hunkHeader = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$');

String? _parseHeaderPath(String value) {
  final field = value.split('\t').first.trim();
  final path = field.startsWith('"')
      ? (_parseGitPathTokens(field).firstOrNull ?? field)
      : field;
  return path == '/dev/null' ? null : _normalizeDiffPath(path);
}

String _normalizeDiffPath(String path) =>
    path.startsWith('a/') || path.startsWith('b/') ? path.substring(2) : path;

List<String> _parseGitPathTokens(String value) {
  final paths = <String>[];
  var index = 0;
  while (index < value.length) {
    while (index < value.length &&
        (value.codeUnitAt(index) == 0x20 || value.codeUnitAt(index) == 0x09)) {
      index++;
    }
    if (index >= value.length) break;
    final quoted = value.codeUnitAt(index) == 0x22;
    if (quoted) index++;
    final bytes = <int>[];
    while (index < value.length) {
      final codeUnit = value.codeUnitAt(index);
      if (quoted && codeUnit == 0x22) {
        index++;
        break;
      }
      if (!quoted && (codeUnit == 0x20 || codeUnit == 0x09)) break;
      if (codeUnit != 0x5c || index + 1 >= value.length) {
        var rune = codeUnit;
        var codeUnits = 1;
        if (codeUnit >= 0xd800 &&
            codeUnit <= 0xdbff &&
            index + 1 < value.length) {
          final low = value.codeUnitAt(index + 1);
          if (low >= 0xdc00 && low <= 0xdfff) {
            rune = 0x10000 + ((codeUnit - 0xd800) << 10) + low - 0xdc00;
            codeUnits = 2;
          }
        }
        bytes.addAll(utf8.encode(String.fromCharCode(rune)));
        index += codeUnits;
        continue;
      }

      index++;
      final escaped = value.codeUnitAt(index);
      if (escaped >= 0x30 && escaped <= 0x37) {
        var octal = 0;
        var digits = 0;
        while (index < value.length && digits < 3) {
          final digit = value.codeUnitAt(index);
          if (digit < 0x30 || digit > 0x37) break;
          octal = octal * 8 + digit - 0x30;
          digits++;
          index++;
        }
        bytes.add(octal);
        continue;
      }
      bytes.add(switch (escaped) {
        0x61 => 0x07,
        0x62 => 0x08,
        0x74 => 0x09,
        0x6e => 0x0a,
        0x76 => 0x0b,
        0x66 => 0x0c,
        0x72 => 0x0d,
        _ => escaped,
      });
      index++;
    }
    paths.add(utf8.decode(bytes, allowMalformed: true));
  }
  return paths;
}

/// Imperative hunk navigation for [DiffView].
final class DiffViewController implements Disposable {
  void Function(int hunkIndex)? _jump;
  int? _pendingHunk;

  /// Scrolls to the zero-based hunk across all files in document order.
  void jumpToHunk(int hunkIndex) {
    if (hunkIndex < 0) {
      throw ArgumentError.value(hunkIndex, 'hunkIndex', 'must be non-negative');
    }
    final jump = _jump;
    if (jump == null) {
      _pendingHunk = hunkIndex;
    } else {
      jump(hunkIndex);
    }
  }

  void _attach(void Function(int hunkIndex) jump) {
    _jump = jump;
    final pending = _pendingHunk;
    _pendingHunk = null;
    if (pending != null) jump(pending);
  }

  void _detach(void Function(int hunkIndex) jump) {
    if (_jump == jump) _jump = null;
  }

  @override
  void dispose() {
    _jump = null;
    _pendingHunk = null;
  }
}

/// Called for an activated diff line.
typedef DiffLineCallback =
    void Function(DiffFile file, DiffHunk hunk, DiffLine line);

/// Called for an activated hunk heading.
typedef DiffHunkCallback = void Function(DiffFile file, DiffHunk hunk);

/// Builds a custom row from the semantic diff row and Noir's default row.
typedef DiffRowBuilder =
    Widget Function(
      BuildContext context,
      DiffFile file,
      DiffHunk hunk,
      DiffLine? line,
      Widget defaultRow,
    );

/// Scrollable unified or aligned split diff presentation.
class DiffView extends StatefulWidget {
  /// Configures diff rendering, highlighting, navigation, and selection.
  const DiffView({
    required this.document,
    super.key,
    this.mode = DiffViewMode.unified,
    this.controller,
    this.scrollController,
    this.highlighter = const PlainTextCodeHighlighter(),
    this.language,
    this.wrap = false,
    this.selectable = true,
    this.showLineNumbers = true,
    this.splitColumnWidth = 40,
    this.focusNode,
    this.autofocus = false,
    this.selectionForegroundColor,
    this.selectionBackgroundColor,
    this.onSelectionChanged,
    this.onCopy,
    this.onHighlightError,
    this.onLine,
    this.onHunk,
    this.rowBuilder,
  }) : assert(splitColumnWidth > 0);

  /// Parsed presentation model.
  final DiffDocument document;

  /// Unified or split presentation.
  final DiffViewMode mode;

  /// Optional hunk navigation owner.
  final DiffViewController? controller;

  /// Optional owner for the diff's vertical scroll position.
  final ScrollController? scrollController;

  /// Optional syntax range producer.
  final CodeHighlighter highlighter;

  /// Language identifier passed to [highlighter].
  final String? language;

  /// Whether long rows soft-wrap.
  final bool wrap;

  /// Whether document text is selectable.
  final bool selectable;

  /// Whether source coordinates are shown in row prefixes.
  final bool showLineNumbers;

  /// Content cells reserved for each side in split mode.
  final int splitColumnWidth;

  /// Caller-owned focus node.
  final FocusNode? focusNode;

  /// Whether the diff requests focus after mounting.
  final bool autofocus;

  /// Selected text foreground override.
  final Color? selectionForegroundColor;

  /// Selected text background override.
  final Color? selectionBackgroundColor;

  /// Receives the current non-empty selection.
  final void Function(SelectedText? selection)? onSelectionChanged;

  /// Receives explicit copy results.
  final SelectionCopyCallback? onCopy;

  /// Receives highlighting failures.
  final HighlightErrorCallback? onHighlightError;

  /// Receives pointer activation of a diff line.
  final DiffLineCallback? onLine;

  /// Receives pointer activation of a hunk heading.
  final DiffHunkCallback? onHunk;

  /// Optionally wraps or replaces each default hunk/line row.
  ///
  /// Replacement rows retain the diff's semantic selection and copy stream;
  /// arbitrary replacements own their visual selection presentation.
  final DiffRowBuilder? rowBuilder;

  @override
  State<DiffView> createState() => _DiffViewState();
}

final class _DiffViewState extends State<DiffView>
    with FocusNodeOwnerStateMixin<DiffView> {
  late ScrollController _scrollController;
  late bool _ownsScrollController;
  late _DiffPresentation _presentation;
  List<StyledTextRange> _syntax = const <StyledTextRange>[];
  int _highlightGeneration = 0;
  TextSelection? _selection;
  bool _dragging = false;
  int? _pendingHunk;
  bool _viewportReady = false;
  bool _pendingJumpScheduled = false;

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  void _jumpToHunk(int hunkIndex) {
    if (hunkIndex >= _presentation.hunkLines.length) return;
    if (!_viewportReady) {
      _pendingHunk = hunkIndex;
      return;
    }
    _pendingHunk = null;
    _applyHunkJump(hunkIndex);
  }

  void _applyHunkJump(int hunkIndex) {
    if (hunkIndex >= _presentation.hunkLines.length) return;
    final line = _presentation.hunkLines[hunkIndex];
    _scrollController.jumpTo(line.toDouble());
  }

  void _handleScrollMetricsChanged() {
    if (_scrollController.viewportExtent <= 0) return;
    _viewportReady = true;
    _schedulePendingJump();
  }

  void _schedulePendingJump() {
    if (_pendingHunk == null || _pendingJumpScheduled) return;
    _pendingJumpScheduled = true;
    scheduleMicrotask(() {
      _pendingJumpScheduled = false;
      if (!mounted || !_viewportReady) return;
      final pending = _pendingHunk;
      _pendingHunk = null;
      if (pending != null) _applyHunkJump(pending);
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _ownsScrollController = widget.scrollController == null;
    _scrollController.addListener(_handleScrollMetricsChanged);
    _presentation = _buildPresentation(widget);
    widget.controller?._attach(_jumpToHunk);
    _refreshHighlights();
  }

  @override
  void didUpdateWidget(DiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
    if ((widget.rowBuilder == null) != (oldWidget.rowBuilder == null)) {
      _retainFocusAcrossRendererChange();
    }
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller?._detach(_jumpToHunk);
      widget.controller?._attach(_jumpToHunk);
    }
    if (!identical(widget.scrollController, oldWidget.scrollController)) {
      _scrollController.removeListener(_handleScrollMetricsChanged);
      if (_ownsScrollController) _scrollController.dispose();
      _scrollController = widget.scrollController ?? ScrollController();
      _ownsScrollController = widget.scrollController == null;
      _scrollController.addListener(_handleScrollMetricsChanged);
      _viewportReady = false;
    }
    if (!identical(widget.document, oldWidget.document) ||
        widget.mode != oldWidget.mode ||
        widget.showLineNumbers != oldWidget.showLineNumbers ||
        widget.splitColumnWidth != oldWidget.splitColumnWidth) {
      _presentation = _buildPresentation(widget);
      final selection = _selection;
      if (selection != null && selection.end > _presentation.text.length) {
        _selection = null;
        widget.onSelectionChanged?.call(null);
      }
      _refreshHighlights();
    } else if (!identical(widget.highlighter, oldWidget.highlighter) ||
        widget.language != oldWidget.language) {
      _refreshHighlights();
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(_jumpToHunk);
    _scrollController.removeListener(_handleScrollMetricsChanged);
    if (_ownsScrollController) _scrollController.dispose();
    super.dispose();
  }

  void _refreshHighlights() {
    final generation = ++_highlightGeneration;
    _syntax = const <StyledTextRange>[];
    FutureOr<List<StyledTextRange>> result;
    try {
      result = widget.highlighter.highlight(
        _presentation.text,
        language: widget.language,
      );
    } on Object catch (error, stackTrace) {
      _highlightFailed(generation, error, stackTrace);
      return;
    }
    if (result is Future<List<StyledTextRange>>) {
      result.then(
        (ranges) => _acceptHighlights(generation, ranges),
        onError: (Object error, StackTrace stackTrace) =>
            _highlightFailed(generation, error, stackTrace),
      );
    } else {
      _acceptHighlights(generation, result);
    }
  }

  void _acceptHighlights(int generation, List<StyledTextRange> ranges) {
    if (!mounted || generation != _highlightGeneration) return;
    try {
      final validated = validateStyledTextRanges(_presentation.text, ranges);
      setState(() => _syntax = validated);
    } on Object catch (error, stackTrace) {
      _highlightFailed(generation, error, stackTrace);
    }
  }

  void _highlightFailed(int generation, Object error, StackTrace stackTrace) {
    if (!mounted || generation != _highlightGeneration) return;
    setState(() => _syntax = const <StyledTextRange>[]);
    widget.onHighlightError?.call(error, stackTrace);
  }

  void _retainFocusAcrossRendererChange() {
    var current = context.owner.focusManager.primaryFocus;
    var focusedWithinDiff = false;
    while (current != null) {
      if (identical(current, focusNode)) {
        focusedWithinDiff = true;
        break;
      }
      current = current.parent;
    }
    if (!focusedWithinDiff) return;
    focusNode.requestFocus();
  }

  SelectedText? get _selectedText {
    final selection = _selection;
    if (selection == null || selection.isCollapsed) return null;
    return SelectedText(
      selection: selection,
      text: _presentation.text.substring(selection.start, selection.end),
    );
  }

  void _setSelection(TextSelection? selection) {
    if (_selection == selection) return;
    setState(() => _selection = selection);
    widget.onSelectionChanged?.call(_selectedText);
  }

  void _setDragging({required bool dragging}) {
    if (_dragging == dragging) return;
    setState(() => _dragging = dragging);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = widget.rowBuilder == null
        ? _buildDefaultDocument(theme)
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final row in _presentation.rows)
                _buildCustomRow(context, theme, row),
            ],
          );
    return DocumentSelectionControls(
      documentText: _presentation.text,
      selectable: widget.selectable,
      readSelection: () => _selection,
      onSelectionChanged: _setSelection,
      onCopy: widget.onCopy,
      focusNode: focusNode,
      child: ScrollBox(
        controller: _scrollController,
        focusNode: focusNode,
        autofocus: widget.autofocus,
        showScrollbar: widget.rowBuilder != null,
        child: DocumentScrollScope(
          handlesScrolling: false,
          handlesHorizontalScrolling: widget.rowBuilder == null && !widget.wrap,
          child: content,
        ),
      ),
    );
  }

  Widget _buildDefaultDocument(ThemeData theme) => DocumentSelectionScope(
    documentText: _presentation.text,
    sourceBase: 0,
    selection: _selection,
    dragging: _dragging,
    readSelection: () => _selection,
    readDragging: () => _dragging,
    onSelectionChanged: _setSelection,
    onDraggingChanged: _setDragging,
    onCopy: widget.onCopy,
    child: DocumentView(
      text: _presentation.span(theme, _syntax),
      plainText: _presentation.text,
      wrap: widget.wrap,
      selectable: widget.selectable,
      selectionForegroundColor: widget.selectionForegroundColor,
      selectionBackgroundColor:
          widget.selectionBackgroundColor ?? theme.selectedBackground,
      onPointerDownOffset: _activateSourceOffset,
    ),
  );

  void _activateSourceOffset(int offset) {
    if (widget.onLine == null && widget.onHunk == null) return;
    _DiffPresentationRow? activated;
    for (final row in _presentation.rows) {
      if (row.start > offset) break;
      activated = row;
    }
    if (activated == null) return;
    _activateRow(activated);
  }

  void _activateRow(_DiffPresentationRow row) {
    final line = row.line;
    if (line == null) {
      widget.onHunk?.call(row.file, row.hunk);
    } else {
      widget.onLine?.call(row.file, row.hunk, line);
    }
  }

  Widget _buildCustomRow(
    BuildContext context,
    ThemeData theme,
    _DiffPresentationRow row,
  ) {
    final plainText = _presentation.text.substring(row.start, row.end);
    final defaultRow = DocumentView(
      text: _presentation.spanForRow(row, theme, _syntax),
      plainText: plainText,
      wrap: widget.wrap,
      selectable: widget.selectable,
      selectionForegroundColor: widget.selectionForegroundColor,
      selectionBackgroundColor:
          widget.selectionBackgroundColor ?? theme.selectedBackground,
    );
    final built = widget.rowBuilder!(
      context,
      row.file,
      row.hunk,
      row.line,
      defaultRow,
    );
    return DocumentSelectionScope(
      documentText: _presentation.text,
      sourceBase: row.start,
      selection: _selection,
      dragging: _dragging,
      readSelection: () => _selection,
      readDragging: () => _dragging,
      onSelectionChanged: _setSelection,
      onDraggingChanged: _setDragging,
      onCopy: widget.onCopy,
      child: PointerListener(
        onPointerDown: (event) {
          if (event.button != MouseButton.left) return;
          _activateRow(row);
        },
        child: built,
      ),
    );
  }
}

final class _DiffPresentation {
  const _DiffPresentation({
    required this.text,
    required this.rows,
    required this.hunkLines,
  });

  final String text;
  final List<_DiffPresentationRow> rows;
  final List<int> hunkLines;

  InlineSpan span(ThemeData theme, List<StyledTextRange> syntax) {
    final children = <InlineSpan>[];
    var globalCursor = 0;
    for (final row in rows) {
      if (globalCursor < row.start) {
        children.add(
          TextSpan(
            text: text.substring(globalCursor, row.start),
            style: row.styleAt(row.start, theme),
          ),
        );
      }
      children.add(spanForRow(row, theme, syntax));
      globalCursor = row.end;
    }
    return TextSpan(children: children);
  }

  TextSpan spanForRow(
    _DiffPresentationRow row,
    ThemeData theme,
    List<StyledTextRange> syntax,
  ) {
    final children = <InlineSpan>[];

    void addText(int start, int end, [TextStyle? syntaxStyle]) {
      var partStart = start;
      while (partStart < end) {
        final partEnd = math.min(end, row.nextStyleBoundary(partStart));
        final rowStyle = row.styleAt(partStart, theme);
        children.add(
          TextSpan(
            text: text.substring(partStart, partEnd),
            style:
                syntaxStyle?.copyWith(
                  backgroundColor: rowStyle.backgroundColor,
                ) ??
                rowStyle,
          ),
        );
        partStart = partEnd;
      }
    }

    var cursor = row.start;
    for (final range in syntax) {
      if (range.end <= cursor) continue;
      if (range.start >= row.end) break;
      final start = math.max(cursor, range.start);
      final end = math.min(row.end, range.end);
      if (cursor < start) addText(cursor, start);
      addText(start, end, range.style);
      cursor = end;
    }
    if (cursor < row.end) addText(cursor, row.end);
    return TextSpan(children: children);
  }
}

final class _DiffPresentationRow {
  const _DiffPresentationRow({
    required this.start,
    required this.end,
    required this.kind,
    required this.file,
    required this.hunk,
    required this.line,
    this.splitLeftEnd,
    this.splitRightStart,
    this.rightKind,
  });

  final int start;
  final int end;
  final _DiffPresentationKind kind;
  final DiffFile file;
  final DiffHunk hunk;
  final DiffLine? line;

  final int? splitLeftEnd;
  final int? splitRightStart;
  final _DiffPresentationKind? rightKind;

  TextStyle styleAt(int absoluteOffset, ThemeData theme) {
    final leftEnd = splitLeftEnd;
    final rightStart = splitRightStart;
    final right = rightKind;
    if (leftEnd != null && rightStart != null && right != null) {
      final localOffset = absoluteOffset - start;
      if (localOffset >= rightStart) return _styleForKind(right, theme);
      if (localOffset >= leftEnd) {
        return _styleForKind(_DiffPresentationKind.context, theme);
      }
    }
    return _styleForKind(kind, theme);
  }

  int nextStyleBoundary(int absoluteOffset) {
    final leftEnd = splitLeftEnd;
    final rightStart = splitRightStart;
    if (leftEnd == null || rightStart == null) return end;
    final localOffset = absoluteOffset - start;
    if (localOffset < leftEnd) return start + leftEnd;
    if (localOffset < rightStart) return start + rightStart;
    return end;
  }
}

TextStyle _styleForKind(_DiffPresentationKind kind, ThemeData theme) =>
    switch (kind) {
      _DiffPresentationKind.header => TextStyle(
        color: theme.accent,
        attributes: Attr.bold,
      ),
      _DiffPresentationKind.context => TextStyle(color: theme.text),
      _DiffPresentationKind.addition => TextStyle(
        color: theme.success,
        backgroundColor: const Color(0.05, 0.2, 0.1),
      ),
      _DiffPresentationKind.deletion => TextStyle(
        color: theme.danger,
        backgroundColor: const Color(0.22, 0.06, 0.06),
      ),
      _DiffPresentationKind.marker => TextStyle(color: theme.warning),
    };

enum _DiffPresentationKind { header, context, addition, deletion, marker }

_DiffPresentation _buildPresentation(DiffView widget) {
  final buffer = StringBuffer();
  final rows = <_DiffPresentationRow>[];
  final hunkLines = <int>[];

  void addRow(
    String text,
    _DiffPresentationKind kind,
    DiffFile file,
    DiffHunk hunk,
    DiffLine? line, {
    int? splitLeftEnd,
    int? splitRightStart,
    _DiffPresentationKind? rightKind,
  }) {
    if (rows.isNotEmpty) buffer.write('\n');
    final adjustedStart = buffer.length;
    buffer.write(text);
    rows.add(
      _DiffPresentationRow(
        start: adjustedStart,
        end: buffer.length,
        kind: kind,
        file: file,
        hunk: hunk,
        line: line,
        splitLeftEnd: splitLeftEnd,
        splitRightStart: splitRightStart,
        rightKind: rightKind,
      ),
    );
  }

  for (final file in widget.document.files) {
    for (final hunk in file.hunks) {
      hunkLines.add(rows.length);
      addRow(
        '@@ -${hunk.oldStart},${hunk.oldCount} '
                '+${hunk.newStart},${hunk.newCount} @@ ${hunk.header}'
            .trimRight(),
        _DiffPresentationKind.header,
        file,
        hunk,
        null,
      );
      if (widget.mode == DiffViewMode.unified) {
        for (final line in hunk.lines) {
          final oldNumber = line.oldLineNumber?.toString() ?? '';
          final newNumber = line.newLineNumber?.toString() ?? '';
          final gutter = widget.showLineNumbers
              ? '${oldNumber.padLeft(4)} ${newNumber.padLeft(4)} '
              : '';
          final prefix = switch (line.kind) {
            DiffLineKind.context => ' ',
            DiffLineKind.addition => '+',
            DiffLineKind.deletion => '-',
            DiffLineKind.noNewlineMarker => r'\',
          };
          addRow(
            '$gutter$prefix${line.text}',
            _presentationKind(line.kind),
            file,
            hunk,
            line,
          );
        }
      } else {
        _addSplitRows(widget, file, hunk, addRow);
      }
    }
  }
  return _DiffPresentation(
    text: buffer.toString(),
    rows: List<_DiffPresentationRow>.unmodifiable(rows),
    hunkLines: List<int>.unmodifiable(hunkLines),
  );
}

void _addSplitRows(
  DiffView widget,
  DiffFile file,
  DiffHunk hunk,
  void Function(
    String,
    _DiffPresentationKind,
    DiffFile,
    DiffHunk,
    DiffLine?, {
    int? splitLeftEnd,
    int? splitRightStart,
    _DiffPresentationKind? rightKind,
  })
  addRow,
) {
  var index = 0;
  while (index < hunk.lines.length) {
    final line = hunk.lines[index];
    if (line.kind == DiffLineKind.context ||
        line.kind == DiffLineKind.noNewlineMarker) {
      final number = widget.showLineNumbers
          ? '${line.oldLineNumber ?? ''}'.padLeft(4)
          : '';
      final left = '$number ${line.text}'.padRight(widget.splitColumnWidth);
      final rightNumber = widget.showLineNumbers
          ? '${line.newLineNumber ?? ''}'.padLeft(4)
          : '';
      addRow(
        '$left │ $rightNumber ${line.text}',
        _presentationKind(line.kind),
        file,
        hunk,
        line,
      );
      index++;
      continue;
    }
    final deletions = <DiffLine>[];
    final additions = <DiffLine>[];
    while (index < hunk.lines.length &&
        hunk.lines[index].kind == DiffLineKind.deletion) {
      deletions.add(hunk.lines[index++]);
    }
    while (index < hunk.lines.length &&
        hunk.lines[index].kind == DiffLineKind.addition) {
      additions.add(hunk.lines[index++]);
    }
    final count = math.max(deletions.length, additions.length);
    for (var pair = 0; pair < count; pair++) {
      final deletion = pair < deletions.length ? deletions[pair] : null;
      final addition = pair < additions.length ? additions[pair] : null;
      final oldNumber = widget.showLineNumbers
          ? '${deletion?.oldLineNumber ?? ''}'.padLeft(4)
          : '';
      final newNumber = widget.showLineNumbers
          ? '${addition?.newLineNumber ?? ''}'.padLeft(4)
          : '';
      final left = '$oldNumber-${deletion?.text ?? ''}'.padRight(
        widget.splitColumnWidth,
      );
      addRow(
        '$left │ $newNumber+${addition?.text ?? ''}',
        deletion == null
            ? _DiffPresentationKind.context
            : _DiffPresentationKind.deletion,
        file,
        hunk,
        addition ?? deletion,
        splitLeftEnd: left.length,
        splitRightStart: left.length + 3,
        rightKind: addition == null
            ? _DiffPresentationKind.context
            : _DiffPresentationKind.addition,
      );
    }
  }
}

_DiffPresentationKind _presentationKind(DiffLineKind kind) => switch (kind) {
  DiffLineKind.context => _DiffPresentationKind.context,
  DiffLineKind.addition => _DiffPresentationKind.addition,
  DiffLineKind.deletion => _DiffPresentationKind.deletion,
  DiffLineKind.noNewlineMarker => _DiffPresentationKind.marker,
};
