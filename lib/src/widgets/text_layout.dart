import 'dart:math' as math;

import 'package:characters/characters.dart';

import '../core/grapheme_metrics.dart';
import '../foundation/text_index_map.dart';
import '../render/geometry.dart';
import 'text_span.dart';
import 'text_style.dart';

/// Overflow behaviour for terminal text rendering.
enum TextOverflow {
  /// Clip overflowing text.
  clip,

  /// Paint an ellipsis when text overflows.
  ellipsis,
}

/// A laid-out text snapshot.
final class TextLayout {
  /// Creates a text layout.
  const TextLayout({
    required this.text,
    required this.style,
    required this.indexMap,
    required this.lines,
    required this.sourceGraphemeToBufferOffset,
    required this.size,
  });

  /// Plain source text before soft wrapping.
  final String text;

  /// Effective root style.
  final TextStyle style;

  /// Unicode/cell index map for source [text].
  final TextIndexMap indexMap;

  /// Laid-out lines in paint order.
  final List<TextLayoutLine> lines;

  /// Source grapheme-index to buffer rune offset mapping.
  final List<int> sourceGraphemeToBufferOffset;

  /// Terminal-cell size.
  final Size size;

  /// Text written to the native text buffer, including layout newlines.
  String get bufferText => lines.map((line) => line.text).join('\n');

  /// Maximum laid-out line width in terminal cells.
  int get maxLineWidth =>
      lines.isEmpty ? 0 : lines.map((line) => line.width).reduce(math.max);

  /// Number of laid-out lines.
  int get lineCount => math.max(1, lines.length);

  /// Convert a source UTF-16 offset to a laid-out buffer rune offset.
  int bufferOffsetForSourceUtf16(int utf16Offset) {
    final grapheme = indexMap.utf16ToGrapheme(utf16Offset);
    return sourceGraphemeToBufferOffset[grapheme.clamp(
      0,
      sourceGraphemeToBufferOffset.length - 1,
    )];
  }
}

/// One laid-out terminal text line.
final class TextLayoutLine {
  /// Creates a laid-out text line.
  const TextLayoutLine({required this.runs, required this.width});

  /// Styled runs on this line.
  final List<TextLayoutRun> runs;

  /// Width in terminal cells.
  final int width;

  /// Plain text for this line.
  String get text => runs.map((run) => run.text).join();
}

/// One styled run within a laid-out text line.
final class TextLayoutRun {
  /// Creates a text layout run.
  const TextLayoutRun({
    required this.text,
    required this.style,
    required this.sourceStart,
    required this.sourceEnd,
  });

  /// Run text.
  final String text;

  /// Effective style.
  final TextStyle style;

  /// Source UTF-16 start offset.
  final int sourceStart;

  /// Source UTF-16 end offset.
  final int sourceEnd;
}

/// Lays out inline spans against terminal box constraints.
final class TextLayoutEngine {
  /// Creates a layout engine.
  const TextLayoutEngine();

  /// Lays out [root] using [constraints].
  TextLayout layout(
    InlineSpan root,
    BoxConstraints constraints, {
    TextStyle style = const TextStyle(),
  }) {
    final runs = <_SourceRun>[];
    final textBuffer = StringBuffer();
    _flatten(root, style, textBuffer, runs);
    final text = textBuffer.toString();
    final effectiveStyle = root is TextSpan ? root.style ?? style : style;
    final indexMap = TextIndexMap(text);
    final laidOut = _layoutRuns(runs, indexMap, constraints.maxWidth);
    return TextLayout(
      text: text,
      style: effectiveStyle,
      indexMap: indexMap,
      lines: laidOut.lines,
      sourceGraphemeToBufferOffset: laidOut.sourceGraphemeToBufferOffset,
      size: Size(
        constraints.constrainWidth(laidOut.maxLineWidth),
        constraints.constrainHeight(math.max(1, laidOut.lines.length)),
      ),
    );
  }

  void _flatten(
    InlineSpan span,
    TextStyle inheritedStyle,
    StringBuffer textBuffer,
    List<_SourceRun> runs,
  ) {
    if (span is TextSpan) {
      final style = span.style ?? inheritedStyle;
      final value = span.text;
      if (value != null && value.isNotEmpty) {
        final start = textBuffer.length;
        textBuffer.write(value);
        runs.add(_SourceRun(value, style, start, textBuffer.length));
      }
      for (final child in span.children) {
        _flatten(child, style, textBuffer, runs);
      }
      return;
    }

    final buffer = StringBuffer();
    span.computePlainText(buffer);
    final value = buffer.toString();
    if (value.isEmpty) {
      return;
    }
    final start = textBuffer.length;
    textBuffer.write(value);
    runs.add(_SourceRun(value, inheritedStyle, start, textBuffer.length));
  }

