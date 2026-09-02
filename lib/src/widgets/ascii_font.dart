import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

import '../core/color.dart';
import '../core/grapheme_metrics.dart';
import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/box.dart';
import '../rendering/object.dart';
import '../rendering/text_highlight.dart';
import 'ascii_font_data.dart';

/// Seven Noir-designed treatments of the built-in 5x7 display alphabet.
enum AsciiFontFamily {
  /// Compact half-block font.
  tiny,

  /// Solid block font.
  block,

  /// Block font with a lighter offset shadow.
  shade,

  /// Slanted block font.
  slick,

  /// Double-scale solid font.
  huge,

  /// Connected grid-line font.
  grid,

  /// Two-color tiled font.
  pallet,
}

/// Paints text using Noir's built-in multi-row terminal alphabet.
class AsciiFont extends RenderObjectWidget {
  /// Configures naturally sized ASCII-art [text].
  const AsciiFont(
    this.text, {
    super.key,
    this.family = AsciiFontFamily.tiny,
    this.color = Color.white,
    this.colors,
    this.backgroundColor,
    this.selection,
  });

  /// Source text; unsupported characters use the font's space width.
  final String text;

  /// Font table used to rasterize [text].
  final AsciiFontFamily family;

  /// Solid glyph color when [colors] is absent.
  final Color color;

  /// Palette for tagged multi-color fonts, with the first color as fallback.
  final List<Color>? colors;

  /// Optional fill behind the complete natural font box.
  final Color? backgroundColor;

  /// Optional UTF-16 source selection mapped across complete glyphs.
  final TextHighlight? selection;

  @override
  @internal
  RenderObject createRenderObject(BuildContext context) => RenderAsciiFont(
    text: text,
    family: family,
    color: color,
    colors: colors,
    backgroundColor: backgroundColor,
    selection: selection,
  );

  @override
  @internal
  void updateRenderObject(BuildContext context, RenderAsciiFont renderObject) {
    renderObject
      ..text = text
      ..family = family
      ..color = color
      ..colors = colors
      ..backgroundColor = backgroundColor
      ..selection = selection;
  }
}

/// Render object for [AsciiFont].
final class RenderAsciiFont extends RenderBox {
  /// Creates an ASCII font render object from snapshotted paint inputs.
  RenderAsciiFont({
    required String text,
    required AsciiFontFamily family,
    required Color color,
    required List<Color>? colors,
    required Color? backgroundColor,
    required TextHighlight? selection,
  }) : _text = text,
       _family = family,
       _color = color,
       _colors = _snapshotColors(colors),
       _backgroundColor = backgroundColor,
       _selection = selection;

  String _text;
  AsciiFontFamily _family;
  Color _color;
  List<Color>? _colors;
  Color? _backgroundColor;
  TextHighlight? _selection;

  /// Source text.
  String get text => _text;
  set text(String value) {
    if (_text == value) return;
    _text = value;
    markNeedsLayout();
  }

  /// Active font family.
  AsciiFontFamily get family => _family;
  set family(AsciiFontFamily value) {
    if (_family == value) return;
    _family = value;
    markNeedsLayout();
  }

  /// Solid fallback color.
  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  /// Multi-color palette.
  List<Color>? get colors => _colors;
  set colors(List<Color>? value) {
    final next = _snapshotColors(value);
    if (_listEquals(_colors, next)) return;
    _colors = next;
    markNeedsPaint();
  }

  /// Complete-box background fill.
  Color? get backgroundColor => _backgroundColor;
  set backgroundColor(Color? value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    markNeedsPaint();
  }

  /// Source selection mapped to glyph boxes.
  TextHighlight? get selection => _selection;
  set selection(TextHighlight? value) {
    if (_selection == value) return;
    _selection = value;
    markNeedsPaint();
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final definition = _definition(_family);
    size = Size(
      constraints.constrainWidth(_measureWidth(_text, definition)),
      constraints.constrainHeight(definition.lines),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.width <= 0 || size.height <= 0) return;
    final origin = offset + Offset(x, y);
    if (_backgroundColor case final background?) {
      context.canvas.fillRect(origin & size, background);
    }
    context.canvas.save();
    try {
      context.canvas.clipRect(origin & size);
      _paintGlyphs(context, origin, _definition(_family));
    } finally {
      context.canvas.restore();
    }
  }

