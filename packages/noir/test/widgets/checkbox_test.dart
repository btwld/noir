import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';

void main() {
  group('Checkbox', () {
    test('Space requests the opposite value', () async {
      final changes = <bool>[];
      final driver = KeyDriver(
        Checkbox(autofocus: true, value: false, onChanged: changes.add),
      );
      await driver.ready();

      await driver.sendLogicalKey(LogicalKeyboardKey.space, code: 32);
      expect(changes, [true]);
      driver.dispose();
    });

    test('Enter requests the opposite value', () async {
      final changes = <bool>[];
      final driver = KeyDriver(
        Checkbox(autofocus: true, value: true, onChanged: changes.add),
      );
      await driver.ready();

      await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
      expect(changes, [false]);
      driver.dispose();
    });

    test('a left click toggles it', () async {
      final changes = <bool>[];
      final driver = KeyDriver(
        Checkbox(value: false, label: 'wrap', onChanged: changes.add),
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
      expect(changes, [true]);
      driver.dispose();
    });

    test('a null onChanged refuses focus and ignores every gesture', () async {
      final focusNode = FocusNode();
      final driver = KeyDriver(
        Checkbox(focusNode: focusNode, autofocus: true, value: false),
        paintFrames: true,
      );
      await driver.ready();

      expect(focusNode.hasFocus, isFalse);
      await driver.sendLogicalKey(LogicalKeyboardKey.space, code: 32);
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 0,
          y: 0,
        ),
      );
      expect(focusNode.hasFocus, isFalse);
      driver.dispose();
      focusNode.dispose();
    });

    test('the glyph and label report the value', () {
      final capture = BufferCapture(width: 12, height: 1);
      try {
        expect(
          capture.capture(const Checkbox(value: false, label: 'on')).toText(),
          startsWith('□ on'),
        );
        expect(
          capture.capture(const Checkbox(value: true, label: 'on')).toText(),
          startsWith('■ on'),
        );
      } finally {
        capture.dispose();
      }
    });

    test('a disabled checkbox is muted', () {
      final capture = BufferCapture(width: 12, height: 1);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(textMuted: Color.red),
            child: const Checkbox(value: true, label: 'x'),
          ),
        );
        expect(frame, BufferMatchers.hasColorAt(0, 0, Color.red));
      } finally {
        capture.dispose();
      }
    });

    test('the checked glyph takes its color from the theme accent', () {
      final capture = BufferCapture(width: 12, height: 1);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(accent: Color.magenta),
            child: Checkbox(value: true, onChanged: (_) {}),
          ),
        );
        expect(frame, BufferMatchers.hasColorAt(0, 0, Color.magenta));
      } finally {
        capture.dispose();
      }
    });
  });
}
