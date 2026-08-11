import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

import '../core/color.dart';
import '../core/grapheme_metrics.dart';
import '../core/terminal_style.dart';
import '../render/geometry.dart';
import '../widgets/text_layout.dart';
import '../widgets/text_span.dart';
import '../widgets/text_style.dart';
import 'box.dart';
import 'object.dart';
import 'text_highlight.dart';

/// RenderObject that lays out inline spans and records text paint commands.
class RenderParagraph extends RenderBox {
  /// Creates a render paragraph.
  RenderParagraph({
    required InlineSpan text,
    TextStyle style = const TextStyle(),
    TextAlign alignment = TextAlign.left,
    int? maxLines,
    bool softWrap = true,
    TextOverflow overflow = TextOverflow.clip,
    TextHighlight? selection,
  }) : _text = text,
       _style = style,
       _alignment = alignment,
       _maxLines = _validatedMaxLines(maxLines),
       _softWrap = softWrap,
       _overflow = overflow,
       _selection = selection;

  InlineSpan _text;
  TextStyle _style;
  TextAlign _alignment;
  int? _maxLines;
  bool _softWrap;
  TextOverflow _overflow;
  TextHighlight? _selection;
  TextLayout? _layout;
  BoxConstraints? _lastLayoutConstraints;

  /// The inline span tree to render.
  InlineSpan get text => _text;
  set text(InlineSpan value) {
    if (identical(_text, value)) {
      return;
    }
    _text = value;
    _markTextLayoutDirty();
  }

  /// Root style used by unstyled spans.
  TextStyle get style => _style;
  set style(TextStyle value) {
    if (identical(_style, value)) {
      return;
    }
    _style = value;
    _markTextLayoutDirty();
  }

  /// How the text should be aligned within its bounds.
  TextAlign get alignment => _alignment;
  set alignment(TextAlign value) {
    if (_alignment == value) {
      return;
    }
    _alignment = value;
    markNeedsPaint();
  }

  /// Maximum laid-out line count, or `null` for no line-count limit.
  ///
  /// Must be null (unlimited) or a positive integer. Zero and negatives are
  /// programmer errors and throw [ArgumentError] before storage.
  int? get maxLines => _maxLines;

  /// Updates the maxLines value.
  set maxLines(int? value) {
    final validated = _validatedMaxLines(value);
    if (_maxLines == validated) {
      return;
    }
    _maxLines = validated;
    markNeedsLayout();
  }

  /// Whether text layout may wrap at the available width.
  bool get softWrap => _softWrap;

  /// Updates the softWrap value.
  set softWrap(bool value) {
    if (_softWrap == value) {
      return;
    }
    _softWrap = value;
    _markTextLayoutDirty();
  }

  /// Paint policy applied when laid-out text exceeds its visible bounds.
  TextOverflow get overflow => _overflow;

  /// Updates the overflow value.
  set overflow(TextOverflow value) {
    if (_overflow == value) {
      return;
    }
    _overflow = value;
    markNeedsPaint();
  }

  /// Optional source-string span highlight recorded with text paint.
  TextHighlight? get selection => _selection;

  /// Updates the selection value.
  set selection(TextHighlight? value) {
    if (_selection == value) {
      return;
    }
    _selection = value;
    markNeedsPaint();
  }

  /// Last computed text layout.
  @visibleForTesting
  TextLayout? get debugTextLayout => _layout;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final layout = _ensureTextLayout(constraints);
    final intrinsicWidth = layout.maxLineWidth;
    final intrinsicHeight = math.min(layout.lineCount, _maxLinesLimit(layout));
    size = Size(
      constraints.constrainWidth(intrinsicWidth),
      constraints.constrainHeight(intrinsicHeight),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.width <= 0 || size.height <= 0) return;

    final layout = _layout;
    if (layout == null) return;

    final absoluteX = offset.dx + x;
    final absoluteY = offset.dy + y;
    final availableWidth = size.width;
    final textWidth = layout.maxLineWidth;
    final maxLinesLimit = _maxLinesLimit(layout);
    final linesToRender = math.min(size.height, maxLinesLimit);
    if (linesToRender <= 0) {
      return;
    }

    var textX = absoluteX;
    switch (_alignment) {
      case TextAlign.left:
        break;
      case TextAlign.center:
        textX =
            absoluteX +
            ((availableWidth - textWidth).clamp(0, availableWidth) ~/ 2);
      case TextAlign.right:
        textX =
            absoluteX + (availableWidth - textWidth).clamp(0, availableWidth);
    }

    final needsWidthClip = textWidth > availableWidth;
    final needsHeightClip = layout.lineCount > linesToRender;
    final hasClip = needsWidthClip || needsHeightClip;
    context.canvas.drawTextLayout(
      layout,
      Offset(textX, absoluteY),
      sourceRect: hasClip
          ? Rect.fromLTWH(0, 0, availableWidth, linesToRender)
          : null,
      selection: _selection,
    );

    if (_overflow == TextOverflow.ellipsis &&
        (needsWidthClip || needsHeightClip)) {
      final ellipsis = _ellipsisForWidth(availableWidth);
      if (ellipsis.isNotEmpty) {
        final ellipsisLineY = absoluteY + linesToRender - 1;
        final ellipsisX =
            absoluteX + availableWidth - terminalStringWidth(ellipsis);
        _paintEllipsis(context, ellipsisX, ellipsisLineY, ellipsis);
      }
    }
  }

  @override
  void detach() {
    _layout = null;
    _lastLayoutConstraints = null;
    super.detach();
  }

  @override
  String toString() =>
      'RenderParagraph(text: "${_plainText()}", style: $_style, '
      'alignment: $_alignment, size: $size)';

  void _markTextLayoutDirty() {
    _layout = null;
    _lastLayoutConstraints = null;
    markNeedsLayout();
  }

  TextLayout _ensureTextLayout(BoxConstraints constraints) {
    final layoutConstraints = _layoutConstraints(constraints);
    final current = _layout;
    if (current != null && _lastLayoutConstraints == layoutConstraints) {
      return current;
    }
    final next = const TextLayoutEngine().layout(
      _text,
      layoutConstraints,
      style: _style,
    );
    _layout = next;
    _lastLayoutConstraints = layoutConstraints;
    return next;
  }

  BoxConstraints _layoutConstraints(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: _softWrap ? constraints.maxWidth : null);

  int _maxLinesLimit(TextLayout layout) => _maxLines ?? layout.lineCount;

  String _plainText() {
    final buffer = StringBuffer();
    _text.computePlainText(buffer);
    return buffer.toString();
  }

  String _ellipsisForWidth(int width) {
    if (width <= 0) {
      return '';
    }
    if (width >= 3) {
      return '...';
    }
    return List.filled(width, '.').join();
  }

  void _paintEllipsis(
    PaintingContext context,
    int startX,
    int y,
    String ellipsis,
  ) {
    final fg = _style.color;
    final bg = _style.backgroundColor ?? Color.transparent;
    var cell = 0;
    for (final cluster in ellipsis.characters) {
      context.canvas.setCell(
        Offset(startX + cell, y),
        cluster,
        fg,
        bg,
        _style.computedAttributes,
      );
      cell += terminalCellWidth(cluster);
    }
  }
}

/// Validates the public positive-or-null [maxLines] contract for all modes.
int? _validatedMaxLines(int? value) {
  if (value != null && value <= 0) {
    throw ArgumentError.value(
      value,
      'maxLines',
      'must be null or greater than zero',
    );
  }
  return value;
}
