import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  group('ProgressBar', () {
    late BufferCapture capture;

    setUpAll(() {
      capture = BufferCapture(width: 12, height: 1);
    });

    tearDownAll(() {
      capture.dispose();
    });

    String render(double value, {int width = 8}) => capture
        .capture(ProgressBar(value: value, width: width))
        .toText()
        .trim();

    test('an empty bar is all track', () {
      expect(render(0), '░░░░░░░░');
    });

    test('a full bar is all fill', () {
      expect(render(1), '████████');
    });

    test('a half bar splits at the midpoint', () {
      expect(render(0.5), '████░░░░');
    });

    test('a fractional cell uses an eighth-block glyph', () {
      // 8 cells * 0.5625 = 4.5 cells -> four full plus a half block.
      expect(render(0.5625), '████▌░░░');
    });

    test('values outside 0..1 clamp instead of overflowing', () {
      expect(render(-3), '░░░░░░░░');
      expect(render(9), '████████');
      expect(render(double.nan), '░░░░░░░░');
    });

    test('the rendered width always equals the requested width', () {
      for (var step = 0; step <= 40; step++) {
        expect(render(step / 40).length, 8, reason: 'step $step');
      }
    });

    test('a zero-width bar renders nothing', () {
      expect(render(0.5, width: 0), isEmpty);
    });

    test('fill and track take their colors from the theme', () {
      final frame = capture.capture(
        Theme(
          data: ThemeData.dark.copyWith(
            accent: Color.magenta,
            scrollbarTrack: Color.blue,
          ),
          child: const ProgressBar(value: 0.5, width: 4),
        ),
      );
      expect(frame, BufferMatchers.hasColorAt(0, 0, Color.magenta));
      expect(frame, BufferMatchers.hasColorAt(3, 0, Color.blue));
    });
  });
}
