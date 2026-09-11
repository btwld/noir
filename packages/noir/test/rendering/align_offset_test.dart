import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  group('Align painting offsets', () {
    late BufferCapture capture;

    setUp(() {
      capture = BufferCapture(width: 40, height: 10);
    });

    tearDown(() {
      capture.dispose();
    });

    test('Align inside Row with leading spacer paints at correct position', () {
      // This test verifies that Align accounts for its own position when painting.
      // The SizedBox creates a 10-char spacer, so the aligned text should
      // appear at column 10 or later, not at column 0.
      const widget = Row(
        children: [
          SizedBox(width: 10), // Leading spacer
          SizedBox(
            width: 20,
            height: 5,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Aligned'),
            ),
          ),
        ],
      );

      final result = capture.capture(widget);
      final lines = result.toLines();

      // Find where "Aligned" appears - should be after the spacer (column >= 10)
      var foundAtCorrectPosition = false;
      for (final line in lines) {
        final index = line.indexOf('Aligned');
        if (index != -1) {
          expect(
            index,
            greaterThanOrEqualTo(10),
            reason:
                'Aligned text should appear after the 10-char spacer, found at column $index',
          );
          foundAtCorrectPosition = true;
          break;
        }
      }
      expect(
        foundAtCorrectPosition,
        isTrue,
        reason: 'Should find "Aligned" text in output',
      );
    });

    test('Nested Align with offsets renders correctly', () {
      // Verify nested Align widgets accumulate offsets correctly
      const widget = Container(
        width: 30,
        height: 8,
        child: Row(
          children: [
            SizedBox(width: 5), // 5-char spacer
            SizedBox(width: 20, height: 6, child: Align(child: Text('Center'))),
          ],
        ),
      );

      final result = capture.capture(widget);
      final lines = result.toLines();

      // "Center" should appear somewhere after column 5
      var found = false;
      for (final line in lines) {
        final index = line.indexOf('Center');
        if (index != -1) {
          expect(
            index,
            greaterThanOrEqualTo(5),
            reason: 'Center text should be after 5-char spacer',
          );
          found = true;
          break;
        }
      }
      expect(found, isTrue, reason: 'Should find "Center" text in output');
    });

    test('center positions a natural child within tight bounds', () {
      final frame = capture.capture(
        const SizedBox(width: 7, height: 3, child: Align(child: Text('C'))),
      );

      expect(frame.findText('C').single, const BufferPosition(3, 1));
    });

    test('centerLeft vertically centers a natural child', () {
      final frame = capture.capture(
        const SizedBox(
          width: 7,
          height: 3,
          child: Align(alignment: Alignment.centerLeft, child: Text('L')),
        ),
      );

      expect(frame.findText('L').single, const BufferPosition(0, 1));
    });

    test('bottomRight positions a natural child at both trailing edges', () {
      final frame = capture.capture(
        const SizedBox(
          width: 7,
          height: 3,
          child: Align(alignment: Alignment.bottomRight, child: Text('R')),
        ),
      );

      expect(frame.findText('R').single, const BufferPosition(6, 2));
    });
  });
}
