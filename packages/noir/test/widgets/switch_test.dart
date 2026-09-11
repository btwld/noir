import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';

void main() {
  group('Switch', () {
    test('Space and Enter both request the opposite value', () async {
      final changes = <bool>[];
      final driver = KeyDriver(
        Switch(autofocus: true, value: false, onChanged: changes.add),
      );
      await driver.ready();

      await driver.sendLogicalKey(LogicalKeyboardKey.space, code: 32);
      await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
      expect(changes, [true, true]);
      driver.dispose();
    });

    test('a left click flips it', () async {
      final changes = <bool>[];
      final driver = KeyDriver(
        Switch(value: true, onChanged: changes.add),
        paintFrames: true,
      );
      await driver.ready();

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 0,
          y: 0,
        ),
      );
      expect(changes, [false]);
      driver.dispose();
    });

    test('a null onChanged refuses focus', () async {
      final focusNode = FocusNode();
      final driver = KeyDriver(
        Switch(focusNode: focusNode, autofocus: true, value: true),
      );
      await driver.ready();

      expect(focusNode.hasFocus, isFalse);
      driver.dispose();
      focusNode.dispose();
    });

    test('the glyph reports the value', () {
      final capture = BufferCapture(width: 12, height: 1);
      try {
        expect(
          capture.capture(const Switch(value: false, label: 'x')).toText(),
          startsWith('○ x'),
        );
        expect(
          capture.capture(const Switch(value: true, label: 'x')).toText(),
          startsWith('● x'),
        );
      } finally {
        capture.dispose();
      }
    });

    test('the on circle takes its color from the theme success token', () {
      final capture = BufferCapture(width: 12, height: 1);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(success: Color.magenta),
            child: Switch(value: true, onChanged: (_) {}),
          ),
        );
        expect(frame, BufferMatchers.hasColorAt(0, 0, Color.magenta));
      } finally {
        capture.dispose();
      }
    });
  });
}
