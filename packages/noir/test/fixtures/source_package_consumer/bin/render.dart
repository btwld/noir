import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';

void main() {
  final renderer = Renderer.create(12, 3, testing: true);
  try {
    final buffer = renderer.nextBuffer
      ..clear(Color.black)
      ..drawText('Noir', 1, 1, Color.white);
    final access = buffer.getDirectAccess();
    final captured = String.fromCharCodes(
      List<int>.generate(4, (index) => access.getEncodedCellAt(13 + index)),
    );
    if (captured != 'Noir') {
      throw StateError('unexpected captured frame: $captured');
    }
    renderer.render(force: true);
  } finally {
    renderer.dispose();
  }
}