  void _paintGlyphs(
    PaintingContext context,
    Offset origin,
    _AsciiFontDefinition definition,
  ) {
    final palette = _colors ?? <Color>[_color];
    final fallback = definition.chars[' '];
    final selection = _selection;
    var currentX = 0;
    var sourceOffset = 0;
    final graphemes = _text.characters.toList(growable: false);
    for (
      var characterIndex = 0;
      characterIndex < graphemes.length;
      characterIndex++
    ) {
      final source = graphemes[characterIndex];
      final lookupKey = _asciiLookupKey(source);
      final glyph = lookupKey == null ? null : definition.chars[lookupKey];
      final lines = glyph ?? fallback;
      final glyphWidth = _glyphWidth(lines);
      final sourceEnd = sourceOffset + source.length;
      final selected =
          selection != null &&
          sourceOffset < selection.end &&
          sourceEnd > selection.start;
      final selectionBackground = selected ? selection.backgroundColor : null;
      final selectionForeground = selected ? selection.foregroundColor : null;
      if (selectionBackground != null) {
        context.canvas.fillRect(
          Rect.fromLTWH(
            origin.dx + currentX,
            origin.dy,
            glyphWidth,
            definition.lines,
          ),
          selectionBackground,
        );
      }
      if (lines != null) {
        for (
          var row = 0;
          row < math.min(definition.lines, lines.length);
          row++
        ) {
          var segmentX = currentX;
          for (final segment in _parseSegments(lines[row])) {
            final foreground =
                selectionForeground ??
                palette.elementAtOrNull(segment.colorIndex) ??
                palette.first;
            _drawFontSegment(
              context,
              segment.text,
              Offset(origin.dx + segmentX, origin.dy + row),
              foreground,
            );
            segmentX += terminalStringWidth(segment.text);
          }
        }
      }
      currentX += glyphWidth;
      if (characterIndex < graphemes.length - 1) {
        currentX += definition.letterSpacing;
      }
      sourceOffset = sourceEnd;
    }
  }
}

void _drawFontSegment(
  PaintingContext context,
  String text,
  Offset origin,
  Color foreground,
) {
  final pending = StringBuffer();
  var pendingX = 0;
  var cursor = 0;

  void flush() {
    if (pending.isEmpty) return;
    context.canvas.drawText(
      pending.toString(),
      Offset(origin.dx + pendingX, origin.dy),
      foreground,
    );
    pending.clear();
  }

  for (final grapheme in text.characters) {
    if (grapheme == ' ') {
      flush();
    } else {
      if (pending.isEmpty) pendingX = cursor;
      pending.write(grapheme);
    }
    cursor += terminalCellWidth(grapheme);
  }
  flush();
}

final class _AsciiFontDefinition {
  const _AsciiFontDefinition({
    required this.lines,
    required this.letterSpacing,
    required this.chars,
  });

  final int lines;
  final int letterSpacing;
  final Map<String, List<String>> chars;
}

final class _FontSegment {
  const _FontSegment(this.text, this.colorIndex);
  final String text;
  final int colorIndex;
}

final Map<AsciiFontFamily, _AsciiFontDefinition> _definitions = {};

_AsciiFontDefinition _definition(AsciiFontFamily family) =>
    _definitions.putIfAbsent(family, () => _buildDefinition(family));

_AsciiFontDefinition _buildDefinition(AsciiFontFamily family) {
  final chars = noirAsciiGlyphs.map(
    (character, glyph) => MapEntry(
      character,
      List<String>.unmodifiable(_transformGlyph(family, glyph)),
    ),
  );
  return _AsciiFontDefinition(
    lines: chars[' ']!.length,
    letterSpacing: 1,
    chars: Map<String, List<String>>.unmodifiable(chars),
  );
}

List<String> _transformGlyph(AsciiFontFamily family, List<String> glyph) =>
    switch (family) {
      AsciiFontFamily.tiny => _tinyGlyph(glyph),
      AsciiFontFamily.block => _solidGlyph(glyph),
      AsciiFontFamily.shade => _shadeGlyph(glyph),
      AsciiFontFamily.slick => _slickGlyph(glyph),
      AsciiFontFamily.huge => _hugeGlyph(glyph),
      AsciiFontFamily.grid => _gridGlyph(glyph),
      AsciiFontFamily.pallet => _palletGlyph(glyph),
    };

List<String> _tinyGlyph(List<String> glyph) {
  final width = glyph.first.length;
  return <String>[
    for (var row = 0; row < glyph.length; row += 2)
      String.fromCharCodes(<int>[
        for (var column = 0; column < width; column++)
          switch ((
            glyph[row][column] == '#',
            row + 1 < glyph.length && glyph[row + 1][column] == '#',
          )) {
            (true, true) => 0x2588,
            (true, false) => 0x2580,
            (false, true) => 0x2584,
            (false, false) => 0x20,
          },
      ]),
  ];
}

List<String> _solidGlyph(List<String> glyph) => <String>[
  for (final row in glyph) row.replaceAll('#', '█'),
];

List<String> _shadeGlyph(List<String> glyph) {
  final width = glyph.first.length;
  final cells = List<List<int>>.generate(
    glyph.length + 1,
    (_) => List<int>.filled(width + 1, 0),
  );
  for (var row = 0; row < glyph.length; row++) {
    for (var column = 0; column < width; column++) {
      if (glyph[row][column] == '#') cells[row + 1][column + 1] = 2;
    }
  }
  for (var row = 0; row < glyph.length; row++) {
    for (var column = 0; column < width; column++) {
      if (glyph[row][column] == '#') cells[row][column] = 1;
    }
  }
  return <String>[
    for (final row in cells) _taggedRow(row, secondaryPixel: '░'),
  ];
}

