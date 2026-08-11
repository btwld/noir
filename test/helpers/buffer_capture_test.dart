import 'package:noir/noir.dart';
import 'package:test/test.dart';

import 'buffer_capture.dart';

void main() {
  group('BufferCapture render pipeline', () {
    late BufferCapture capture;

    setUp(() {
      capture = BufferCapture(width: 40, height: 10);
    });

    tearDown(() {
      capture.dispose();
    });

    test('Row with two Text children produces AB not ABB (no double paint)', () {
      // This test verifies that the render pipeline paints once from root,
      // not recursively on each element (which would cause double painting).
      const widget = Row(children: [Text('A'), Text('B')]);

      final result = capture.capture(widget);
      final text = result.toText();

      // Should produce "AB" at the start, not "ABB" or other double-paint artifacts
      expect(
        text.startsWith('AB'),
        isTrue,
        reason: 'Row with Text(A), Text(B) should render as AB',
      );

      // Verify no 'ABB' anywhere (would indicate double-paint)
      expect(
        text.contains('ABB'),
        isFalse,
        reason: 'Should not have double-painted characters',
      );
    });

    test('simple text rendering matches expected output', () {
      const widget = Text('Hello');

      final result = capture.capture(widget);
      final lines = result.toLines();

      expect(lines[0], startsWith('Hello'));
    });

    test('text highlight paints selected foreground and background', () {
      const widget = Text(
        'Selection',
        selection: TextHighlight(
          start: 0,
          end: 5,
          foregroundColor: Color.black,
          backgroundColor: Color.red,
        ),
      );

      final result = capture.capture(widget);

      expect(result, BufferMatchers.hasCharAt(0, 0, 'S'));
      for (var x = 0; x < 5; x++) {
        expect(result, BufferMatchers.hasColorAt(x, 0, Color.black));
        expect(result, BufferMatchers.hasBackgroundAt(x, 0, Color.red));
      }
      expect(result, BufferMatchers.hasCharAt(5, 0, 't'));
      expect(result, BufferMatchers.hasBackgroundAt(5, 0, Color.black));
    });

    test('nested Row/Column renders correctly without artifacts', () {
      const widget = Column(
        children: [
          Row(children: [Text('A'), Text('B')]),
          Row(children: [Text('C'), Text('D')]),
        ],
      );

      final result = capture.capture(widget);
      final lines = result.toLines();

      expect(lines[0], startsWith('AB'), reason: 'First row should be AB');
      expect(lines[1], startsWith('CD'), reason: 'Second row should be CD');
    });

    test('tight terminal constraints center default Row and Column', () {
      final terminalCapture = BufferCapture(
        width: 20,
        height: 5,
        layoutConstraints: const BoxConstraints.tight(width: 20, height: 5),
      );
      try {
        final row = terminalCapture.capture(
          const Row(children: [Text('Left'), Text('Middle'), Text('Right')]),
        );

        expect(row, BufferMatchers.hasCharAt(0, 0, ' '));
        expect(row, BufferMatchers.hasCharAt(0, 2, 'L'));
        expect(row, BufferMatchers.hasCharAt(4, 2, 'M'));
        expect(row, BufferMatchers.hasCharAt(10, 2, 'R'));

        final column = terminalCapture.capture(
          const Column(
            children: [Text('Line 1'), Text('Line 2'), Text('Line 3')],
          ),
        );

        expect(column, BufferMatchers.hasCharAt(0, 0, ' '));
        expect(column, BufferMatchers.hasCharAt(7, 0, 'L'));
        expect(column, BufferMatchers.hasCharAt(7, 1, 'L'));
        expect(column, BufferMatchers.hasCharAt(7, 2, 'L'));
      } finally {
        terminalCapture.dispose();
      }
    });
  });
}
