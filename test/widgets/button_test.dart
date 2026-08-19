import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';

void main() {
  group('Button', () {
    test('Space, Enter, and a left click each fire onPressed once', () async {
      var presses = 0;
      final driver = KeyDriver(
        Button(autofocus: true, label: 'Run', onPressed: () => presses++),
        paintFrames: true,
      );
      await driver.ready();

      await driver.sendLogicalKey(LogicalKeyboardKey.space, code: 32);
      expect(presses, 1);
      await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
      expect(presses, 2);
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 1,
          y: 0,
        ),
      );
      expect(presses, 3);
      driver.dispose();
    });

    test('a null onPressed refuses focus and ignores keys', () async {
      final focusNode = FocusNode();
      final driver = KeyDriver(
        Button(focusNode: focusNode, autofocus: true, label: 'Run'),
      );
      await driver.ready();

      expect(focusNode.hasFocus, isFalse);
      await driver.sendLogicalKey(LogicalKeyboardKey.space, code: 32);
      expect(focusNode.hasFocus, isFalse);
      driver.dispose();
      focusNode.dispose();
    });

    test('a right click does not activate', () async {
      var presses = 0;
      final driver = KeyDriver(
        Button(label: 'Run', onPressed: () => presses++),
        paintFrames: true,
      );
      await driver.ready();

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.right,
          x: 1,
          y: 0,
        ),
      );
      expect(presses, 0);
      driver.dispose();
    });

    test('padding surrounds the label with the fill color', () {
      final capture = BufferCapture(width: 10, height: 1);
      try {
        final frame = capture.capture(
          Button(label: 'Go', color: Color.blue, onPressed: () {}),
        );
        expect(frame.toText().trim(), startsWith('Go'));
        expect(frame, BufferMatchers.hasBackgroundAt(0, 0, Color.blue));
        expect(frame, BufferMatchers.hasBackgroundAt(3, 0, Color.blue));
      } finally {
        capture.dispose();
      }
    });

    test('an enabled button takes its fill from the theme accent', () {
      final capture = BufferCapture(width: 10, height: 1);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(accent: Color.magenta),
            child: Button(label: 'Go', onPressed: () {}),
          ),
        );
        expect(frame, BufferMatchers.hasBackgroundAt(0, 0, Color.magenta));
      } finally {
        capture.dispose();
      }
    });
  });
}
