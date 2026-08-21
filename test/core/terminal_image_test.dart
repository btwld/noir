import 'dart:io';
import 'dart:typed_data';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/core/buffer.dart';
import 'package:test/test.dart';

void main() {
  test('raw RGBA validates dimensions and stride before native allocation', () {
    final pixels = Uint8List(4);

    expect(
      () => TerminalImage.fromRgba(
        pixels,
        pixelWidth: 0,
        pixelHeight: 1,
        rowStride: 4,
      ),
      throwsArgumentError,
    );
    expect(
      () => TerminalImage.fromRgba(
        pixels,
        pixelWidth: 1,
        pixelHeight: 1,
        rowStride: 3,
      ),
      throwsArgumentError,
    );
  });

  test('empty encoded image data is rejected before native allocation', () {
    expect(() => TerminalImage.decode(Uint8List(0)), throwsArgumentError);
  });

  test('image exceptions expose stable typed status codes', () {
    final error = TerminalImageException.fromStatus(2);

    expect(error.code, TerminalImageErrorCode.unsupportedFormat);
    expect(error.status, 2);
    expect(error.toString(), contains('unsupported image format'));
  });

  test('decoded images publish immutable info and dispose idempotently', () {
    final image = TerminalImage.fromRgba(
      Uint8List.fromList(<int>[255, 0, 0, 255]),
      pixelWidth: 1,
      pixelHeight: 1,
      rowStride: 4,
    );

    expect(image.info.pixelWidth, 1);
    expect(image.info.pixelHeight, 1);
    expect(image.info.format, ImageFormat.rawRgba);
    expect(image.info.hasAlpha, isFalse);

    image.dispose();
    image.dispose();

    expect(() => image.info, throwsStateError);
  });

  test('bundled library decodes every promised encoded format', () {
    const fixtures = <String, ImageFormat>{
      'rgba.png': ImageFormat.png,
      'baseline.jpg': ImageFormat.jpeg,
      'lossless.webp': ImageFormat.webp,
      'first-frame.gif': ImageFormat.gif,
    };

    for (final entry in fixtures.entries) {
      final image = TerminalImage.decode(
        File(
          'external/opentui/packages/core/src/tests/fixtures/images/${entry.key}',
        ).readAsBytesSync(),
      );
      expect(image.info.format, entry.value, reason: entry.key);
      expect(image.info.pixelWidth, greaterThan(0), reason: entry.key);
      expect(image.info.pixelHeight, greaterThan(0), reason: entry.key);
      image.dispose();
    }
  });

  test('bundled block protocol materializes an RGBA image into cells', () {
    final image = TerminalImage.fromRgba(
      Uint8List.fromList(<int>[255, 0, 0, 255, 0, 255, 0, 255]),
      pixelWidth: 2,
      pixelHeight: 1,
      rowStride: 8,
    );
    final renderer = Renderer.create(2, 1, testing: true);
    try {
      final buffer = renderer.nextBuffer;
      expect(
        buffer.drawImage(
          image,
          x: 0,
          y: 0,
          width: 2,
          height: 1,
          protocol: ImageProtocol.blocks,
        ),
        isTrue,
      );
      renderer.render(force: true, autoFlush: false);
      expect(
        debugResolveBufferCharacters(renderer.debugCurrentBuffer),
        isNotEmpty,
      );
    } finally {
      renderer.dispose();
      image.dispose();
    }
  });
}
