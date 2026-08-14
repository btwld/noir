import 'package:test/test.dart';

import '../../example/pulse_animation.dart';
import '../helpers/tui_test_app.dart';

void main() {
  test('pulse demo reaches its endpoint and reverses', () {
    final app = createTuiTestApp(
      const PulseAnimationDemo(),
      width: 56,
      height: 18,
    );

    try {
      app.pumpFrame();
      final initial = app.captureFrame().toText();

      app.pumpFrame(const Duration(milliseconds: 350));
      final midpoint = app.captureFrame().toText();

      app.pumpFrame(const Duration(milliseconds: 700));
      final endpoint = app.captureFrame().toText();

      // Completion starts the reverse ticker. Its next frame establishes a
      // fresh time origin, and the following 350 ms frame proves movement.
      app
        ..pumpFrame(const Duration(milliseconds: 1050))
        ..pumpFrame(const Duration(milliseconds: 1400));
      final reversing = app.captureFrame().toText();

      expect(initial, contains('AnimationController demo'));
      expect(initial, contains('controller.value: 0.00'));
      expect(midpoint, contains('controller.value: 0.50'));
      expect(endpoint, contains('controller.value: 1.00'));
      expect(reversing, contains('controller.value: 0.50'));
      expect(midpoint, isNot(initial));
      expect(endpoint, isNot(midpoint));
      expect(reversing, isNot(endpoint));
    } finally {
      app.dispose();
    }
  });
}
