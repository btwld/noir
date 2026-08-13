import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';

void main() {
  final renderer = Renderer.create(12, 3, testing: true);
  try {
    final buffer = renderer.nextBuffer
      ..clear(Color.black)
      ..drawText('Noir', 1, 1, Color.white);
    final chars = buffer.getDirectAccess().chars;
    final captured = String.fromCharCodes(chars.skip(13).take(4));
    if (captured != 'Noir') {
      throw StateError('unexpected captured frame: $captured');
    }
    renderer.render(force: true);
  } finally {
    renderer.dispose();
  }
}
