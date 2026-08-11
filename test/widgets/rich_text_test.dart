import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  test('Text.rich delegates span text into RenderParagraph', () {
    final capture = BufferCapture(width: 12, height: 1);
    addTearDown(capture.dispose);

    final captured = capture.capture(
      const Text.rich(
        TextSpan(
          text: 'Hello',
          children: <InlineSpan>[TextSpan(text: ' world')],
        ),
      ),
    );

    expect(captured.getRegion(0, 0, 12, 1), 'Hello world ');
  });

  test('RichText renders plain text from a span tree', () {
    final capture = BufferCapture(width: 12, height: 1);
    addTearDown(capture.dispose);

    final captured = capture.capture(
      const RichText(
        text: TextSpan(
          text: 'A',
          children: <InlineSpan>[TextSpan(text: 'B')],
        ),
      ),
    );

    expect(captured.getRegion(0, 0, 4, 1), 'AB  ');
  });

  test('RichText paints child span styles independently', () {
    final capture = BufferCapture(width: 4, height: 1);
    addTearDown(capture.dispose);

    final captured = capture.capture(
      const RichText(
        text: TextSpan(
          text: 'A',
          style: TextStyle(color: Color.red),
          children: <InlineSpan>[
            TextSpan(
              text: 'B',
              style: TextStyle(color: Color.green, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );

    expect(captured.getChar(0, 0), 'A');
    expect(captured.getChar(1, 0), 'B');
    expect(captured.getForegroundColor(0, 0), Color.red);
    expect(captured.getForegroundColor(1, 0), Color.green);
    expect(captured.getCell(1, 0).isBold, isTrue);
  });
}
