import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/core/ansi_row.dart';
import 'package:test/test.dart';

void main() {
  group('sgrSequence', () {
    test('starts from a reset, then lists attributes and both colors', () {
      expect(
        sgrSequence(
          attributes: Attr.bold | Attr.underline,
          foreground: (red: 1, green: 2, blue: 3),
          background: (red: 4, green: 5, blue: 6),
        ),
        '\x1b[0;1;4;38;2;1;2;3;48;2;4;5;6m',
      );
    });

    test('maps every attribute bit to its SGR code', () {
      expect(
        sgrSequence(
          attributes:
              Attr.bold |
              Attr.dim |
              Attr.italic |
              Attr.underline |
              Attr.blink |
              Attr.reverse |
              Attr.strike,
        ),
        '\x1b[0;1;2;3;4;5;7;9m',
      );
    });

    test('leaves a null color at the terminal default', () {
      expect(sgrSequence(attributes: 0), '\x1b[0m');
      expect(
        sgrSequence(
          attributes: Attr.dim,
          background: (red: 9, green: 8, blue: 7),
        ),
        '\x1b[0;2;48;2;9;8;7m',
      );
    });
  });

  group('encodeAnsiRow', () {
    test('writes unstyled text with no escape sequence', () {
      expect(encodeAnsiRow(_cells('ab')), 'ab');
    });

    test('trims trailing blank cells and keeps inner ones', () {
      expect(encodeAnsiRow(_cells('a b   ')), 'a b');
    });

    test('an all-blank row is empty', () {
      expect(encodeAnsiRow(_cells('    ')), isEmpty);
      expect(encodeAnsiRow(const <AnsiRowCell>[]), isEmpty);
    });

    test('keeps a trailing space that a background makes visible', () {
      expect(
        encodeAnsiRow(const <AnsiRowCell>[
          AnsiRowCell('a'),
          AnsiRowCell(' ', background: Color.blue),
          AnsiRowCell(' '),
        ]),
        'a\x1b[0;38;2;255;255;255;48;2;0;0;255m \x1b[0m',
      );
    });

    test('keeps a trailing space that an attribute makes visible', () {
      expect(
        encodeAnsiRow(const <AnsiRowCell>[
          AnsiRowCell('a'),
          AnsiRowCell(' ', attributes: Attr.underline),
          AnsiRowCell(' ', attributes: Attr.bold),
        ]),
        'a\x1b[0;4m \x1b[0m',
      );
    });

    test('writes the framework text color as the terminal default', () {
      expect(encodeAnsiRow(const <AnsiRowCell>[AnsiRowCell('a')]), 'a');
    });

    test('keeps the framework text color over a painted background', () {
      // The terminal's own text color is only known to be readable on the
      // terminal's own background.
      expect(
        encodeAnsiRow(const <AnsiRowCell>[
          AnsiRowCell('a', background: Color.black),
        ]),
        '\x1b[0;38;2;255;255;255;48;2;0;0;0ma\x1b[0m',
      );
    });

    test('blends a partly transparent text color over its background', () {
      expect(
        encodeAnsiRow(const <AnsiRowCell>[
          AnsiRowCell(
            'a',
            foreground: Color.whiteTransparent,
            background: Color.black,
          ),
        ]),
        '\x1b[0;38;2;128;128;128;48;2;0;0;0ma\x1b[0m',
      );
      expect(
        encodeAnsiRow(const <AnsiRowCell>[
          AnsiRowCell(
            'a',
            foreground: Color(1, 0, 0, 0.5),
            background: Color.blue,
          ),
        ]),
        '\x1b[0;38;2;128;0;127;48;2;0;0;255ma\x1b[0m',
      );
    });

    test('blends a partly transparent text color over black elsewhere', () {
      // OpenTUI has already blended such a cell over its black backdrop by
      // the time a row is read. A cell that still carries alpha gets the same
      // backdrop here.
      expect(
        encodeAnsiRow(const <AnsiRowCell>[
          AnsiRowCell('a', foreground: Color.whiteTransparent),
        ]),
        '\x1b[0;38;2;128;128;128ma\x1b[0m',
      );
    });

    test('a fully transparent text color takes the color behind it', () {
      expect(
        encodeAnsiRow(const <AnsiRowCell>[
          AnsiRowCell(
            'a',
            foreground: Color(1, 1, 1, 0),
            background: Color.blue,
          ),
        ]),
        '\x1b[0;38;2;0;0;255;48;2;0;0;255ma\x1b[0m',
      );
    });

    test('writes a transparent background as the terminal default', () {
      expect(
        encodeAnsiRow(const <AnsiRowCell>[
          AnsiRowCell('a', foreground: Color.red),
        ]),
        '\x1b[0;38;2;255;0;0ma\x1b[0m',
      );
      expect(
        encodeAnsiRow(const <AnsiRowCell>[
          AnsiRowCell('a', foreground: Color.red, background: Color.black),
        ]),
        '\x1b[0;38;2;255;0;0;48;2;0;0;0ma\x1b[0m',
      );
    });

    test('selects a style once per run and resets after the last cell', () {
      expect(
        encodeAnsiRow(const <AnsiRowCell>[
          AnsiRowCell('a', foreground: Color.red),
          AnsiRowCell('b', foreground: Color.red),
          AnsiRowCell('c'),
          AnsiRowCell('d', attributes: Attr.bold),
        ]),
        '\x1b[0;38;2;255;0;0mab\x1b[0mc\x1b[0;1md\x1b[0m',
      );
    });

    test('writes a wide glyph once and skips its trailing half', () {
      expect(
        encodeAnsiRow(const <AnsiRowCell>[
          AnsiRowCell('界'),
          AnsiRowCell(''),
          AnsiRowCell('a'),
        ]),
        '界a',
      );
    });

    test('writes a control character as a space, never as itself', () {
      expect(
        encodeAnsiRow(const <AnsiRowCell>[
          AnsiRowCell('a'),
          AnsiRowCell('\x1b'),
          AnsiRowCell('\x07'),
          AnsiRowCell('\x7f'),
          AnsiRowCell('\u009b'),
          AnsiRowCell('b'),
          AnsiRowCell('\r'),
        ]),
        'a    b',
      );
    });

    test('ignores every bit that is not an attribute flag', () {
      expect(
        encodeAnsiRow(const <AnsiRowCell>[
          // Link identifiers live above the attribute byte.
          AnsiRowCell('a', attributes: 0x100),
          AnsiRowCell('b', attributes: 0x200 | Attr.bold),
          // The eighth bit has no flag in Attr and no SGR code here.
          AnsiRowCell('c', attributes: 0x80 | Attr.bold),
          AnsiRowCell('d', attributes: 0x80),
        ]),
        'a\x1b[0;1mbc\x1b[0md',
      );
    });

    test('with colors off, drops colors and keeps attributes', () {
      expect(
        encodeAnsiRow(const <AnsiRowCell>[
          AnsiRowCell('a', foreground: Color.red, background: Color.blue),
          AnsiRowCell('b', foreground: Color.red, attributes: Attr.bold),
          AnsiRowCell(' ', background: Color.blue),
        ], colors: false),
        'a\x1b[0;1mb\x1b[0m',
      );
    });
  });

  group('readBufferRow', () {
    late Renderer renderer;

    setUp(() {
      renderer = Renderer.create(8, 2, testing: true)..setAutoFlush(false);
    });

    tearDown(() => renderer.dispose());

    test('reads one row of characters, colors and attributes', () {
      final buffer = renderer.nextBuffer
        ..clear(Color.transparent)
        ..drawText('top', 0, 0, Color.white)
        ..drawText(
          'ab',
          1,
          1,
          Color.red,
          bg: Color.blue,
          attributes: Attr.bold,
        );

      final row = readBufferRow(buffer, 1);

      expect(row, hasLength(8));
      expect(row.map((cell) => cell.text).join(), ' ab     ');
      expect(row[1].foreground, Color.red);
      expect(row[1].background, Color.blue);
      expect(row[1].attributes & Attr.bold, Attr.bold);
      expect(row[0].background.a, 0);
      expect(row[3].background.a, 0);
    });

    test('reports a wide glyph as one cell and an empty trailing half', () {
      final buffer = renderer.nextBuffer
        ..clear(Color.transparent)
        ..drawText('界a', 0, 0, Color.white);

      final row = readBufferRow(buffer, 0);

      expect(row[0].text, '界');
      expect(row[1].text, isEmpty);
      expect(row[2].text, 'a');
      expect(encodeAnsiRow(row), '界a');
    });

    test('reads a cell the native layer stored broken as a blank', () {
      // OpenTUI v0.5.1 mis-stores a zero-width character that stands alone.
      // Here it leaves a packed cell whose bytes are not valid UTF-8, and
      // then a stray byte as a cell of its own.
      final buffer = renderer.nextBuffer
        ..clear(Color.transparent)
        ..drawText('ab​cd', 0, 0, Color.white);

      final row = readBufferRow(buffer, 0);

      expect(row, hasLength(8));
      expect(encodeAnsiRow(row), 'ab  cd');
    });

    test('rejects a row outside the buffer', () {
      final buffer = renderer.nextBuffer;
      expect(() => readBufferRow(buffer, 2), throwsRangeError);
      expect(() => readBufferRow(buffer, -1), throwsRangeError);
    });
  });
}

List<AnsiRowCell> _cells(String text) => <AnsiRowCell>[
  for (final rune in text.runes) AnsiRowCell(String.fromCharCode(rune)),
];
