import 'dart:async';

import 'package:meta/meta.dart';

import '../core/color.dart';
import '../foundation/selected_text.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import 'document_view.dart';
import 'text_span.dart';
import 'text_style.dart';
import 'theme.dart';

/// One non-overlapping UTF-16 style range returned by a [CodeHighlighter].
@immutable
final class StyledTextRange {
  /// Creates a style range over `[start, end)`.
  const StyledTextRange({
    required this.start,
    required this.end,
    required this.style,
  });

  /// Inclusive UTF-16 start offset.
  final int start;

  /// Exclusive UTF-16 end offset.
  final int end;

  /// Style applied within this range.
  final TextStyle style;
}

/// Converts source code to non-overlapping UTF-16 style ranges.
abstract interface class CodeHighlighter {
  /// Highlights [source], optionally using a language identifier.
  FutureOr<List<StyledTextRange>> highlight(String source, {String? language});
}

/// Highlighter that intentionally leaves source text unstyled.
final class PlainTextCodeHighlighter implements CodeHighlighter {
  /// Creates the dependency-free fallback highlighter.
  const PlainTextCodeHighlighter();

  @override
  List<StyledTextRange> highlight(String source, {String? language}) =>
      const <StyledTextRange>[];
}

/// Called when a synchronous or asynchronous highlighting attempt fails.
typedef HighlightErrorCallback =
    void Function(Object error, StackTrace stackTrace);

/// Scrollable, selectable source-code viewer with async-safe highlighting.
class CodeView extends StatefulWidget {
  /// Configures source rendering, highlighting, gutter, and selection.
  const CodeView({
    required this.code,
    super.key,
    this.language,
    this.highlighter = const PlainTextCodeHighlighter(),
    this.style,
    this.wrap = false,
    this.selectable = true,
    this.showLineNumbers = true,
    this.lineNumberStyle,
    this.selectionForegroundColor,
    this.selectionBackgroundColor,
    this.focusNode,
    this.autofocus = false,
    this.onSelectionChanged,
    this.onCopy,
    this.onHighlightError,
    this.onVisibleLineChanged,
  });

  /// Source code rendered verbatim.
  final String code;

  /// Optional language identifier passed to [highlighter].
  final String? language;

  /// Range producer; concrete grammar engines live outside Noir core.
  final CodeHighlighter highlighter;

  /// Base source style.
  final TextStyle? style;

  /// Whether long source lines soft-wrap.
  final bool wrap;

  /// Whether text can be selected and explicitly copied.
  final bool selectable;

  /// Whether source line numbers are shown.
  final bool showLineNumbers;

  /// Source-line gutter style.
  final TextStyle? lineNumberStyle;

  /// Selected text foreground override.
  final Color? selectionForegroundColor;

  /// Selected text background override.
  final Color? selectionBackgroundColor;

  /// Caller-owned focus node, or null for widget ownership.
  final FocusNode? focusNode;

  /// Whether the view requests focus after mounting.
  final bool autofocus;

  /// Receives null when no non-empty selection remains.
  final void Function(SelectedText? selection)? onSelectionChanged;

  /// Receives each explicit Ctrl+C result.
  final SelectionCopyCallback? onCopy;

  /// Receives validation, synchronous, and asynchronous highlight failures.
  final HighlightErrorCallback? onHighlightError;

  /// Receives the first visible visual line after vertical scrolling.
  final void Function(int line)? onVisibleLineChanged;

  @override
  State<CodeView> createState() => _CodeViewState();
}

final class _CodeViewState extends State<CodeView> {
  List<StyledTextRange> _ranges = const <StyledTextRange>[];
  int _highlightGeneration = 0;

  @override
  void initState() {
    super.initState();
    _refreshHighlights();
  }

  @override
  void didUpdateWidget(CodeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.code != oldWidget.code ||
        widget.language != oldWidget.language ||
        !identical(widget.highlighter, oldWidget.highlighter)) {
      _refreshHighlights();
    }
  }

  void _refreshHighlights() {
    final generation = ++_highlightGeneration;
    _ranges = const <StyledTextRange>[];
    FutureOr<List<StyledTextRange>> result;
    try {
      result = widget.highlighter.highlight(
        widget.code,
        language: widget.language,
      );
    } on Object catch (error, stackTrace) {
      _handleHighlightFailure(generation, error, stackTrace);
      return;
    }
    if (result is Future<List<StyledTextRange>>) {
      result.then(
        (ranges) => _acceptHighlights(generation, ranges),
        onError: (Object error, StackTrace stackTrace) {
          _handleHighlightFailure(generation, error, stackTrace);
        },
      );
    } else {
      _acceptHighlights(generation, result);
    }
  }

  void _acceptHighlights(int generation, List<StyledTextRange> ranges) {
    if (!mounted || generation != _highlightGeneration) return;
    try {
      final validated = validateStyledTextRanges(widget.code, ranges);
      setState(() => _ranges = validated);
    } on Object catch (error, stackTrace) {
      _handleHighlightFailure(generation, error, stackTrace);
    }
  }

  void _handleHighlightFailure(
    int generation,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!mounted || generation != _highlightGeneration) return;
    setState(() => _ranges = const <StyledTextRange>[]);
    widget.onHighlightError?.call(error, stackTrace);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = widget.style ?? TextStyle(color: theme.text);
    return DocumentView(
      text: _spanFor(widget.code, baseStyle, _ranges),
      plainText: widget.code,
      wrap: widget.wrap,
      selectable: widget.selectable,
      showLineNumbers: widget.showLineNumbers,
      lineNumberStyle:
          widget.lineNumberStyle ?? TextStyle(color: theme.textMuted),
      selectionForegroundColor:
          widget.selectionForegroundColor ?? theme.selectedForeground,
      selectionBackgroundColor:
          widget.selectionBackgroundColor ?? theme.selectedBackground,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onSelectionChanged: widget.onSelectionChanged,
      onCopy: widget.onCopy,
      onVisibleLineChanged: widget.onVisibleLineChanged,
    );
  }
}

/// Validates and snapshots highlighter output for document components.
@internal
List<StyledTextRange> validateStyledTextRanges(
  String source,
  List<StyledTextRange> ranges,
) {
  final snapshot = List<StyledTextRange>.of(ranges)
    ..sort((a, b) => a.start.compareTo(b.start));
  var previousEnd = 0;
  for (final range in snapshot) {
    if (range.start < 0 ||
        range.end <= range.start ||
        range.end > source.length ||
        range.start < previousEnd) {
      throw FormatException(
        'Invalid or overlapping highlight range '
        '[${range.start}, ${range.end}) for ${source.length} UTF-16 units.',
      );
    }
    previousEnd = range.end;
  }
  return List<StyledTextRange>.unmodifiable(snapshot);
}

InlineSpan _spanFor(
  String source,
  TextStyle baseStyle,
  List<StyledTextRange> ranges,
) {
  if (ranges.isEmpty) return TextSpan(text: source, style: baseStyle);
  final children = <InlineSpan>[];
  var cursor = 0;
  for (final range in ranges) {
    if (cursor < range.start) {
      children.add(
        TextSpan(text: source.substring(cursor, range.start), style: baseStyle),
      );
    }
    children.add(
      TextSpan(
        text: source.substring(range.start, range.end),
        style: range.style,
      ),
    );
    cursor = range.end;
  }
  if (cursor < source.length) {
    children.add(TextSpan(text: source.substring(cursor), style: baseStyle));
  }
  return TextSpan(style: baseStyle, children: children);
}