List<String> _slickGlyph(List<String> glyph) {
  final maxShift = (glyph.length - 1) ~/ 2;
  final width = glyph.first.length + maxShift;
  return <String>[
    for (var row = 0; row < glyph.length; row++)
      glyph[row]
          .replaceAll('#', '█')
          .padLeft(glyph.first.length + ((glyph.length - 1 - row) ~/ 2))
          .padRight(width),
  ];
}

List<String> _hugeGlyph(List<String> glyph) => <String>[
  for (final row in glyph) ...<String>[_doubleWidth(row), _doubleWidth(row)],
];

String _doubleWidth(String row) {
  final output = StringBuffer();
  for (var column = 0; column < row.length; column++) {
    output.write(row[column] == '#' ? '██' : '  ');
  }
  return output.toString();
}

List<String> _gridGlyph(List<String> glyph) {
  final width = glyph.first.length;
  return <String>[
    for (var row = 0; row < glyph.length; row++)
      String.fromCharCodes(<int>[
        for (var column = 0; column < width; column++)
          if (glyph[row][column] != '#')
            0x20
          else
            _gridCodePoint(
              up: row > 0 && glyph[row - 1][column] == '#',
              right: column + 1 < width && glyph[row][column + 1] == '#',
              down: row + 1 < glyph.length && glyph[row + 1][column] == '#',
              left: column > 0 && glyph[row][column - 1] == '#',
            ),
      ]),
  ];
}

int _gridCodePoint({
  required bool up,
  required bool right,
  required bool down,
  required bool left,
}) {
  final mask = (up ? 1 : 0) | (right ? 2 : 0) | (down ? 4 : 0) | (left ? 8 : 0);
  return switch (mask) {
    0 => 0x25cf, // ●
    1 => 0x2579, // ╹
    2 => 0x257a, // ╺
    3 => 0x2517, // ┗
    4 => 0x257b, // ╻
    5 => 0x2503, // ┃
    6 => 0x250f, // ┏
    7 => 0x2523, // ┣
    8 => 0x2578, // ╸
    9 => 0x251b, // ┛
    10 => 0x2501, // ━
    11 => 0x253b, // ┻
    12 => 0x2513, // ┓
    13 => 0x252b, // ┫
    14 => 0x2533, // ┳
    15 => 0x254b, // ╋
    _ => throw StateError('unreachable grid mask'),
  };
}

List<String> _palletGlyph(List<String> glyph) {
  final width = glyph.first.length;
  return <String>[
    for (var row = 0; row < glyph.length; row++)
      _taggedRow(<int>[
        for (var column = 0; column < width; column++)
          if (glyph[row][column] == '#') 1 + ((row + column) & 1) else 0,
      ]),
  ];
}

String _taggedRow(List<int> cells, {String secondaryPixel = '█'}) {
  final output = StringBuffer();
  for (final cell in cells) {
    output.write(switch (cell) {
      0 => ' ',
      1 => '<c1>█</c1>',
      2 => '<c2>$secondaryPixel</c2>',
      _ => throw StateError('unknown ASCII font color index $cell'),
    });
  }
  return output.toString();
}

int _measureWidth(String text, _AsciiFontDefinition definition) {
  final characters = text.characters.toList(growable: false);
  var width = 0;
  for (var index = 0; index < characters.length; index++) {
    final lookupKey = _asciiLookupKey(characters[index]);
    width += _glyphWidth(
      (lookupKey == null ? null : definition.chars[lookupKey]) ??
          definition.chars[' '],
    );
    if (index < characters.length - 1) width += definition.letterSpacing;
  }
  return width;
}

String? _asciiLookupKey(String grapheme) {
  if (grapheme.length != 1) return null;
  final codeUnit = grapheme.codeUnitAt(0);
  if (codeUnit < 0x20 || codeUnit > 0x7e) return null;
  return codeUnit >= 0x61 && codeUnit <= 0x7a
      ? String.fromCharCode(codeUnit - 0x20)
      : grapheme;
}

int _glyphWidth(List<String>? lines) => lines == null || lines.isEmpty
    ? 1
    : _parseSegments(lines.first).fold<int>(
        0,
        (width, segment) => width + terminalStringWidth(segment.text),
      );

final RegExp _colorTag = RegExp(r'<c(\d+)>(.*?)</c\d+>');

List<_FontSegment> _parseSegments(String line) {
  final segments = <_FontSegment>[];
  var offset = 0;
  for (final match in _colorTag.allMatches(line)) {
    if (match.start > offset) {
      segments.add(_FontSegment(line.substring(offset, match.start), 0));
    }
    segments.add(
      _FontSegment(
        match.group(2)!,
        math.max(0, int.parse(match.group(1)!) - 1),
      ),
    );
    offset = match.end;
  }
  if (offset < line.length) {
    segments.add(_FontSegment(line.substring(offset), 0));
  }
  return segments;
}

List<Color>? _snapshotColors(List<Color>? value) {
  if (value == null) return null;
  if (value.isEmpty) {
    throw ArgumentError.value(value, 'colors', 'must not be empty');
  }
  return List<Color>.unmodifiable(value);
}

bool _listEquals(List<Color>? left, List<Color>? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
