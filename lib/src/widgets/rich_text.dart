import 'package:meta/meta.dart';

import '../core/terminal_style.dart';
import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../rendering/object.dart';
import '../rendering/paragraph.dart';
import '../rendering/text_highlight.dart';
import 'text_layout.dart';
import 'text_span.dart';

/// Displays an [InlineSpan] tree.
class RichText extends RenderObjectWidget {
  /// Creates rich text.
  const RichText({
    required this.text,
    this.textAlign = TextAlign.left,
    this.maxLines,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.selection,
    super.key,
  }) : assert(
         maxLines == null || maxLines > 0,
         'maxLines must be null or greater than zero',
       );

  /// Span tree to display.
  final InlineSpan text;

  /// Horizontal alignment.
  final TextAlign textAlign;

  /// Maximum visible lines.
  ///
  /// Must be null (unlimited) or greater than zero.
  final int? maxLines;

  /// Whether to soft-wrap.
  final bool softWrap;

  /// Overflow mode.
  final TextOverflow overflow;

  /// Optional selection highlight.
  final TextHighlight? selection;

  @override
  @internal
  RenderObject createRenderObject(BuildContext context) => RenderParagraph(
    text: text,
    alignment: textAlign,
    maxLines: maxLines,
    softWrap: softWrap,
    overflow: overflow,
    selection: selection,
  );

  @override
  @internal
  void updateRenderObject(BuildContext context, RenderParagraph renderObject) {
    // Validate maxLines first so an assertion-disabled invalid update cannot
    // mutate text/alignment before the render boundary rejects it.
    renderObject
      ..maxLines = maxLines
      ..text = text
      ..alignment = textAlign
      ..softWrap = softWrap
      ..overflow = overflow
      ..selection = selection;
  }
}
