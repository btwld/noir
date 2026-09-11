import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/key_driver.dart';
import '../helpers/tui_test_app.dart';

void main() {
  group('render-tree pointer hit testing', () {
    test('zero-size PointerListener does not receive clicks', () async {
      final hits = <MouseEvent>[];
      final driver = KeyDriver(
        SizedBox(
          width: 0,
          height: 0,
          child: PointerListener(
            onPointerDown: hits.add,
            child: const SizedBox(width: 1, height: 1),
          ),
        ),
        paintFrames: true,
      );
      await driver.ready();

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 0,
          y: 0,
        ),
      );

      expect(hits, isEmpty);
      driver.dispose();
    });

    test('PointerListener receives local coordinates', () async {
      final hits = <MouseEvent>[];
      final driver = KeyDriver(
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 1),
          child: PointerListener(
            onPointerDown: hits.add,
            child: const SizedBox(width: 4, height: 2),
          ),
        ),
        paintFrames: true,
      );
      await driver.ready();

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 3,
          y: 2,
        ),
      );

      expect(hits, hasLength(1));
      expect(hits.single.x, 3);
      expect(hits.single.y, 2);
      expect(hits.single.localPosition, const Offset(1, 1));
      driver.dispose();
    });

    test('localized scroll preserves payload and modifiers', () async {
      final hits = <MouseEvent>[];
      final scroll = MouseScroll(
        direction: MouseScrollDirection.left,
        magnitude: 3,
      );
      final driver = KeyDriver(
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 1),
          child: PointerListener(
            onPointerScroll: hits.add,
            child: const SizedBox(width: 4, height: 2),
          ),
        ),
        paintFrames: true,
      );
      await driver.ready();

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.scroll,
          button: MouseButton.right,
          x: 3,
          y: 2,
          modifiers: KeyModifiers.shift | KeyModifiers.alt,
          scroll: scroll,
        ),
      );

      expect(hits, hasLength(1));
      expect(hits.single.localPosition, const Offset(1, 1));
      expect(hits.single.button, MouseButton.right);
      expect(hits.single.modifiers, KeyModifiers.shift | KeyModifiers.alt);
      expect(hits.single.scroll, same(scroll));
      driver.dispose();
    });

    test('overlapping targets route to the last-painted child', () async {
      final hits = <String>[];
      final driver = KeyDriver(
        _Overlay(
          children: [
            PointerListener(
              onPointerDown: (_) => hits.add('bottom'),
              child: const SizedBox(width: 4, height: 2),
            ),
            PointerListener(
              onPointerDown: (_) => hits.add('top'),
              child: const SizedBox(width: 4, height: 2),
            ),
          ],
        ),
        paintFrames: true,
      );
      await driver.ready();

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 1,
          y: 1,
        ),
      );

      expect(hits, ['top']);
      driver.dispose();
    });

    test('consumed child event stops ancestor pointer dispatch', () async {
      final hits = <String>[];
      final driver = KeyDriver(
        PointerListener(
          onPointerDown: (_) => hits.add('parent'),
          child: PointerListener(
            onPointerDown: (event) {
              hits.add('child');
              event.consume();
            },
            child: const SizedBox(width: 4, height: 2),
          ),
        ),
        paintFrames: true,
      );
      await driver.ready();

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 1,
          y: 1,
        ),
      );

      expect(hits, ['child']);
      driver.dispose();
    });

    test(
      'mockMouse SGR bytes route through PointerRouter to topmost target',
      () {
        final hits = <String>[];
        final app = createTuiTestApp(
          _Overlay(
            children: [
              PointerListener(
                onPointerDown: (_) => hits.add('bottom'),
                child: const SizedBox(width: 4, height: 2),
              ),
              PointerListener(
                onPointerDown: (_) => hits.add('top'),
                child: const SizedBox(width: 4, height: 2),
              ),
            ],
          ),
          width: 8,
          height: 3,
        );

        try {
          app.pumpFrame();
          app.mockMouse.pressDown(1, 1);
          expect(hits, ['top']);
        } finally {
          app.dispose();
        }
      },
    );
  });
}

class _Overlay extends MultiChildRenderObjectWidget {
  const _Overlay({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOverlay();
}

class _RenderOverlay extends RenderBox {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    final w = constraints.constrainWidth(4);
    final h = constraints.constrainHeight(2);
    size = Size(w, h);
    for (final child in children.cast<RenderBox>()) {
      child.performBoxLayout(BoxConstraints.tight(width: w, height: h));
      positionChild(child, 0, 0);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = offset + Offset(x, y);
    for (final child in children.cast<RenderBox>()) {
      context.paintChild(child, origin);
    }
  }
}
