import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  group('Spinner', () {
    test('advances one frame per interval and wraps around', () {
      final owner = BuildOwner();
      owner.setFrameCallback(() {});
      final element = const Spinner(
        interval: Duration(milliseconds: 100),
        frames: SpinnerFrames.line,
      ).createElement();
      element.mount(null, owner);

      String frame() => (element.children.single.widget as Text).data!;

      expect(frame(), SpinnerFrames.line[0]);

      // The controller spans the frame-index range, so one interval of elapsed
      // time is exactly one frame.
      owner.handleBeginFrame(Duration.zero);
      owner.handleBeginFrame(const Duration(milliseconds: 100));
      owner.buildScope();
      expect(frame(), SpinnerFrames.line[1]);

      owner.handleBeginFrame(const Duration(milliseconds: 250));
      owner.buildScope();
      expect(frame(), SpinnerFrames.line[2]);

      // Completing the last frame restarts the run rather than sticking.
      owner.handleBeginFrame(const Duration(milliseconds: 400));
      owner.buildScope();
      owner.handleBeginFrame(const Duration(milliseconds: 401));
      owner.buildScope();
      expect(frame(), SpinnerFrames.line[0]);

      element.unmount();
    });

    test('the ticker is released on unmount', () {
      final owner = BuildOwner();
      owner.setFrameCallback(() {});
      final element = const Spinner().createElement();
      element.mount(null, owner);
      owner.handleBeginFrame(Duration.zero);

      element.unmount();

      // A frame after unmount must not drive a disposed controller.
      expect(
        () => owner.handleBeginFrame(const Duration(milliseconds: 100)),
        returnsNormally,
      );
    });

    test('the glyph takes its color from the theme accent', () {
      final capture = BufferCapture(width: 4, height: 1);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(accent: Color.magenta),
            child: const Spinner(),
          ),
        );
        expect(frame, BufferMatchers.hasColorAt(0, 0, Color.magenta));
        expect(frame.toText(), startsWith(SpinnerFrames.dots.first));
      } finally {
        capture.dispose();
      }
    });
  });
}
