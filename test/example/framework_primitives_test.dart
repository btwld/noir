import 'dart:io' as io;

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/framework_primitives.dart';
import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';

void main() {
  test('renders notifier state with a styled child span', () async {
    final app = createTuiTestApp(
      FrameworkPrimitivesApp(onQuit: () {}),
      width: 64,
      height: 14,
    );
    try {
      await _settle(app);
      final frame = app.captureFrame();
      expect(frame, BufferMatchers.containsText('Framework primitives'));
      expect(frame, BufferMatchers.containsText('Count: 0'));
      expect(frame, BufferMatchers.containsText('Last activation: none'));

      final count = frame.findText('Count: 0').single;
      final digitX = count.x + 'Count: '.length;
      expect(frame.getForegroundColor(digitX, count.y), Color.yellow);
      expect(frame.getCell(digitX, count.y).isBold, isTrue);
    } finally {
      app.dispose();
    }
  });

  test('Enter, Space, pointer, and q share observable app state', () async {
    var quits = 0;
    final app = createTuiTestApp(
      FrameworkPrimitivesApp(onQuit: () => quits++),
      width: 64,
      height: 14,
    );
    try {
      await _settle(app);

      app.mockInput.pressEnter();
      await _settle(app);
      expect(app.captureFrame().toText(), contains('Count: 1'));
      expect(
        app.captureFrame().toText(),
        contains('Last activation: keyboard'),
      );

      app.mockInput.typeText(' ');
      await _settle(app);
      expect(app.captureFrame().toText(), contains('Count: 2'));

      final activate = app.captureFrame().findText('Activate').single;
      expect(activate.x, greaterThan(0));
      expect(activate.y, greaterThan(0));
      app.mockMouse.click(activate.x, activate.y);
      await _settle(app);

      final pointerFrame = app.captureFrame().toText();
      expect(pointerFrame, contains('Count: 3'));
      expect(pointerFrame, contains('Last activation: pointer local 0,0'));

      app.mockInput.typeText('q');
      await Future<void>.delayed(Duration.zero);
      expect(quits, 1);
    } finally {
      app.dispose();
    }
  });

  test('real entrypoint enables basic mouse reporting', () {
    final source = io.File(
      'example/framework_primitives.dart',
    ).readAsStringSync();
    expect(RegExp(r'app\.enableMouse\(\);').allMatches(source), hasLength(1));
    expect(source, isNot(contains('enableMouse(enableMovement: true)')));
  });
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
