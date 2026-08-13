import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/counter.dart';
import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';

void main() {
  test('counter renders every available keyboard control', () async {
    final app = createTuiTestApp(const CounterApp(), width: 64, height: 12);

    try {
      await _settleAutofocus();
      final frame = _render(app);
      final text = frame.toText();
      expect(text, contains('Up/+ increment'));
      expect(text, contains('Down/- decrement'));
      expect(text, contains('Ctrl+C exit'));
      expect(
        frame.getForegroundColor(0, 0),
        isNot(Color.black),
        reason: 'the counter border must remain visible on its dark surface',
      );
    } finally {
      app.dispose();
    }
  });

  test(
    'counter changes only from parsed increment and decrement keys',
    () async {
      final app = createTuiTestApp(const CounterApp(), width: 48, height: 12);

      try {
        await _settleAutofocus();
        await Future<void>.delayed(const Duration(milliseconds: 75));
        expect(_render(app).toText(), contains('Count: 0'));

        app.mockInput.pressArrow(ArrowDirection.up);
        await Future<void>.delayed(Duration.zero);
        expect(_render(app).toText(), contains('Count: 1'));

        app.mockInput.typeText('+');
        await Future<void>.delayed(Duration.zero);
        expect(_render(app).toText(), contains('Count: 2'));

        app.mockInput.pressArrow(ArrowDirection.down);
        await Future<void>.delayed(Duration.zero);
        expect(_render(app).toText(), contains('Count: 1'));

        app.mockInput.typeText('-');
        await Future<void>.delayed(Duration.zero);
        expect(_render(app).toText(), contains('Count: 0'));
      } finally {
        app.dispose();
      }
    },
  );
}

CapturedBuffer _render(TuiTestApp app) {
  app.pumpFrame();
  return app.captureFrame();
}

Future<void> _settleAutofocus() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
