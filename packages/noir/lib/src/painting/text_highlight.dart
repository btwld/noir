import '../core/color.dart';

/// Configuration for highlighting a range of text within a [RenderParagraph].
class TextHighlight {
  /// Defines an ordered half-open UTF-16 source span with optional color overrides.
  const TextHighlight({
    required this.start,
    required this.end,
    this.foregroundColor,
    this.backgroundColor,
  }) : assert(start >= 0 && end >= start, 'Invalid selection range');

  /// Inclusive UTF-16 code-unit offset in the source string, not a cell offset.
  final int start;

  /// Exclusive UTF-16 code-unit offset in the source string, not a cell offset.
  final int end;

  /// Optional foreground override for text intersecting the source span.
  final Color? foregroundColor;

  /// Optional background override for text intersecting the source span.
  final Color? backgroundColor;
}
