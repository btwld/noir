import 'package:meta/meta.dart';

import '../core/terminal_style.dart';
import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../rendering/object.dart';
import '../rendering/paragraph.dart';
import '../rendering/text_highlight.dart';
import 'text_layout.dart';
import 'text_span.dart';
import 'text_style.dart';

/// A run of text with a single style, rendered through the terminal text
/// pipeline.
///
/// Supported styling is the terminal-representable subset of [TextStyle]:
/// foreground/background `Color`, [FontWeight] normal/bold/dim, [FontStyle]
/// italic, underline and line-through [TextDecoration], and the
/// terminal-specific blink/reverse [TextEffect]s. [TextAlign] supports left,
/// center, and right.
///
/// Flutter compatibility note: fontSize, fontFamily, letterSpacing,
/// wordSpacing, height, `FontWeight.w100`-`w900`, `TextAlign.justify`, and
/// `TextDecoration.overline` are removed — the fixed character grid and
/// terminal-controlled font cannot express them.
class Text extends RenderObjectWidget {
  /// Creates a Text widget.
  ///
  /// The [data] argument is required and specifies the text content.
  /// The [style] parameter controls the appearance of the text.
  /// If [style] is null, a default style with white text is used.
  const Text(
    this.data, {
    this.style,
    this.textAlign = TextAlign.left,
    this.maxLines,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.selection,
    super.key,
  }) : assert(
         maxLines == null || maxLines > 0,
         'maxLines must be null or greater than zero',
       ),
       textSpan = null;

  /// Creates text from an inline span tree.
  const Text.rich(
    TextSpan this.textSpan, {
    this.style,
    this.textAlign = TextAlign.left,
    this.maxLines,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.selection,
    super.key,
  }) : assert(
         maxLines == null || maxLines > 0,
         'maxLines must be null or greater than zero',
       ),
       data = null;

  /// The text to display.
  final String? data;

  /// Rich text span to display.
  final TextSpan? textSpan;

  /// The style to use for this text.
  ///
  /// If null, defaults to the default text style with white foreground.
  final TextStyle? style;

  /// How the text should be aligned horizontally within its bounds.
  ///
  /// Defaults to [TextAlign.left].
  final TextAlign textAlign;

  /// The maximum number of lines to display.
  ///
  /// Must be null (unlimited) or greater than zero.
  final int? maxLines;

  /// Whether to break lines softly at word boundaries.
  final bool softWrap;

  /// How to handle visual overflow.
  final TextOverflow overflow;

  /// Optional text selection highlight configuration.
  final TextHighlight? selection;

  @override
  @internal
  RenderObject createRenderObject(BuildContext context) => RenderParagraph(
    text: _span(),
    style: style ?? const TextStyle(),
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
    // mutate text/style/alignment before the render boundary rejects it.
    renderObject
      ..maxLines = maxLines
      ..text = _span()
      ..style = style ?? const TextStyle()
      ..alignment = textAlign
      ..softWrap = softWrap
      ..overflow = overflow
      ..selection = selection;
  }

  TextSpan _span() => textSpan ?? TextSpan(text: data, style: style);
}
