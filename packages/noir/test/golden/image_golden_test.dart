import 'dart:io';
import 'dart:typed_data';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('Image Golden', () {
    late GoldenTester tester;
    late TerminalImage image;

    setUpAll(() {
      tester = GoldenTester(width: 6, height: 3);
      image = TerminalImage.fromRgba(
        Uint8List.fromList(<int>[
          255,
          0,
          0,
          255,
          0,
          255,
          0,
          255,
          0,
          0,
          255,
          255,
          255,
          255,
          0,
          255,
        ]),
        pixelWidth: 2,
        pixelHeight: 2,
        rowStride: 8,
      );
    });

    tearDownAll(() {
      tester.dispose();
      image.dispose();
    });

    test('block fallback captures cells, styles, and cursor', () async {
      await tester.expectGolden(
        Image(
          image: image,
          width: 4,
          height: 2,
          fit: ImageFit.fill,
          protocol: ImageProtocol.blocks,
        ),
        'image_block_fallback',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
