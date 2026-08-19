import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';

void main() {
  group('Badge', () {
    late BufferCapture capture;

    setUpAll(() {
      capture = BufferCapture(width: 14, height: 1);
    });

    tearDownAll(() {
      capture.dispose();
    });

    test('the label sits between one padding cell on each side', () {
      final frame = capture.capture(const Badge(label: 'NEW'));
      expect(frame.toText(), startsWith(' NEW '));
      expect(frame.getCell(1, 0).isBold, isTrue);
    });

    test('each variant maps to its theme status token', () {
      const theme = ThemeData(
        success: Color.green,
        warning: Color.yellow,
        danger: Color.red,
        info: Color.blue,
        textMuted: Color.magenta,
      );
      const expected = {
        BadgeVariant.neutral: Color.magenta,
        BadgeVariant.success: Color.green,
        BadgeVariant.warning: Color.yellow,
        BadgeVariant.danger: Color.red,
        BadgeVariant.info: Color.blue,
      };

      for (final entry in expected.entries) {
        final frame = capture.capture(
          Theme(
            data: theme,
            child: Badge(label: 'X', variant: entry.key),
          ),
        );
        expect(
          frame,
          BufferMatchers.hasBackgroundAt(0, 0, entry.value),
          reason: '${entry.key}',
        );
      }
    });

    test('an explicit color overrides the variant', () {
      final frame = capture.capture(
        const Badge(
          label: 'X',
          variant: BadgeVariant.danger,
          color: Color.cyan,
        ),
      );
      expect(frame, BufferMatchers.hasBackgroundAt(0, 0, Color.cyan));
    });

    test('a badge never takes focus', () async {
      final focusNode = FocusNode();
      final driver = KeyDriver(
        Focus(
          focusNode: focusNode,
          autofocus: true,
          child: const Badge(label: 'X'),
        ),
      );
      await driver.ready();

      // The only focusable node in the tree is the explicit wrapper, so the
      // badge contributed none of its own.
      expect(focusNode.hasFocus, isTrue);
      driver.dispose();
      focusNode.dispose();
    });
  });
}
