import 'dart:typed_data';

import 'package:noir/noir.dart';

void main() => runTuiApp(const ImageDemo());

class ImageDemo extends StatelessWidget {
  const ImageDemo({super.key});

  static final Uint8List _checkerboard = Uint8List.fromList(<int>[
    255,
    80,
    80,
    255,
    255,
    200,
    40,
    255,
    255,
    200,
    40,
    255,
    255,
    80,
    80,
    255,
  ]);

  @override
  Widget build(BuildContext context) => Container(
    color: Color.black,
    padding: const EdgeInsets.all(1),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 1,
      children: [
        const Text(
          'Embedded RGBA image',
          style: TextStyle(color: Color.yellow, fontWeight: FontWeight.bold),
        ),
        Image.rgba(
          _checkerboard,
          pixelWidth: 2,
          pixelHeight: 2,
          rowStride: 8,
          width: 12,
          height: 6,
          fit: ImageFit.fill,
        ),
        const Text('Ctrl+C exits.', style: TextStyle(color: Color.lightGray)),
      ],
    ),
  );
}