  _LayoutResult _layoutRuns(
    List<_SourceRun> sourceRuns,
    TextIndexMap indexMap,
    int? maxWidth,
  ) {
    final lines = <_LineBuild>[];
    final current = <_ClusterToken>[];
    var currentWidth = 0;

    int widthOf(List<_ClusterToken> tokens) =>
        tokens.fold(0, (sum, token) => sum + token.width);

    void flushLine({int? explicitNewlineSourceStart}) {
      lines.add(
        _LineBuild(
          tokens: List<_ClusterToken>.unmodifiable(current),
          width: currentWidth,
          explicitNewlineSourceStart: explicitNewlineSourceStart,
        ),
      );
      current.clear();
      currentWidth = 0;
    }

    void wrapBefore(_ClusterToken token) {
      if (maxWidth == null ||
          maxWidth <= 0 ||
          currentWidth == 0 ||
          currentWidth + token.width <= maxWidth) {
        return;
      }

      final breakIndex = current.lastIndexWhere((item) => item.isWhitespace);
      if (breakIndex >= 0 && breakIndex < current.length - 1) {
        final nextLine = current.sublist(breakIndex + 1);
        current.removeRange(breakIndex + 1, current.length);
        currentWidth = widthOf(current);
        flushLine();
        current.addAll(nextLine);
        currentWidth = widthOf(current);
        if (currentWidth + token.width <= maxWidth) {
          return;
        }
      }

      flushLine();
    }

    for (final run in sourceRuns) {
      var sourceOffset = run.sourceStart;
      for (final cluster in run.text.characters) {
        if (cluster == '\n') {
          flushLine(explicitNewlineSourceStart: sourceOffset);
          sourceOffset += cluster.length;
          continue;
        }

        final token = _ClusterToken(
          text: cluster,
          style: run.style,
          sourceStart: sourceOffset,
          sourceEnd: sourceOffset + cluster.length,
          width: terminalCellWidth(cluster),
        );
        wrapBefore(token);
        current.add(token);
        currentWidth += token.width;
        sourceOffset += cluster.length;
      }
    }

    if (current.isNotEmpty || lines.isEmpty) {
      flushLine();
    }

    final sourceToBuffer = List<int>.filled(indexMap.graphemeCount + 1, 0);
    var bufferOffset = 0;
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      for (final token in line.tokens) {
        sourceToBuffer[indexMap.utf16ToGrapheme(token.sourceStart)] =
            bufferOffset;
        bufferOffset += token.text.runes.length;
      }
      if (lineIndex < lines.length - 1) {
        bufferOffset++;
        final sourceStart = line.explicitNewlineSourceStart;
        if (sourceStart != null) {
          sourceToBuffer[indexMap.utf16ToGrapheme(sourceStart)] = bufferOffset;
        }
      }
    }
    sourceToBuffer[indexMap.graphemeCount] = bufferOffset;

    final textLines = lines
        .map(
          (line) => TextLayoutLine(
            runs: List<TextLayoutRun>.unmodifiable(_runsFor(line.tokens)),
            width: line.width,
          ),
        )
        .toList(growable: false);

    return _LayoutResult(
      lines: List<TextLayoutLine>.unmodifiable(textLines),
      sourceGraphemeToBufferOffset: List<int>.unmodifiable(sourceToBuffer),
    );
  }

  Iterable<TextLayoutRun> _runsFor(List<_ClusterToken> tokens) sync* {
    _MutableRun? current;
    for (final token in tokens) {
      if (current != null &&
          current.style == token.style &&
          current.sourceEnd == token.sourceStart) {
        current
          ..buffer.write(token.text)
          ..sourceEnd = token.sourceEnd;
        continue;
      }
      if (current != null) {
        yield current.toImmutable();
      }
      current = _MutableRun(
        style: token.style,
        sourceStart: token.sourceStart,
        sourceEnd: token.sourceEnd,
      )..buffer.write(token.text);
    }
    if (current != null) {
      yield current.toImmutable();
    }
  }
}

final class _SourceRun {
  const _SourceRun(this.text, this.style, this.sourceStart, this.sourceEnd);

  final String text;
  final TextStyle style;
  final int sourceStart;
  final int sourceEnd;
}

final class _ClusterToken {
  const _ClusterToken({
    required this.text,
    required this.style,
    required this.sourceStart,
    required this.sourceEnd,
    required this.width,
  });

  final String text;
  final TextStyle style;
  final int sourceStart;
  final int sourceEnd;
  final int width;

  bool get isWhitespace => text.trim().isEmpty;
}

final class _LineBuild {
  const _LineBuild({
    required this.tokens,
    required this.width,
    required this.explicitNewlineSourceStart,
  });

  final List<_ClusterToken> tokens;
  final int width;
  final int? explicitNewlineSourceStart;
}

final class _MutableRun {
  _MutableRun({
    required this.style,
    required this.sourceStart,
    required this.sourceEnd,
  });

  final StringBuffer buffer = StringBuffer();
  final TextStyle style;
  final int sourceStart;
  int sourceEnd;

  TextLayoutRun toImmutable() => TextLayoutRun(
    text: buffer.toString(),
    style: style,
    sourceStart: sourceStart,
    sourceEnd: sourceEnd,
  );
}

final class _LayoutResult {
  const _LayoutResult({
    required this.lines,
    required this.sourceGraphemeToBufferOffset,
  });

  final List<TextLayoutLine> lines;
  final List<int> sourceGraphemeToBufferOffset;

  /// Maximum laid-out line width in terminal cells, derived from [lines]
  /// exactly as [TextLayout.maxLineWidth] derives it.
  int get maxLineWidth =>
      lines.isEmpty ? 0 : lines.map((line) => line.width).reduce(math.max);
}
