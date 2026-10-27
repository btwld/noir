import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart' show TextLayoutEngine;
import 'package:test/test.dart';

void main() {
  group('TextLayoutEngine', () {
    for (final (parts, width) in <(List<String>, int)>[
      (['👩', '\u200d', '💻x'], 3),
      (['🇺', '🇸x'], 3),
      (['👍', '🏽x'], 3),
      (['a', '\u0301x'], 2),
    ]) {
      test('span boundaries preserve the whole grapheme ${parts.join()}', () {
        final layout = const TextLayoutEngine().layout(
          TextSpan(children: [for (final part in parts) TextSpan(text: part)]),
          BoxConstraints(maxWidth: width),
        );

        expect(layout.lines.map((line) => line.text), [parts.join()]);
        expect(layout.size, Size(width, 1));
        expect(layout.lines.single.width, width);
        expect(layout.lines.single.runs.single.sourceStart, 0);
        expect(layout.lines.single.runs.single.sourceEnd, parts.join().length);
      });
    }

    test('a cross-span grapheme keeps its starting style and link', () {
      final firstLink = Uri.parse('https://example.com/first');
      final nextLink = Uri.parse('https://example.com/next');
      final layout = const TextLayoutEngine().layout(
        TextSpan(
          children: [
            TextSpan(
              text: 'a',
              style: const TextStyle(color: Color.red),
              uri: firstLink,
            ),
            TextSpan(
              text: '\u0301b',
              style: const TextStyle(color: Color.green),
              uri: nextLink,
            ),
          ],
        ),
        const BoxConstraints(maxWidth: 2),
      );

      final runs = layout.lines.single.runs;
      expect(layout.lines.single.width, 2);
      expect(runs, hasLength(2));
      expect(runs.first.text, 'a\u0301');
      expect(runs.first.style.color, Color.red);
      expect(runs.first.uri, firstLink);
      expect((runs.first.sourceStart, runs.first.sourceEnd), (0, 2));
      expect(runs.last.text, 'b');
      expect(runs.last.style.color, Color.green);
      expect(runs.last.uri, nextLink);
      expect((runs.last.sourceStart, runs.last.sourceEnd), (2, 3));
    });

    for (final span in [
      const TextSpan(text: 'a\r\nb'),
      const TextSpan(
        children: [
          TextSpan(text: 'a\r'),
          TextSpan(text: '\nb'),
        ],
      ),
    ]) {
      test('CRLF is one hard break with unchanged source offsets ($span)', () {
        final layout = const TextLayoutEngine().layout(
          span,
          const BoxConstraints(maxWidth: 10),
        );

        expect(layout.text, 'a\r\nb');
        expect(layout.lines.map((line) => line.text), ['a', 'b']);
        expect(layout.size, const Size(1, 2));
        expect(layout.lines.first.runs.single.sourceEnd, 1);
        expect(layout.lines.last.runs.single.sourceStart, 3);
        expect(layout.lines.last.runs.single.sourceEnd, 4);
      });
    }

    test('wraps text by terminal cells and preserves source offsets', () {
      final layout = const TextLayoutEngine().layout(
        const TextSpan(text: 'ab中c'),
        const BoxConstraints(maxWidth: 3),
      );

      expect(layout.lines.map((line) => line.text).toList(), ['ab', '中c']);
      expect(layout.size, const Size(3, 2));
      expect(layout.lines.first.runs.single.sourceStart, 0);
      expect(layout.lines.first.runs.single.sourceEnd, 2);
      expect(layout.lines.last.runs.single.sourceStart, 2);
      expect(layout.lines.last.runs.single.sourceEnd, 4);
    });

    test('keeps child TextSpan styles as separate layout runs', () {
      const style = TextStyle(color: Color.green);
      const bold = TextStyle(fontWeight: FontWeight.bold);
      final layout = const TextLayoutEngine().layout(
        const TextSpan(
          text: 'A',
          style: style,
          children: <InlineSpan>[TextSpan(text: 'B', style: bold)],
        ),
        const BoxConstraints(maxWidth: 10),
      );

      expect(layout.lines, hasLength(1));
      expect(layout.lines.single.runs, hasLength(2));
      expect(layout.lines.single.runs[0].text, 'A');
      expect(layout.lines.single.runs[0].style.color, Color.green);
      expect(layout.lines.single.runs[1].text, 'B');
      expect(
        layout.lines.single.runs[1].style.computedAttributes & Attr.bold,
        isNonZero,
      );
    });

    test('places styled text after a flag at its canonical cell', () {
      final layout = const TextLayoutEngine().layout(
        const TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '🇺🇸',
              style: TextStyle(color: Color.green),
            ),
            TextSpan(
              text: 'B',
              style: TextStyle(color: Color.red),
            ),
          ],
        ),
        const BoxConstraints(maxWidth: 3),
      );

      expect(layout.lines, hasLength(1));
      expect(layout.lines.single.width, 3);
      expect(layout.lines.single.text, '🇺🇸B');

      final wrapped = const TextLayoutEngine().layout(
        const TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '🇺🇸',
              style: TextStyle(color: Color.green),
            ),
            TextSpan(
              text: 'B',
              style: TextStyle(color: Color.red),
            ),
          ],
        ),
        const BoxConstraints(maxWidth: 2),
      );
      expect(wrapped.lines.map((line) => line.text), <String>['🇺🇸', 'B']);
    });

    test('places a styled run after a native-width format scalar', () {
      const span = TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: '\u200E',
            style: TextStyle(color: Color.green),
          ),
          TextSpan(
            text: 'B',
            style: TextStyle(color: Color.red),
          ),
        ],
      );
      final layout = const TextLayoutEngine().layout(
        span,
        const BoxConstraints(maxWidth: 2),
      );
      expect(layout.lines, hasLength(1));
      expect(layout.lines.single.width, 2);

      final wrapped = const TextLayoutEngine().layout(
        span,
        const BoxConstraints(maxWidth: 1),
      );
      expect(wrapped.lines.map((line) => line.text), <String>['\u200E', 'B']);
    });

    test('wraps at word boundaries when possible', () {
      final layout = const TextLayoutEngine().layout(
        const TextSpan(text: 'alpha beta'),
        const BoxConstraints(maxWidth: 7),
      );

      expect(layout.lines.map((line) => line.text).toList(), [
        'alpha ',
        'beta',
      ]);
    });
  });
}
