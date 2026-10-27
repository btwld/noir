import 'dart:typed_data';

import 'package:noir/noir.dart';
import 'package:noir/src/app/driver.dart';
import 'package:test/test.dart';

void main() {
  test('drive cell capture publishes source-correct block image colors', () {
    final image = TerminalImage.fromRgba(
      Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 255]),
      pixelWidth: 2,
      pixelHeight: 1,
      rowStride: 8,
    );
    addTearDown(image.dispose);
    final host = DriverHost.create(width: 4, height: 2);
    addTearDown(host.dispose);
    host.binding
      ..runApp(
        Image(
          image: image,
          width: 4,
          height: 2,
          fit: ImageFit.fill,
          protocol: ImageProtocol.kitty,
        ),
      )
      ..debugFlushFrame();

    final capture = host.capture(format: DriverCaptureFormat.cells);
    expect(capture['lines'], ['████', '████']);
    final rows = (capture['rows']! as List<Object?>)
        .cast<Map<String, Object?>>();
    for (final row in rows) {
      for (final channel in ['fg', 'bg']) {
        expect(row[channel], [
          '#ff0000ff',
          '#ff0000ff',
          '#00ff00ff',
          '#00ff00ff',
        ]);
      }
    }
  });
}
