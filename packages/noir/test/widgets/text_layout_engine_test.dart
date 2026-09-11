import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart' show TextLayoutEngine;
import 'package:test/test.dart';

void main() {
  group('TextLayoutEngine', () {
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
