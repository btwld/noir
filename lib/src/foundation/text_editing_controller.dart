import 'text_editing_value.dart';
import 'text_index_map.dart';
import 'text_range.dart';
import 'text_selection.dart';
import 'value_notifier.dart';

/// Controls editable text through an immutable [TextEditingValue].
class TextEditingController extends ValueNotifier<TextEditingValue> {
  /// Creates a controller with optional initial [text].
  TextEditingController({String text = ''})
    : super(TextEditingValue(text: text));

  /// Text content of the field. Setting this value also clears the current selection.
  String get text => value.text;

  /// Replaces current text and clears the selection.
  set text(String text) {
    value = TextEditingValue(text: text);
  }

  /// Current selection.
  TextSelection get selection => value.selection;

  /// Updates selection without changing text.
  set selection(TextSelection selection) {
    _validateSelection(selection, text);
    value = value.copyWith(selection: selection);
  }

  /// Whether both selection offsets lie within the current [text]
  /// (`0 <= offset <= text.length`). False for cleared (-1) selections.
  bool get selectionWithinText {
    final end = text.length;
    return selection.baseOffset >= 0 &&
        selection.extentOffset >= 0 &&
        selection.baseOffset <= end &&
        selection.extentOffset <= end;
  }

  /// Lines of the current text, split on newline characters.
  List<String> get lines => text.split('\n');

  /// Zero-based line index of the cursor when the selection is collapsed.
  int get line => _positionForOffset(text, selection.extentOffset).line;

  /// Zero-based grapheme-cluster column of the cursor on its current line.
  int get col => _positionForOffset(text, selection.extentOffset).column;

  /// Whether the text is empty.
  bool get isEmpty => text.isEmpty;

  /// Clears the current value.
  void clear() {
    value = const TextEditingValue(
      selection: TextSelection.collapsed(offset: 0),
    );
  }

  /// Sets the collapsed selection by line and grapheme-column.
  void setCursor(int line, int col) {
    final offset = _offsetForPosition(text, line, col);
    selection = TextSelection.collapsed(offset: offset);
  }

  /// Inserts [replacement] at the current selection.
  bool insert(String replacement, {bool allowNewline = true}) {
    if (replacement.isEmpty) return false;
    if (!allowNewline && replacement.contains('\n')) return false;
    _replaceSelection(replacement);
    return true;
  }

  /// Inserts a newline at the current selection.
  bool newline() => insert('\n');

  /// Deletes the previous grapheme cluster or selected range.
  bool deleteBack() {
    final range = _normalizedSelection;
    if (!range.isCollapsed) {
      _replaceRange(range.start, range.end, '');
      return true;
    }
    if (range.start <= 0) return false;
    final start = _previousGraphemeBoundary(text, range.start);
    _replaceRange(start, range.start, '');
    return true;
  }

  /// Deletes the next grapheme cluster or selected range.
  bool deleteForward() {
    final range = _normalizedSelection;
    if (!range.isCollapsed) {
      _replaceRange(range.start, range.end, '');
      return true;
    }
    if (range.start >= _endOffset(text)) return false;
    final end = _nextGraphemeBoundary(text, range.start);
    _replaceRange(range.start, end, '');
    return true;
  }

  /// Moves the collapsed cursor left by one grapheme cluster.
  void moveCursorLeft() {
    final offset = _previousGraphemeBoundary(text, selection.extentOffset);
    selection = TextSelection.collapsed(offset: offset);
  }

  /// Moves the collapsed cursor right by one grapheme cluster.
  void moveCursorRight() {
    final offset = _nextGraphemeBoundary(text, selection.extentOffset);
    selection = TextSelection.collapsed(offset: offset);
  }

  /// Moves the collapsed cursor up one line, preserving grapheme column.
  void moveCursorUp() {
    final position = _positionForOffset(text, selection.extentOffset);
    setCursor(position.line - 1, position.column);
  }

