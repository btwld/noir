// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

void main() {
  group('FFI smoke', () {
    test('create/render/dispose', () {
      final renderer = Renderer.create(80, 24, testing: true);
      addTearDown(renderer.dispose);

      renderer.setBackgroundColor(Color.rgb(0.05, 0.05, 0.1));
      renderer.clearTerminal();

      final buf = renderer.nextBuffer;
      buf.clear(Color.rgb(0.05, 0.05, 0.1));
      buf.drawText('Hello, OpenTUI!', 2, 2, Color.yellow);
      buf.fillRect(1, 4, 10, 1, Color.red);

      renderer.render(force: true);
    });
  });
}
