import 'dart:io' as io;

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/hooks_counter.dart';
import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';

final _accent = Color.fromHex('#7DD3FC');

void main() {
  test('hooks counter renders a focused, terminal-native hierarchy', () async {
    final app = createTuiTestApp(const HooksCounterApp());

    try {
      await _settle(app);
      final frame = app.captureFrame();
      final title = frame.findText('Hooks counter').single;
      final count = frame.findText('0').single;
      final action = frame.findText('+ Add one').single;

      expect(
        frame,
        BufferMatchers.containsText(
          'Enter / Space / click to add one · Ctrl+C exits',
        ),
      );
      expect(frame, BufferMatchers.containsText('Current count'));
      expect(frame, BufferMatchers.containsText('HOOKS'));

      expect(title, const BufferPosition(2, 1));
      expect(frame.getCell(title.x, title.y).isBold, isTrue);
      expect(count.x, 3);
      expect(count.y, greaterThan(title.y));
      expect(frame.getForegroundColor(count.x, count.y), _accent);
      expect(frame.getCell(count.x, count.y).isBold, isTrue);
      expect(action.x, 3);
      expect(action.y, greaterThan(count.y));
      expect(frame.getBackgroundColor(action.x, action.y), _accent);
    } finally {
      app.dispose();
    }
  });

  test('hooks counter increments from the Button input paths', () async {
    final app = createTuiTestApp(const HooksCounterApp());

    try {
      await _settle(app);
      _expectCount(app, 0);

      app.mockInput.pressEnter();
      await _settle(app);
      _expectCount(app, 1);

      app.mockInput.typeText(' ');
      await _settle(app);
      _expectCount(app, 2);

      final action = app.captureFrame().findText('+ Add one').single;
      app.mockMouse.pressDown(action.x, action.y);
      await _settle(app);
      _expectCount(app, 3);
    } finally {
      app.dispose();
    }
  });

  test('hooks counter entrypoint enables basic mouse reporting once', () {
    final source = io.File('example/hooks_counter.dart').readAsStringSync();

    expect(RegExp('enableMouse: true').allMatches(source), hasLength(1));
    expect(source, isNot(contains('enableMouse(enableMovement: true)')));
  });
}

void _expectCount(TuiTestApp app, int expected) {
  expect(app.captureFrame().findText('$expected'), hasLength(1));
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
