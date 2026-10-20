import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  group('paragraph line alignment', () {
    late BufferCapture capture;

    setUp(() {
      capture = BufferCapture(width: 20, height: 4);
    });

    tearDown(() {
      capture.dispose();
    });

    test('wrapped center aligns each line inside the box', () {
      // Width 10 wraps "1234567 abcd" into "1234567 " (8) and "abcd" (4).
      // Slack 2 and 6 are both even, so centering is not the odd-cell rule.
      final rendered = capture.capture(
        const SizedBox(
          width: 10,
          child: Text('1234567 abcd', textAlign: TextAlign.center),
        ),
      );

      expect(rendered.getRegion(0, 0, 10, 2), ' 1234567  \n   abcd   ');
    });

    test('wrapped right aligns each line to the box edge', () {
      final rendered = capture.capture(
        const SizedBox(
          width: 10,
          child: Text('1234567 abcd', textAlign: TextAlign.right),
        ),
      );

      expect(rendered.getRegion(0, 0, 10, 2), '  1234567 \n      abcd');
    });

    test('center gives an odd leftover cell to the leading side', () {
      // Slack is 3. Truncating ~/ 2 starts the text at column 1;
      // ((slack) / 2).round() starts it at column 2.
      final rendered = capture.capture(
        const SizedBox(
          width: 5,
          child: Text('AB', textAlign: TextAlign.center),
        ),
      );

      expect(rendered.getRegion(0, 0, 5, 1), '  AB ');
    });

    test('a line wider than the box keeps a centered or trailing window', () {
      final centered = capture.capture(
        const Row(
          children: [
            SizedBox(width: 2, child: Text('ZZ')),
            SizedBox(
              width: 5,
              child: Text(
                'ABCDEFGH',
                softWrap: false,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
      expect(centered.getRegion(0, 0, 7, 1), 'ZZCDEFG');

      final trailing = capture.capture(
        const Row(
          children: [
            SizedBox(width: 2, child: Text('ZZ')),
            SizedBox(
              width: 4,
              child: Text(
                'ABCDEFGH',
                softWrap: false,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
      expect(trailing.getRegion(0, 0, 6, 1), 'ZZEFGH');
    });
  });
}
