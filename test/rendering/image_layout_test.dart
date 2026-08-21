import 'dart:typed_data';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

void main() {
  test('natural image size uses nominal one-by-two cell pixels', () {
    final image = _image(width: 8, height: 6);
    final render = RenderImage(image: image, fit: ImageFit.fit);

    render.layout(const BoxConstraints());

    expect(render.size, const Size(8, 3));
    image.dispose();
  });

  test('tight constraints override natural image size', () {
    final image = _image(width: 8, height: 6);
    final render = RenderImage(image: image, fit: ImageFit.cover);

    render.layout(const BoxConstraints.tight(width: 4, height: 2));

    expect(render.size, const Size(4, 2));
    image.dispose();
  });

  test('cover center-crops source pixels for the terminal cell aspect', () {
    final image = _image(width: 8, height: 4);
    final render = RenderImage(image: image, fit: ImageFit.cover)
      ..layout(const BoxConstraints.tight(width: 10, height: 10));
    final canvas = _RecordingCanvas();

    render.paint(
      PaintingContext(
        canvas,
        cellMetrics: const TerminalCellMetrics(columns: 10, rows: 10),
      ),
      Offset.zero,
    );

    expect(canvas.destination, const Rect.fromLTWH(0, 0, 10, 10));
    expect(canvas.source, const Rect.fromLTWH(3, 0, 2, 4));
    expect(canvas.pixelWidth, 0);
    expect(canvas.pixelHeight, 0);
    image.dispose();
  });

  test('measured pixels are passed to fill draws', () {
    final image = _image(width: 8, height: 4);
    final render = RenderImage(image: image, fit: ImageFit.fill)
      ..layout(const BoxConstraints.tight(width: 4, height: 2));
    final canvas = _RecordingCanvas();

    render.paint(
      PaintingContext(
        canvas,
        cellMetrics: const TerminalCellMetrics(
          columns: 4,
          rows: 2,
          pixelWidth: 32,
          pixelHeight: 32,
        ),
      ),
      Offset.zero,
    );

    expect(canvas.pixelWidth, 32);
    expect(canvas.pixelHeight, 32);
    image.dispose();
  });
}

TerminalImage _image({required int width, required int height}) =>
    TerminalImage.fromRgba(
      Uint8List(width * height * 4),
      pixelWidth: width,
      pixelHeight: height,
      rowStride: width * 4,
    );

final class _RecordingCanvas implements TuiCanvas {
  Rect? destination;
  Rect? source;
  int? pixelWidth;
  int? pixelHeight;

  @override
  void drawImage(
    TerminalImage image,
    Rect destination, {
    int pixelWidth = 0,
    int pixelHeight = 0,
    Rect? sourceRect,
    ImageProtocol protocol = ImageProtocol.auto,
  }) {
    this.destination = destination;
    source = sourceRect;
    this.pixelWidth = pixelWidth;
    this.pixelHeight = pixelHeight;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
