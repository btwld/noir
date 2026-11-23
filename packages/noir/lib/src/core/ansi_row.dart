// ignore_for_file: invalid_use_of_visible_for_testing_member
/// Cells to ANSI text: SGR selection and single-row serialization.
///
/// Noir's terminal path leaves ANSI output to OpenTUI. This is the Dart-side
/// writer for the two callers that own their output instead: the inline host,
/// which writes one row to a sink the application chose, and the demo
/// recorder under `tool/`.
library;

import 'package:meta/meta.dart';

import 'buffer.dart';
import 'color.dart';
import 'terminal_style.dart';

/// 8-bit channels of one SGR truecolor argument.
typedef SgrColor = ({int red, int green, int blue});

/// The flags [Attr] defines. Every other bit of a cell's attribute word is
/// ignored: the higher ones carry link identifiers, not style.
const int _attributeMask =
    Attr.bold |
    Attr.dim |
    Attr.italic |
    Attr.underline |
    Attr.blink |
    Attr.reverse |
    Attr.strike;

/// Attributes that change how a blank cell looks.
const int _visibleOnBlank = Attr.underline | Attr.reverse | Attr.strike;

/// Builds the SGR sequence that selects exactly [attributes] and both colors.
///
/// The sequence starts with a reset, so it does not depend on what a terminal
/// had selected before it. A null color stays at the terminal's default.
String sgrSequence({
  required int attributes,
  SgrColor? foreground,
  SgrColor? background,
}) {
  final codes = <int>[
    0,
    if (attributes & Attr.bold != 0) 1,
    if (attributes & Attr.dim != 0) 2,
    if (attributes & Attr.italic != 0) 3,
    if (attributes & Attr.underline != 0) 4,
    if (attributes & Attr.blink != 0) 5,
    if (attributes & Attr.reverse != 0) 7,
    if (attributes & Attr.strike != 0) 9,
    if (foreground != null) ...<int>[
      38,
      2,
      foreground.red,
      foreground.green,
      foreground.blue,
    ],
    if (background != null) ...<int>[
      48,
      2,
      background.red,
      background.green,
      background.blue,
    ],
  ];
  return '\x1b[${codes.join(';')}m';
}

/// One painted cell, as [encodeAnsiRow] reads it.
@immutable
final class AnsiRowCell {
  /// Describes a cell; the defaults are an unpainted cell's colors.
  const AnsiRowCell(
    this.text, {
    this.foreground = Color.white,
    this.background = Color.transparent,
    this.attributes = 0,
  });

  /// The grapheme in this cell, or empty for the trailing half of a wide one.
  final String text;

  /// Foreground color. [Color.white] is the framework's default text color.
  final Color foreground;

  /// Background color. Zero alpha means nothing painted a background here.
  final Color background;

  /// The cell's attribute word.
  final int attributes;
}

/// Reads row [row] of [buffer] into cells.
///
/// A cell whose text cannot be read back is reported as a blank. The pinned
/// OpenTUI stores a zero-width character that stands alone as cells that do
/// not hold valid text, and a row has to survive whatever a widget was
/// given to show.
///
/// Throws [RangeError] when [row] is outside the buffer.
List<AnsiRowCell> readBufferRow(Buffer buffer, int row) {
  final direct = buffer.getDirectAccess();
  RangeError.checkValueInInterval(row, 0, direct.height - 1, 'row');
  final width = direct.width;
  return <AnsiRowCell>[
    for (var x = 0; x < width; x++)
      AnsiRowCell(
        _cellText(buffer, row * width + x),
        foreground: direct.getForeground(x, row),
        background: direct.getBackground(x, row),
        attributes: direct.getAttributes(x, row),
      ),
  ];
}

String _cellText(Buffer buffer, int cellIndex) {
  try {
    return debugResolveBufferCell(buffer, cellIndex);
  } on Object {
    return ' ';
  }
}

