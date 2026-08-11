import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart' show TextLayoutEngine;
import 'package:test/test.dart';

void main() {
  group('TextLayoutEngine', () {
    test('wraps text by terminal cells and preserves source mappings', () {
      final layout = const TextLayoutEngine().layout(
        const TextSpan(text: 'ab中c'),
        const BoxConstraints(maxWidth: 3),
      );

      expect(layout.lines.map((line) => line.text).toList(), ['ab', '中c']);
      expect(layout.size, const Size(3, 2));
      expect(layout.bufferText, 'ab\n中c');
      expect(layout.bufferOffsetForSourceUtf16(3), 4);
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
