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
  TextLayout({
    required this.text,
    required this.style,
    required this.indexMap,
    required List<TextLayoutLine> lines,
    required this.size,
  }) : lines = List<TextLayoutLine>.unmodifiable(lines);

  /// Plain source text before soft wrapping.
  final String text;

  /// Effective root style.
  final TextStyle style;

  /// Unicode/cell index map for source [text].
  final TextIndexMap indexMap;

  /// Laid-out lines in paint order.
  final List<TextLayoutLine> lines;

  /// Terminal-cell size.
  final Size size;

  /// Maximum laid-out line width in terminal cells.
  int get maxLineWidth =>
      lines.isEmpty ? 0 : lines.map((line) => line.width).reduce(math.max);

  /// Number of laid-out lines.
  int get lineCount => math.max(1, lines.length);
}

/// One laid-out terminal text line.
final class TextLayoutLine {
  /// Creates a laid-out text line.
  TextLayoutLine({required List<TextLayoutRun> runs, required this.width})
    : runs = List<TextLayoutRun>.unmodifiable(runs);

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
    this.uri,
  });

  /// Run text.
  final String text;

  /// Effective style.
  final TextStyle style;

  /// Source UTF-16 start offset.
  final int sourceStart;

  /// Source UTF-16 end offset.
  final int sourceEnd;

  /// Semantic hyperlink for this laid-out run.
  final Uri? uri;
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
    _flatten(root, style, null, textBuffer, runs);
    final text = textBuffer.toString();
    final effectiveStyle = root is TextSpan ? root.style ?? style : style;
    final indexMap = TextIndexMap(text);
    final laidOut = _layoutRuns(runs, constraints.maxWidth);
    return TextLayout(
      text: text,
      style: effectiveStyle,
      indexMap: indexMap,
      lines: laidOut.lines,
      size: Size(
        constraints.constrainWidth(laidOut.maxLineWidth),
        constraints.constrainHeight(math.max(1, laidOut.lines.length)),
      ),
    );
  }

  void _flatten(
    InlineSpan span,
    TextStyle inheritedStyle,
    Uri? inheritedUri,
    StringBuffer textBuffer,
    List<_SourceRun> runs,
  ) {
    if (span is TextSpan) {
      final style = span.style ?? inheritedStyle;
      final uri = span.uri ?? inheritedUri;
      final value = span.text;
      if (value != null && value.isNotEmpty) {
        final start = textBuffer.length;
        textBuffer.write(value);
        runs.add(_SourceRun(value, style, uri, start, textBuffer.length));
      }
      for (final child in span.children) {
        _flatten(child, style, uri, textBuffer, runs);
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
    runs.add(
      _SourceRun(value, inheritedStyle, inheritedUri, start, textBuffer.length),
    );
  }

  _LayoutResult _layoutRuns(List<_SourceRun> sourceRuns, int? maxWidth) {
    final lines = <_LineBuild>[];
    final current = <_ClusterToken>[];
    var currentWidth = 0;

    int widthOf(List<_ClusterToken> tokens) =>
        tokens.fold(0, (sum, token) => sum + token.width);

    void flushLine() {
      lines.add(
        _LineBuild(
          tokens: List<_ClusterToken>.unmodifiable(current),
          width: currentWidth,
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
          flushLine();
          sourceOffset += cluster.length;
          continue;
        }

        final token = _ClusterToken(
          text: cluster,
          style: run.style,
          uri: run.uri,
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

    final textLines = lines
        .map(
          (line) => TextLayoutLine(
            runs: List<TextLayoutRun>.unmodifiable(_runsFor(line.tokens)),
            width: line.width,
          ),
        )
        .toList(growable: false);

    return _LayoutResult(lines: List<TextLayoutLine>.unmodifiable(textLines));
  }

  Iterable<TextLayoutRun> _runsFor(List<_ClusterToken> tokens) sync* {
    _MutableRun? current;
    for (final token in tokens) {
      if (current != null &&
          current.style == token.style &&
          current.uri == token.uri &&
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
        uri: token.uri,
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
  const _SourceRun(
    this.text,
    this.style,
    this.uri,
    this.sourceStart,
    this.sourceEnd,
  );

  final String text;
  final TextStyle style;
  final Uri? uri;
  final int sourceStart;
  final int sourceEnd;
}

final class _ClusterToken {
  const _ClusterToken({
    required this.text,
    required this.style,
    required this.uri,
    required this.sourceStart,
    required this.sourceEnd,
    required this.width,
  });

  final String text;
  final TextStyle style;
  final Uri? uri;
  final int sourceStart;
  final int sourceEnd;
  final int width;

  bool get isWhitespace => text.trim().isEmpty;
}

final class _LineBuild {
  const _LineBuild({required this.tokens, required this.width});

  final List<_ClusterToken> tokens;
  final int width;
}

final class _MutableRun {
  _MutableRun({
    required this.style,
    required this.uri,
    required this.sourceStart,
    required this.sourceEnd,
  });

  final StringBuffer buffer = StringBuffer();
  final TextStyle style;
  final Uri? uri;
  final int sourceStart;
  int sourceEnd;

  TextLayoutRun toImmutable() => TextLayoutRun(
    text: buffer.toString(),
    style: style,
    uri: uri,
    sourceStart: sourceStart,
    sourceEnd: sourceEnd,
  );
}

final class _LayoutResult {
  const _LayoutResult({required this.lines});

  final List<TextLayoutLine> lines;

  /// Maximum laid-out line width in terminal cells, derived from [lines]
  /// exactly as [TextLayout.maxLineWidth] derives it.
  int get maxLineWidth =>
      lines.isEmpty ? 0 : lines.map((line) => line.width).reduce(math.max);
}
