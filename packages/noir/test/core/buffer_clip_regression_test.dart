import 'dart:typed_data';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  test('a nested view intersects rather than widening its parent clip', () {
    final renderer = Renderer.create(5, 1, testing: true);
    addTearDown(renderer.dispose);
    final buffer = renderer.nextBuffer..clear(Color.black);
    buffer
        .clipped(clipX: 1, clipY: 0, clipWidth: 1, clipHeight: 1)
        .clipped(clipX: 0, clipY: 0, clipWidth: 5, clipHeight: 1)
        .drawText('abcde', 0, 0, Color.white);

    expect(CapturedBuffer.fromBuffer(buffer).toText(), ' b   ');
  });

  for (final defaults in [false, true]) {
    test('clipped blit preserves source offsets (defaults=$defaults)', () {
      final target = Renderer.create(5, 2, testing: true);
      final source = Renderer.create(5, 2, testing: true);
      addTearDown(target.dispose);
      addTearDown(source.dispose);
      final buffer = target.nextBuffer..clear(Color.black);
      final sourceBuffer = source.nextBuffer
        ..clear(Color.black)
        ..drawText('abcde', 0, 0, Color.white)
        ..drawText('ABCDE', 0, 1, Color.white);
      buffer
          .clipped(clipX: 1, clipY: 0, clipWidth: 2, clipHeight: 1)
          .drawFrameBuffer(
            sourceBuffer,
            1,
            1,
            defaults ? 0 : 4,
            defaults ? 0 : 1,
            0,
            0,
          );

      expect(CapturedBuffer.fromBuffer(buffer).toText(), ' CD  \n     ');
    });
  }

  test('clipped blit keeps argument and lifecycle guards when out of view', () {
    final target = Renderer.create(5, 1, testing: true);
    final source = Renderer.create(5, 1, testing: true);
    addTearDown(target.dispose);
    addTearDown(source.dispose);
    final view = target.nextBuffer.clipped(
      clipX: 20,
      clipY: 20,
      clipWidth: 1,
      clipHeight: 1,
    );
    final sourceBuffer = source.nextBuffer;

    expect(
      () => view.drawFrameBuffer(sourceBuffer, -1, 0, 1, 1, 0, 0),
      throwsRangeError,
    );
    source.dispose();
    expect(
      () => view.drawFrameBuffer(sourceBuffer, 0, 0, 1, 1, 0, 0),
      throwsStateError,
    );
  });

  test('a clipped image draw combines its view and explicit clip', () {
    final renderer = Renderer.create(3, 1, testing: true);
    addTearDown(renderer.dispose);
    final image = TerminalImage.fromRgba(
      Uint8List.fromList([255, 0, 0, 255]),
      pixelWidth: 1,
      pixelHeight: 1,
      rowStride: 4,
    );
    addTearDown(image.dispose);
    final buffer = renderer.nextBuffer..clear(Color.black);
    buffer
        .clipped(clipX: 1, clipY: 0, clipWidth: 1, clipHeight: 1)
        .drawImage(
          image,
          x: 0,
          y: 0,
          width: 3,
          height: 1,
          clipX: 0,
          clipY: 0,
          clipWidth: 3,
          clipHeight: 1,
        );
    renderer.render(force: true, autoFlush: false);

    final result = CapturedBuffer.fromBuffer(renderer.debugCurrentBuffer);
    expect(result, BufferMatchers.hasBackgroundAt(0, 0, Color.black));
    expect(result, BufferMatchers.hasBackgroundAt(1, 0, Color.red));
    expect(result, BufferMatchers.hasBackgroundAt(2, 0, Color.black));
  });
}
