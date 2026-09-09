import 'package:test/test.dart';

import '../../example/tutorials/first_app/step_01.dart' as step1;
import '../../example/tutorials/first_app/step_02.dart' as step2;
import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';

/// The first-app tutorial teaches these two files and shows captured frames of
/// them. These checks hold the checkpoints to the labels and the count the
/// lesson promises, at the geometry the published frames use.
void main() {
  test('the first checkpoint counts up from the focused button', () async {
    final app = createTuiTestApp(const step1.CounterApp(), width: 40, height: 6);
    try {
      await _settle(app);
      expect(app.captureFrame(), BufferMatchers.containsText('Count: 0'));
      expect(app.captureFrame(), BufferMatchers.containsText('+ Add one'));

      app.mockInput.typeText(' ');
      await _settle(app);
      expect(app.captureFrame(), BufferMatchers.containsText('Count: 1'));
    } finally {
      app.dispose();
    }
  });

  test('the edited checkpoint changes only the label', () async {
    final app = createTuiTestApp(const step2.CounterApp(), width: 40, height: 6);
    try {
      await _settle(app);
      app.mockInput.typeText(' ');
      await _settle(app);
      final frame = app.captureFrame();
      expect(frame, BufferMatchers.containsText('Total: 1'));
      expect(frame.findText('Count:'), isEmpty);
    } finally {
      app.dispose();
    }
  });
}

Future<void> _settle(TuiTestApp app) async {
  app.pumpFrame();
  await Future<void>.microtask(() {});
  app.pumpFrame();
}
