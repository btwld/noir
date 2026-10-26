import 'dart:typed_data';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  late TerminalImage image;
  late Renderer renderer;
  setUp(() {
    image = TerminalImage.fromRgba(
      Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 255]),
      pixelWidth: 2,
      pixelHeight: 1,
      rowStride: 8,
    );
    renderer = Renderer.create(2, 1, testing: true)..setAutoFlush(false);
  });
  tearDown(() {
    renderer.dispose();
    image.dispose();
  });

  test('testing renderer materializes the source pixels as colored cells', () {
    final buffer = renderer.nextBuffer..clear(Color.black);
    expect(buffer.drawImage(image, x: 0, y: 0, width: 2, height: 1), isTrue);
    renderer.render(force: true, autoFlush: false);

    final result = CapturedBuffer.fromBuffer(renderer.debugCurrentBuffer);
    expect(result, BufferMatchers.hasCharAt(0, 0, '█'));
    expect(result, BufferMatchers.hasColorAt(0, 0, Color.red));
    expect(result, BufferMatchers.hasBackgroundAt(0, 0, Color.red));
    expect(result, BufferMatchers.hasColorAt(1, 0, Color.green));
    expect(result, BufferMatchers.hasBackgroundAt(1, 0, Color.green));
  });

  test('testing image draws honor the selected source crop', () {
    final buffer = renderer.nextBuffer..clear(Color.black);
    expect(
      buffer.drawImage(
        image,
        x: 0,
        y: 0,
        width: 2,
        height: 1,
        sourceX: 1,
        sourceWidth: 1,
      ),
      isTrue,
    );
    renderer.render(force: true, autoFlush: false);

    final result = CapturedBuffer.fromBuffer(renderer.debugCurrentBuffer);
    for (var x = 0; x < 2; x++) {
      expect(result, BufferMatchers.hasColorAt(x, 0, Color.green));
      expect(result, BufferMatchers.hasBackgroundAt(x, 0, Color.green));
    }
  });

  test('image clipping crops source pixels along with the destination', () {
    final buffer = renderer.nextBuffer..clear(Color.black);
    expect(
      buffer.drawImage(
        image,
        x: 0,
        y: 0,
        width: 2,
        height: 1,
        clipX: 1,
        clipY: 0,
        clipWidth: 1,
        clipHeight: 1,
      ),
      isTrue,
    );
    renderer.render(force: true, autoFlush: false);

    final result = CapturedBuffer.fromBuffer(renderer.debugCurrentBuffer);
    expect(result, BufferMatchers.hasCharAt(0, 0, ' '));
    expect(result, BufferMatchers.hasBackgroundAt(0, 0, Color.black));
    expect(result, BufferMatchers.hasColorAt(1, 0, Color.green));
    expect(result, BufferMatchers.hasBackgroundAt(1, 0, Color.green));
  });

  test('BufferCapture preserves pixels through repeated image captures', () {
    final capture = BufferCapture(width: 2, height: 1);
    addTearDown(capture.dispose);
    for (var frame = 0; frame < 2; frame++) {
      final result = capture.capture(
        Image(image: image, width: 2, height: 1, fit: ImageFit.fill),
      );
      expect(result, BufferMatchers.hasColorAt(0, 0, Color.red));
      expect(result, BufferMatchers.hasColorAt(1, 0, Color.green));
    }
  });
}
