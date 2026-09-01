import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  test('TextInput paints an extended grapheme cluster whole', () {
    final capture = BufferCapture(width: 12, height: 1);
    addTearDown(capture.dispose);

    final frame = capture.capture(
      const TextInput(value: 'a\u{1F468}\u200D\u{1F469}\u200D\u{1F467}b'),
    );

    expect(
      frame.toLines().first.trimRight(),
      'a\u{1F468}\u200D\u{1F469}\u200D\u{1F467}b',
    );
  });
}
