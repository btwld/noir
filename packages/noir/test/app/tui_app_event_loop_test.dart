import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/tui_test_app.dart';

void main() {
  test('render-tree pointer hits survive input frames that skip paint', () {
    final hits = <MouseEvent>[];
    final paintLog = <String>[];
    final app = createTuiTestApp(
      PointerListener(
        onPointerDown: hits.add,
        child: _PaintProbe(log: paintLog),
      ),
      width: 8,
      height: 2,
    );

    try {
      app.pumpFrame();

      expect(paintLog, ['paint']);

      app.mockMouse.pressDown(0, 0);
      app.pumpFrame();

      expect(hits, hasLength(1));
      expect(paintLog, [
        'paint',
      ], reason: 'The input-scheduled clean frame must not repaint.');

      app.mockMouse.pressDown(0, 0);

      expect(hits, hasLength(2));
    } finally {
      app.dispose();
    }
  });
}

class _PaintProbe extends RenderObjectWidget {
  const _PaintProbe({required this.log});

  final List<String> log;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintProbe(log);
}

class _RenderPaintProbe extends RenderBox {
  _RenderPaintProbe(this.log);

  final List<String> log;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = const Size(2, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    log.add('paint');
  }
}
