import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';

Column _column(int n) =>
    Column(children: List<Widget>.generate(n, (i) => Text('Item $i')));

Widget _wideText() => const Text('01234567890123456789', softWrap: false);

MouseEvent _wheel(
  MouseScrollDirection direction, {
  int magnitude = 1,
  int modifiers = 0,
  int x = 0,
  int y = 0,
}) => MouseEvent(
  type: MouseEventType.scroll,
  button: MouseButton.left,
  x: x,
  y: y,
  modifiers: modifiers,
  scroll: MouseScroll(direction: direction, magnitude: magnitude),
);

void main() {
  group('ScrollBox flex constraints', () {
    test('vertical ScrollBox surfaces the Expanded height diagnostic', () {
      final capture = BufferCapture(width: 10, height: 4);
      addTearDown(capture.dispose);

      expect(
        () => capture.capture(
          const ScrollBox(
            child: Column(children: [Expanded(child: Text('expanded'))]),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('height constraints are unbounded'),
          ),
        ),
      );
    });

    test('horizontal ScrollBox surfaces the Expanded width diagnostic', () {
      final capture = BufferCapture(width: 10, height: 4);
      addTearDown(capture.dispose);

      expect(
        () => capture.capture(
          const ScrollBox(
            scrollDirection: Axis.horizontal,
            child: Row(children: [Expanded(child: Text('expanded'))]),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('width constraints are unbounded'),
          ),
        ),
      );
    });

    test('loose min flex shrink-wraps and publishes scroll extent', () {
      final controller = ScrollController();
      final capture = BufferCapture(width: 10, height: 2);
      addTearDown(capture.dispose);

      capture.capture(
        ScrollBox(
          controller: controller,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: SizedBox(height: 3)),
              Flexible(flex: 9, child: SizedBox(height: 3)),
            ],
          ),
        ),
      );

      expect(controller.viewportExtent, 2);
      expect(controller.maxScrollExtent, 4);
    });

    test('cross-axis flex remains bounded inside ScrollBox', () {
      final capture = BufferCapture(width: 10, height: 2);
      addTearDown(capture.dispose);

      expect(
        () => capture.capture(
          const ScrollBox(
            child: Row(
              children: [
                Expanded(child: Text('left')),
                Expanded(child: Text('right')),
              ],
            ),
          ),
        ),
        returnsNormally,
      );
    });
  });

  group('ScrollBox viewport-driven scrolling', () {
    test('vertical wheel applies direction and positive magnitude', () async {
      final controller = ScrollController(initialOffset: 5);
      final driver = KeyDriver(
        SizedBox(
          width: 14,
          height: 4,
          child: ScrollBox(
            autofocus: true,
            controller: controller,
            child: _column(20),
          ),
        ),
        paintFrames: true,
      );
      await driver.ready();

      final up = _wheel(MouseScrollDirection.up, magnitude: 3);
      await driver.sendMouse(up);
      expect(controller.offset, 2);
      expect(up.isConsumed, isTrue);

      final down = _wheel(MouseScrollDirection.down, magnitude: 3);
      await driver.sendMouse(down);
      expect(controller.offset, 5);
      expect(down.isConsumed, isTrue);
      driver.dispose();
    });

    test('vertical ScrollBox ignores horizontal wheel directions', () async {
      final controller = ScrollController(initialOffset: 5);
      final driver = KeyDriver(
        SizedBox(
          width: 14,
          height: 4,
          child: ScrollBox(controller: controller, child: _column(20)),
        ),
        paintFrames: true,
      );
      await driver.ready();

      for (final direction in [
        MouseScrollDirection.left,
        MouseScrollDirection.right,
      ]) {
        final event = _wheel(direction);
        await driver.sendMouse(event);
        expect(controller.offset, 5);
        expect(event.isConsumed, isFalse);
      }
      driver.dispose();
    });

    test(
      'horizontal wheel applies direction and ignores vertical input',
      () async {
        final controller = ScrollController(initialOffset: 5);
        final driver = KeyDriver(
          SizedBox(
            width: 4,
            height: 2,
            child: ScrollBox(
              controller: controller,
              scrollDirection: Axis.horizontal,
              showScrollbar: false,
              child: _wideText(),
            ),
          ),
          paintFrames: true,
        );
        await driver.ready();

        final left = _wheel(MouseScrollDirection.left, magnitude: 3);
        await driver.sendMouse(left);
        expect(controller.offset, 2);
        expect(left.isConsumed, isTrue);

        final right = _wheel(MouseScrollDirection.right, magnitude: 3);
        await driver.sendMouse(right);
        expect(controller.offset, 5);
        expect(right.isConsumed, isTrue);

        for (final direction in [
          MouseScrollDirection.up,
          MouseScrollDirection.down,
        ]) {
          final event = _wheel(direction);
          await driver.sendMouse(event);
          expect(controller.offset, 5);
          expect(event.isConsumed, isFalse);
        }
        driver.dispose();
      },
    );

    test('Shift rotates raw wheel direction before axis matching', () async {
      final vertical = ScrollController(initialOffset: 5);
      final verticalDriver = KeyDriver(
        SizedBox(
          width: 14,
          height: 4,
          child: ScrollBox(controller: vertical, child: _column(20)),
        ),
        paintFrames: true,
      );
      await verticalDriver.ready();

      await verticalDriver.sendMouse(
        _wheel(
          MouseScrollDirection.left,
          magnitude: 2,
          modifiers: KeyModifiers.shift,
        ),
      );
      expect(vertical.offset, 3);
      final verticalMismatch = _wheel(
        MouseScrollDirection.up,
        modifiers: KeyModifiers.shift,
      );
      await verticalDriver.sendMouse(verticalMismatch);
      expect(vertical.offset, 3);
      expect(verticalMismatch.isConsumed, isFalse);
      verticalDriver.dispose();

      final horizontal = ScrollController(initialOffset: 5);
      final horizontalDriver = KeyDriver(
        SizedBox(
          width: 4,
          height: 2,
          child: ScrollBox(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            showScrollbar: false,
            child: _wideText(),
          ),
        ),
        paintFrames: true,
      );
      await horizontalDriver.ready();

      await horizontalDriver.sendMouse(
        _wheel(
          MouseScrollDirection.up,
          magnitude: 2,
          modifiers: KeyModifiers.shift,
        ),
      );
      expect(horizontal.offset, 3);
      final horizontalMismatch = _wheel(
        MouseScrollDirection.left,
        modifiers: KeyModifiers.shift,
      );
      await horizontalDriver.sendMouse(horizontalMismatch);
      expect(horizontal.offset, 3);
      expect(horizontalMismatch.isConsumed, isFalse);
      horizontalDriver.dispose();
    });

    test('mouse wheel outside the ScrollBox does not scroll', () async {
      final controller = ScrollController();
      final driver = KeyDriver(
        SizedBox(
          width: 14,
          height: 4,
          child: ScrollBox(controller: controller, child: _column(20)),
        ),
        paintFrames: true,
      );
      await driver.ready();

      final event = _wheel(MouseScrollDirection.down, x: 20, y: 20);
      await driver.sendMouse(event);

      expect(controller.offset, 0);
      expect(event.isConsumed, isFalse);
      driver.dispose();
    });

    test(
      'mouse wheel inside an offset ScrollBox uses local hit testing',
      () async {
        final controller = ScrollController();
        final driver = KeyDriver(
          Padding(
            padding: const EdgeInsets.only(left: 3, top: 2),
            child: SizedBox(
              width: 14,
              height: 4,
              child: ScrollBox(controller: controller, child: _column(20)),
            ),
          ),
          paintFrames: true,
        );
        await driver.ready();

        await driver.sendMouse(_wheel(MouseScrollDirection.down, x: 3, y: 2));

        expect(controller.offset, 1);
        driver.dispose();
      },
    );

    test('clamped input bubbles but changed input stops an ancestor', () async {
      final controller = ScrollController();
      final ancestorEvents = <MouseEvent>[];
      final driver = KeyDriver(
        PointerListener(
          onPointerScroll: ancestorEvents.add,
          child: SizedBox(
            width: 14,
            height: 4,
            child: ScrollBox(controller: controller, child: _column(20)),
          ),
        ),
        paintFrames: true,
      );
      await driver.ready();

      final atStart = _wheel(MouseScrollDirection.up);
      await driver.sendMouse(atStart);
      expect(controller.offset, 0);
      expect(atStart.isConsumed, isFalse);
      expect(ancestorEvents, hasLength(1));

      ancestorEvents.clear();
      final changed = _wheel(MouseScrollDirection.down);
      await driver.sendMouse(changed);
      expect(controller.offset, 1);
      expect(changed.isConsumed, isTrue);
      expect(ancestorEvents, isEmpty);
      driver.dispose();
    });

    test(
      'nested ScrollBoxes move only the first box that can apply input',
      () async {
        final outer = ScrollController(initialOffset: 5);
        final inner = ScrollController(initialOffset: 1);
        final driver = KeyDriver(
          SizedBox(
            width: 14,
            height: 6,
            child: ScrollBox(
              controller: outer,
              showScrollbar: false,
              child: Column(
                children: [
                  ...List<Widget>.generate(5, (index) => Text('Lead $index')),
                  SizedBox(
                    width: 14,
                    height: 4,
                    child: ScrollBox(
                      controller: inner,
                      showScrollbar: false,
                      child: _column(20),
                    ),
                  ),
                  ...List<Widget>.generate(20, (index) => Text('Outer $index')),
                ],
              ),
            ),
          ),
          paintFrames: true,
        );
        await driver.ready();

        final childMoves = _wheel(MouseScrollDirection.down);
        await driver.sendMouse(childMoves);
        expect(inner.offset, 2);
        expect(outer.offset, 5);
        expect(childMoves.isConsumed, isTrue);

        inner.jumpTo(0);
        final ancestorMoves = _wheel(MouseScrollDirection.up);
        await driver.sendMouse(ancestorMoves);
        expect(inner.offset, 0);
        expect(outer.offset, 4);
        expect(ancestorMoves.isConsumed, isTrue);
        driver.dispose();
      },
    );

    test('callbacks fire once only when a wheel changes the offset', () async {
      final controller = ScrollController(initialOffset: 2);
      var listenerCalls = 0;
      final callbackOffsets = <double>[];
      controller.addListener(() => listenerCalls++);
      final driver = KeyDriver(
        SizedBox(
          width: 14,
          height: 4,
          child: ScrollBox(
            controller: controller,
            onScroll: callbackOffsets.add,
            child: _column(20),
          ),
        ),
        paintFrames: true,
      );
      await driver.ready();
      listenerCalls = 0;
      callbackOffsets.clear();

      await driver.sendMouse(_wheel(MouseScrollDirection.down, magnitude: 3));
      expect(controller.offset, 5);
      expect(listenerCalls, 1);
      expect(callbackOffsets, [5]);

      await driver.sendMouse(_wheel(MouseScrollDirection.left));
      expect(listenerCalls, 1);
      expect(callbackOffsets, [5]);

      controller.jumpTo(controller.maxScrollExtent);
      listenerCalls = 0;
      callbackOffsets.clear();
      final atEnd = _wheel(MouseScrollDirection.down, magnitude: 3);
      await driver.sendMouse(atEnd);
      expect(listenerCalls, 0);
      expect(callbackOffsets, isEmpty);
      expect(atEnd.isConsumed, isFalse);
      driver.dispose();
    });

    test('PageDown advances by viewport height (not a const)', () async {
      final controller = ScrollController();
      final driver = KeyDriver(
        SizedBox(
          width: 14,
          height: 3,
          child: ScrollBox(
            autofocus: true,
            controller: controller,
            child: _column(50),
          ),
        ),
        paintFrames: true,
      );
      await driver.ready();
      // viewport height = 3 (no scrollbar takes one row only horizontally).
      // After PageDown, we expect offset = 3.
      await driver.sendLogicalKey(LogicalKeyboardKey.pageDown);
      expect(controller.offset, 3);
      await driver.sendLogicalKey(LogicalKeyboardKey.pageDown);
      expect(controller.offset, 6);
      driver.dispose();
    });

    test('clicking past content does nothing', () async {
      // ScrollBox itself has no row-click handler. This test asserts the
      // pointer down is not consumed and the scroll offset stays unchanged.
      final controller = ScrollController();
      final driver = KeyDriver(
        SizedBox(
          width: 14,
          height: 3,
          child: ScrollBox(controller: controller, child: _column(50)),
        ),
        paintFrames: true,
      );
      await driver.ready();
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 50, // way past the box's width
          y: 50, // way past the box's height
        ),
      );
      expect(controller.offset, 0);
      driver.dispose();
    });
  });
}
