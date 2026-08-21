import 'package:noir/noir.dart';
import 'package:noir/src/widgets/ascii_font_data.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/widget_tester.dart';

void main() {
  test('Noir base alphabet defines normalized printable ASCII glyphs', () {
    final expected = <String>{
      for (var codePoint = 0x20; codePoint <= 0x7e; codePoint++)
        String.fromCharCode(codePoint).toUpperCase(),
    };
    expect(noirAsciiGlyphs.keys.toSet(), expected);
    for (final entry in noirAsciiGlyphs.entries) {
      expect(entry.value, hasLength(7), reason: entry.key);
      for (final row in entry.value) {
        expect(row, hasLength(5), reason: entry.key);
        expect(row, matches(RegExp(r'^[ #]{5}$')), reason: entry.key);
      }
    }
  });

  test('every printable ASCII character has a visible glyph', () {
    final missing = <String>[];
    for (var codePoint = 0x21; codePoint <= 0x7e; codePoint++) {
      final character = String.fromCharCode(codePoint);
      final capture = BufferCapture(width: 16, height: 16);
      try {
        final frame = capture.capture(AsciiFont(character));
        if (frame.getRegion(0, 0, 16, 16).trim().isEmpty) {
          missing.add(character);
        }
      } finally {
        capture.dispose();
      }
    }

    expect(missing, isEmpty);
  });

  test('every Noir ASCII font reports its exact natural size', () {
    const expectedSizes = <AsciiFontFamily, (int, int)>{
      AsciiFontFamily.tiny: (5, 4),
      AsciiFontFamily.block: (5, 7),
      AsciiFontFamily.shade: (6, 8),
      AsciiFontFamily.slick: (8, 7),
      AsciiFontFamily.huge: (10, 14),
      AsciiFontFamily.grid: (5, 7),
      AsciiFontFamily.pallet: (5, 7),
    };
    for (final family in AsciiFontFamily.values) {
      final tester = WidgetTester();
      try {
        tester.pumpWidget(AsciiFont('A', family: family));
        expect(
          (tester.width, tester.height),
          expectedSizes[family],
          reason: family.name,
        );
      } finally {
        tester.dispose();
      }
    }
  });

  test('all seven families produce distinct rendered treatments', () {
    final signatures = <String>{};
    for (final family in AsciiFontFamily.values) {
      final capture = BufferCapture(width: 16, height: 16);
      try {
        final frame = capture.capture(
          AsciiFont(
            'A',
            family: family,
            colors: const <Color>[Color.cyan, Color.blue],
          ),
        );
        signatures.add(
          frame.cells
              .expand((row) => row)
              .map(
                (cell) =>
                    '${cell.char}:${cell.foreground.toHex(includeAlpha: false)}',
              )
              .join('|'),
        );
      } finally {
        capture.dispose();
      }
    }

    expect(signatures, hasLength(AsciiFontFamily.values.length));
  });

  test('tiny font paints its canonical four-row A glyph', () {
    final capture = BufferCapture(width: 5, height: 4);
    try {
      final frame = capture.capture(const AsciiFont('A'));
      expect(frame.getRegion(0, 0, 5, 4), '▄▀▀▀▄\n█▄▄▄█\n█   █\n▀   ▀');
    } finally {
      capture.dispose();
    }
  });

  test('unsupported Unicode does not case-fold into ASCII glyphs', () {
    final capture = BufferCapture(width: 11, height: 4);
    try {
      final frame = capture.capture(const AsciiFont('ıſ'));
      expect(frame.getRegion(0, 0, 11, 4).trim(), isEmpty);
    } finally {
      capture.dispose();
    }
  });

  test('constrained font clips glyph paint to its laid-out box', () {
    final capture = BufferCapture(width: 5, height: 4);
    try {
      final frame = capture.capture(
        const SizedBox(
          width: 2,
          height: 2,
          child: AsciiFont('A', family: AsciiFontFamily.block),
        ),
      );

      expect(frame.getRegion(0, 0, 5, 4), ' █   \n█    \n     \n     ');
    } finally {
      capture.dispose();
    }
  });

  test('background fills spaces across the complete natural box', () {
    final capture = BufferCapture(width: 5, height: 4);
    try {
      final frame = capture.capture(
        const AsciiFont('A', backgroundColor: Color.red),
      );

      expect(frame, BufferMatchers.hasBackgroundAt(2, 2, Color.red));
      expect(frame.getChar(2, 2), ' ');
    } finally {
      capture.dispose();
    }
  });

  test('font color tags select matching palette entries', () {
    final capture = BufferCapture(width: 5, height: 7);
    try {
      final frame = capture.capture(
        const AsciiFont(
          'A',
          family: AsciiFontFamily.pallet,
          colors: <Color>[Color.red, Color.blue],
        ),
      );
      expect(frame, BufferMatchers.hasColorAt(2, 0, Color.red));
      expect(frame, BufferMatchers.hasColorAt(1, 0, Color.blue));
    } finally {
      capture.dispose();
    }
  });

  test('selection overrides glyph foreground and background', () {
    final capture = BufferCapture(width: 11, height: 4);
    try {
      final frame = capture.capture(
        const AsciiFont(
          'AB',
          selection: TextHighlight(
            start: 1,
            end: 2,
            foregroundColor: Color.yellow,
            backgroundColor: Color.blue,
          ),
        ),
      );
      expect(frame, BufferMatchers.hasColorAt(6, 0, Color.yellow));
      expect(frame, BufferMatchers.hasBackgroundAt(6, 0, Color.blue));
      expect(frame, BufferMatchers.hasColorAt(0, 0, Color.white));
    } finally {
      capture.dispose();
    }
  });

  test('font glyph spaces preserve content painted underneath', () {
    final capture = BufferCapture(width: 5, height: 4);
    try {
      final frame = capture.capture(
        const Stack(
          children: <Widget>[
            Text('xxxxx\nxxxxx\nxxxxx\nxxxxx'),
            AsciiFont('T'),
          ],
        ),
      );

      expect(frame.getRegion(0, 0, 5, 4), '▀▀█▀▀\nxx█xx\nxx█xx\nxx▀xx');
    } finally {
      capture.dispose();
    }
  });
}