  /// Moves the collapsed cursor down one line, preserving grapheme column.
  void moveCursorDown() {
    final position = _positionForOffset(text, selection.extentOffset);
    setCursor(position.line + 1, position.column);
  }

  /// Moves the collapsed cursor to the start of its current line.
  void moveLineStart() {
    final position = _positionForOffset(text, selection.extentOffset);
    setCursor(position.line, 0);
  }

  /// Moves the collapsed cursor to the end of its current line.
  void moveLineEnd() {
    final position = _positionForOffset(text, selection.extentOffset);
    final lineText = lines[position.line];
    setCursor(position.line, TextIndexMap(lineText).graphemeCount);
  }

  /// Moves the collapsed cursor to the start of the document.
  void moveDocumentStart() {
    selection = const TextSelection.collapsed(offset: 0);
  }

  /// Moves the collapsed cursor to the end of the document.
  void moveDocumentEnd() {
    selection = TextSelection.collapsed(offset: _endOffset(text));
  }

  TextRange get _normalizedSelection =>
      TextRange(start: selection.start, end: selection.end);

  void _replaceSelection(String replacement) {
    final range = _normalizedSelection;
    _replaceRange(range.start, range.end, replacement);
  }

  void _replaceRange(int start, int end, String replacement) {
    final newText = text.replaceRange(start, end, replacement);
    final offset = start + _endOffset(replacement);
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

({int line, int column}) _positionForOffset(String text, int offset) {
  final clamped = offset.clamp(0, _endOffset(text));
  final lines = text.split('\n');
  var line = 0;
  var lineStart = 0;
  for (final lineText in lines) {
    final lineEnd = lineStart + _endOffset(lineText);
    if (clamped <= lineEnd) {
      return (
        line: line,
        column: TextIndexMap(lineText).utf16ToGrapheme(clamped - lineStart),
      );
    }
    lineStart = lineEnd + 1;
    line++;
  }
  throw StateError('unreachable: clamped offset always lands on a line');
}

int _offsetForPosition(String text, int line, int column) {
  final lines = text.split('\n');
  final clampedLine = line.clamp(0, lines.length - 1);
  var offset = 0;
  for (var i = 0; i < clampedLine; i++) {
    offset += _endOffset(lines[i]) + 1;
  }
  final lineText = lines[clampedLine];
  final map = TextIndexMap(lineText);
  final clampedColumn = column.clamp(0, map.graphemeCount);
  return offset + map.graphemeToUtf16(clampedColumn);
}

int _previousGraphemeBoundary(String text, int offset) {
  final map = TextIndexMap(text);
  final clamped = offset.clamp(0, map.graphemeToUtf16(map.graphemeCount));
  if (clamped <= 0) return 0;
  final index = map.utf16ToGrapheme(clamped);
  if (map.graphemeToUtf16(index) == clamped) {
    return map.graphemeToUtf16(index - 1);
  }
  return map.graphemeToUtf16(index);
}

int _nextGraphemeBoundary(String text, int offset) {
  final map = TextIndexMap(text);
  final end = map.graphemeToUtf16(map.graphemeCount);
  final clamped = offset.clamp(0, end);
  if (clamped >= end) return end;
  final index = map.utf16ToGrapheme(clamped);
  return map.graphemeToUtf16(index + 1);
}

void _validateSelection(TextSelection selection, String text) {
  final end = _endOffset(text);
  final base = selection.baseOffset;
  final extent = selection.extentOffset;
  final clearsSelection = base == -1 && extent == -1;
  final inRange = base >= 0 && extent >= 0 && base <= end && extent <= end;
  if (clearsSelection || inRange) {
    return;
  }
  final invalidOffset = base < -1 || base > end ? base : extent;
  throw RangeError.range(
    invalidOffset,
    0,
    end,
    'selection',
    'selection offsets must be in the current text',
  );
}

int _endOffset(String text) {
  final map = TextIndexMap(text);
  return map.graphemeToUtf16(map.graphemeCount);
}
