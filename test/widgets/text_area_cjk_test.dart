import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  group('TextArea CJK cell width', () {
    test('CJK characters paint into their wide cells', () {
      final capture = BufferCapture(width: 10, height: 2);
      try {
        final captured = capture.capture(
          const TextArea(height: 1, width: 10, value: '中文'),
        );
        // Each ideograph takes 2 cells. The first cell holds the glyph;
        // the second cell is the wide overhang (terminal renders the
        // glyph spanning both cells). drawText encodes the cluster and
        // its overhang, so the next glyph starts two cells later.
        expect(captured.getChar(0, 0), '中');
        expect(captured.getChar(2, 0), '文');
      } finally {
        capture.dispose();
      }
    });
  });
}
