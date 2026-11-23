import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/tui_test_app.dart';

void main() {
  test('a resize that restores the last laid-out size still repaints', () {
    final app = createTuiTestApp(const Text('ready'), width: 10, height: 1);
    addTearDown(app.dispose);
    app.pumpFrame();
    expect(app.captureFrame().toText(), contains('ready'));

    // Two resizes before the next frame. The renderer dropped its frame both
    // times, while the tree ends at the size it was last laid out at, so
    // nothing in it is dirty.
    app
      ..resize(5, 1)
      ..resize(10, 1)
      ..pumpFrame(const Duration(milliseconds: 16));

    expect(app.captureFrame().toText(), contains('ready'));
  });
}
