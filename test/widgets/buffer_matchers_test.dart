import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  group('BufferMatchers in widget rendering', () {
    late BufferCapture capture;

    setUpAll(() {
      capture = BufferCapture(width: 30, height: 5);
    });

    tearDownAll(() {
      capture.dispose();
    });

    test(
      'Select highlighted row paints visible glyphs and bg differs from row 1',
      () {
        const widget = Select<String>(
          height: 3,
          selectedTextColor: Color.yellow,
          options: [
            SelectOption(name: 'A', value: 'a'),
            SelectOption(name: 'B', value: 'b'),
          ],
        );
        final captured = capture.capture(widget);
        // Glyph rendered at (0, 0) is the 'A' label.
        expect(captured, BufferMatchers.hasCharAt(0, 0, 'A'));
        // The highlighted row's background should differ from the unselected row.
        final bg0 = captured.getBackgroundColor(0, 0);
        final bg1 = captured.getBackgroundColor(0, 1);
        expect(
          bg0,
          isNot(equals(bg1)),
          reason: 'highlighted row background should differ from unselected',
        );
      },
    );

    test('TextInput placeholder is rendered at half intensity vs value', () {
      const placeholderWidget = TextInput(placeholder: 'hi');
      const valueWidget = TextInput(value: 'hi');
      final placeholder = capture.capture(placeholderWidget);
      final value = capture.capture(valueWidget);
      final phFg = placeholder.getForegroundColor(0, 0);
      final vFg = value.getForegroundColor(0, 0);
      // Placeholder uses half-intensity color: each channel should be lower.
      expect(phFg.r < vFg.r, isTrue, reason: 'placeholder.r < value.r');
      expect(phFg.g < vFg.g, isTrue, reason: 'placeholder.g < value.g');
      expect(phFg.b < vFg.b, isTrue, reason: 'placeholder.b < value.b');
    });

    test('non-focused TextInput captures cursor as hidden', () {
      const widget = TextInput(value: 'hello');
      final captured = capture.capture(widget);
      expect(captured.cursor.visible, isFalse);
    });
  });
}
