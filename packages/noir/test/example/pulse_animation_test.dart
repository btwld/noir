import 'package:test/test.dart';

import '../../example/pulse_animation.dart';
import '../helpers/tui_test_app.dart';

void main() {
  test('pulse demo advances by fractional cells and reverses', () {
    final app = createTuiTestApp(
      const PulseAnimationDemo(),
      width: 56,
      height: 18,
    );

    try {
      app.pumpFrame();
      final initial = app.captureFrame().toText();

      app.pumpFrame(const Duration(milliseconds: 25));
      final fractional = app.captureFrame().toText();

      app.pumpFrame(const Duration(milliseconds: 800));
      final midpoint = app.captureFrame().toText();

      app.pumpFrame(const Duration(milliseconds: 1600));
      final endpoint = app.captureFrame().toText();

      // Completion starts the reverse ticker. Its next frame establishes a
      // fresh time origin, and the following 800 ms frame proves movement.
      app
        ..pumpFrame(const Duration(milliseconds: 2400))
        ..pumpFrame(const Duration(milliseconds: 3200));
      final reversing = app.captureFrame().toText();

      expect(initial, contains('Terminal-native motion'));
      expect(initial, contains('controller.value: 0.00'));
      expect(initial, contains('░' * 32));
      expect(fractional, contains('▌${'░' * 31}'));
      expect(midpoint, contains('controller.value: 0.50'));
      expect(midpoint, contains('${'█' * 16}${'░' * 16}'));
      expect(endpoint, contains('controller.value: 1.00'));
      expect(endpoint, contains('█' * 32));
      expect(reversing, contains('controller.value: 0.50'));
      expect(reversing, contains('${'█' * 16}${'░' * 16}'));
      expect(fractional, isNot(initial));
      expect(midpoint, isNot(initial));
      expect(endpoint, isNot(midpoint));
      expect(reversing, isNot(endpoint));
    } finally {
      app.dispose();
    }
  });

  test('Space pauses and resumes the pulse without resetting it', () async {
    final app = createTuiTestApp(
      const PulseAnimationDemo(),
      width: 56,
      height: 18,
    );

    try {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      app
        ..pumpFrame()
        ..pumpFrame(const Duration(milliseconds: 400));
      final running = app.captureFrame().toText();
      expect(running, contains('running'));

      app.mockInput.typeText(' ');
      app.pumpFrame(const Duration(milliseconds: 800));
      final paused = app.captureFrame().toText();
      app.pumpFrame(const Duration(milliseconds: 1400));
      final stillPaused = app.captureFrame().toText();

      expect(paused, contains('paused'));
      expect(stillPaused, paused);

      app.mockInput.typeText(' ');
      app
        ..pumpFrame(const Duration(milliseconds: 1416))
        ..pumpFrame(const Duration(milliseconds: 1816));
      final resumed = app.captureFrame().toText();

      expect(resumed, contains('running'));
      expect(resumed, isNot(paused));
      expect(resumed, isNot(running), reason: 'resume does not restart at 0');
    } finally {
      app.dispose();
    }
  });
}
