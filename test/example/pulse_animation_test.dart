import 'package:test/test.dart';

import '../../example/pulse_animation.dart';
import '../helpers/tui_test_app.dart';

void main() {
  test('pulse demo visibly advances from scheduler frame timestamps', () {
    final app = createTuiTestApp(
      const PulseAnimationDemo(),
      width: 56,
      height: 18,
    );

    try {
      app.pumpFrame();
      final initial = app.captureFrame().toText();

      app.pumpFrame(const Duration(milliseconds: 350));
      final advanced = app.captureFrame().toText();

      expect(initial, contains('AnimationController demo'));
      expect(initial, contains('controller.value: 0.00'));
      expect(advanced, contains('controller.value: 0.50'));
      expect(advanced, isNot(initial));
    } finally {
      app.dispose();
    }
  });
}