/// Serializes [cells] as one row of text and SGR sequences.
///
/// The result has no cursor addressing and no line break, so the caller
/// decides where the row lands. Trailing blank cells are dropped, a style is
/// selected once per run of equal cells, and attributes are reset after the
/// last cell whenever any were selected.
///
/// Two colors are written as the terminal's own default rather than as RGB.
/// A background with zero alpha is a cell no widget painted behind, so it
/// keeps the terminal's background. Over such a cell, a foreground of opaque
/// [Color.white], the framework's default text color, keeps the terminal's
/// text color. Together they keep a row readable on a terminal whose
/// background the application does not own. Over a painted background the
/// foreground is always written, white included: the terminal's text color
/// is only known to be readable on the terminal's own background.
///
/// A partly transparent foreground is blended over what is behind it: the
/// cell's own background when one is written, and black otherwise, which is
/// the backdrop OpenTUI itself blends with. A partly transparent background
/// is written as its RGB channels.
///
/// With [colors] false every color is left at the terminal default, and
/// attributes such as bold and underline are still written.
///
/// A cell whose text holds a control character is written as a space, so
/// cell content can never start a control sequence of its own.
String encodeAnsiRow(Iterable<AnsiRowCell> cells, {bool colors = true}) {
  final row = cells.toList(growable: false);
  var end = row.length;
  while (end > 0 && _isBlank(row[end - 1], colors: colors)) {
    end--;
  }

  final output = StringBuffer();
  var selected = _plain;
  for (var index = 0; index < end; index++) {
    final cell = row[index];
    if (cell.text.isEmpty) {
      continue;
    }
    final style = _styleOf(cell, colors: colors);
    if (style != selected) {
      output.write(
        sgrSequence(
          attributes: style.attributes,
          foreground: style.foreground,
          background: style.background,
        ),
      );
      selected = style;
    }
    output.write(_printable(cell.text));
  }
  if (selected != _plain) {
    output.write(sgrSequence(attributes: 0));
  }
  return output.toString();
}

typedef _Style = ({int attributes, SgrColor? foreground, SgrColor? background});

const _Style _plain = (attributes: 0, foreground: null, background: null);

_Style _styleOf(AnsiRowCell cell, {required bool colors}) {
  final attributes = cell.attributes & _attributeMask;
  if (!colors) {
    return (attributes: attributes, foreground: null, background: null);
  }
  final background = _backgroundOf(cell.background);
  return (
    attributes: attributes,
    foreground: background == null && _isDefaultTextColor(cell.foreground)
        ? null
        : _blended(cell.foreground, over: background ?? _black),
    background: background,
  );
}

const SgrColor _black = (red: 0, green: 0, blue: 0);

/// [color] composited over [over] by its alpha, rounded as OpenTUI rounds.
SgrColor _blended(Color color, {required SgrColor over}) {
  final channels = _channels(color);
  final alpha = _channel(color.a);
  if (alpha == 255) {
    return channels;
  }
  final rest = 255 - alpha;
  int mix(int source, int backdrop) =>
      (source * alpha + backdrop * rest + 127) ~/ 255;
  return (
    red: mix(channels.red, over.red),
    green: mix(channels.green, over.green),
    blue: mix(channels.blue, over.blue),
  );
}

bool _isBlank(AnsiRowCell cell, {required bool colors}) {
  if (cell.text.isNotEmpty && _printable(cell.text) != ' ') {
    return false;
  }
  final style = _styleOf(cell, colors: colors);
  return style.background == null && style.attributes & _visibleOnBlank == 0;
}

/// [text], or a space when it holds a C0 or C1 control character or DEL.
String _printable(String text) {
  for (final rune in text.runes) {
    if (rune < 0x20 || (rune >= 0x7f && rune < 0xa0)) {
      return ' ';
    }
  }
  return text;
}

/// Whether [color] is opaque white, the color of text with no style.
bool _isDefaultTextColor(Color color) =>
    _channel(color.a) == 255 &&
    _channel(color.r) == 255 &&
    _channel(color.g) == 255 &&
    _channel(color.b) == 255;

SgrColor? _backgroundOf(Color color) =>
    _channel(color.a) == 0 ? null : _channels(color);

SgrColor _channels(Color color) =>
    (red: _channel(color.r), green: _channel(color.g), blue: _channel(color.b));

int _channel(double value) => (value * 255).round();
