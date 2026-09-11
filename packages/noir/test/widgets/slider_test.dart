import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';

void main() {
  test('Slider keyboard emits stepped, page, and boundary values', () async {
    final values = <double>[];
    final driver = KeyDriver(
      Slider(
        value: 5,
        max: 10,
        step: 2,
        viewportSize: 4,
        autofocus: true,
        onChanged: values.add,
      ),
    );
    await driver.ready();

    await driver.sendLogicalKey(LogicalKeyboardKey.arrowRight);
    await driver.sendLogicalKey(LogicalKeyboardKey.pageDown);
    await driver.sendLogicalKey(LogicalKeyboardKey.home);
    await driver.sendLogicalKey(LogicalKeyboardKey.end);

    expect(values, <double>[7, 9, 0, 10]);
    driver.dispose();
  });

  test('Slider pointer maps the local track position to its range', () async {
    final values = <double>[];
    final driver = KeyDriver(
      SizedBox(
        width: 10,
        height: 1,
        child: Slider(value: 0, onChanged: values.add),
      ),
      paintFrames: true,
    );
    await driver.ready();

    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 5,
        y: 0,
      ),
    );

    expect(values.single, closeTo(50, 0.001));
    driver.dispose();
  });

  test('vertical Slider handles drag movement on its local axis', () async {
    final values = <double>[];
    final driver = KeyDriver(
      SizedBox(
        width: 1,
        height: 10,
        child: Slider(value: 0, axis: Axis.vertical, onChanged: values.add),
      ),
      paintFrames: true,
    );
    await driver.ready();

    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 0,
        y: 2,
      ),
    );
    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.move,
        button: MouseButton.left,
        x: 0,
        y: 8,
      ),
    );
    await driver.sendMouse(
      MouseEvent(type: MouseEventType.up, button: MouseButton.left, x: 0, y: 8),
    );

    expect(values.first, closeTo(20, 0.001));
    expect(values.last, closeTo(80, 0.001));
    driver.dispose();
  });

  test('disabled Slider ignores keyboard and pointer input', () async {
    var bubbledRight = 0;
    final driver = KeyDriver(
      Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            bubbledRight++;
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: const SizedBox(width: 10, child: Slider(value: 25)),
      ),
      paintFrames: true,
    );
    await driver.ready();

    await driver.sendLogicalKey(LogicalKeyboardKey.arrowRight);
    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 8,
        y: 0,
      ),
    );

    expect(bubbledRight, 1);
    driver.dispose();
  });

  test('zero-range Slider is disabled and paints a full thumb', () async {
    final values = <double>[];
    final driver = KeyDriver(
      SizedBox(
        width: 5,
        child: Slider(
          value: 5,
          min: 5,
          max: 5,
          autofocus: true,
          onChanged: values.add,
        ),
      ),
      paintFrames: true,
    );
    addTearDown(driver.dispose);
    await driver.ready();

    await driver.sendLogicalKey(LogicalKeyboardKey.arrowRight);
    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 4,
        y: 0,
      ),
    );

    expect(values, isEmpty);

    final capture = BufferCapture(width: 5, height: 1);
    try {
      final frame = capture.capture(Slider(value: 5, min: 5, max: 5));
      for (var x = 0; x < 5; x++) {
        expect(
          frame,
          BufferMatchers.hasBackgroundAt(x, 0, ThemeData.dark.textMuted),
        );
      }
    } finally {
      capture.dispose();
    }
  });

  test('Slider paints a viewport-sized thumb and disabled theme', () {
    final capture = BufferCapture(width: 10, height: 1);
    try {
      final frame = capture.capture(const Slider(value: 50, viewportSize: 20));

      expect(
        frame,
        BufferMatchers.hasBackgroundAt(4, 0, ThemeData.dark.textMuted),
      );
      expect(
        frame,
        BufferMatchers.hasBackgroundAt(0, 0, ThemeData.dark.scrollbarTrack),
      );
    } finally {
      capture.dispose();
    }
  });

  test('thumb ratio includes the viewport in total content size', () {
    final capture = BufferCapture(width: 10, height: 1);
    try {
      final frame = capture.capture(const Slider(value: 0, viewportSize: 100));

      expect(
        frame,
        BufferMatchers.hasBackgroundAt(4, 0, ThemeData.dark.textMuted),
      );
      expect(
        frame,
        BufferMatchers.hasBackgroundAt(5, 0, ThemeData.dark.scrollbarTrack),
      );
    } finally {
      capture.dispose();
    }
  });
}
