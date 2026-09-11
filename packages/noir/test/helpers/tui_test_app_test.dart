import 'package:noir/noir.dart';
import 'package:test/test.dart';

import 'buffer_capture.dart';
import 'tui_test_app.dart';

void main() {
  test('createTuiTestApp pumps and captures a rendered frame', () {
    final app = createTuiTestApp(const Text('hello'), width: 12, height: 3);

    try {
      app.pumpFrame();
      final captured = app.captureFrame();

      expect(captured.width, 12);
      expect(captured.height, 3);
      expect(captured, BufferMatchers.hasCharAt(0, 0, 'h'));
      expect(captured, BufferMatchers.hasCharAt(4, 0, 'o'));
    } finally {
      app.dispose();
    }
  });

  test('createTuiTestApp resizes through the binding', () {
    final app = createTuiTestApp(const Text('wide'), width: 8, height: 2);

    try {
      app
        ..resize(16, 4)
        ..pumpFrame();

      final captured = app.captureFrame();
      expect(captured.width, 16);
      expect(captured.height, 4);
      expect(captured, BufferMatchers.hasCharAt(0, 0, 'w'));
    } finally {
      app.dispose();
    }
  });

  test('createTuiTestApp dispose is idempotent', () {
    final app = createTuiTestApp(const Text('bye'));

    app
      ..dispose()
      ..dispose();
  });

  group('parser-roundtrip', () {
    test('mockInput typeText sends UTF-8 bytes through StdinInputDriver', () {
      final app = createTuiTestApp(const Text('input'));
      final keys = <KeyEvent>[];
      final sub = app.binding.inputManager.onKey(keys.add);

      try {
        app.mockInput.typeText('a🙂');

        expect(keys.map((event) => event.character), ['a', '🙂']);
      } finally {
        sub.cancel();
        app.dispose();
      }
    });

    test('mockInput emits control, arrow, Kitty CSI-u, and paste bytes', () {
      final app = createTuiTestApp(const Text('input'), kittyKeyboard: true);
      final keys = <KeyEvent>[];
      final pastes = <PasteEvent>[];
      final keySub = app.binding.inputManager.onKey(keys.add);
      final pasteSub = app.binding.inputManager.onPaste(pastes.add);

      try {
        app.mockInput.pressCtrl('c');
        app.mockInput.pressArrow(ArrowDirection.down);
        app.mockInput.pressKittyKey(
          'x'.codeUnitAt(0),
          modifiers:
              KeyModifiers.super_ |
              KeyModifiers.hyper |
              KeyModifiers.capsLock |
              KeyModifiers.numLock,
        );
        app.mockInput.paste('hello\nworld');

        expect(keys[0].logicalKey, LogicalKeyboardKey.keyC);
        expect(keys[0].character, isNull);
        expect(keys[0].modifiers & KeyModifiers.ctrl, isNonZero);
        expect(keys[1].logicalKey, LogicalKeyboardKey.arrowDown);
        expect(keys[2].logicalKey, LogicalKeyboardKey.keyX);
        expect(keys[2].character, 'x');
        expect(keys[2].modifiers & KeyModifiers.super_, isNonZero);
        expect(keys[2].modifiers & KeyModifiers.hyper, isNonZero);
        expect(keys[2].modifiers & KeyModifiers.capsLock, isNonZero);
        expect(keys[2].modifiers & KeyModifiers.numLock, isNonZero);
        expect(pastes.single.text, 'hello\nworld');
      } finally {
        keySub.cancel();
        pasteSub.cancel();
        app.dispose();
      }
    });

    test(
      'mockMouse emits SGR click, drag, and four-direction scroll bytes',
      () {
        final app = createTuiTestApp(const Text('mouse'));
        final events = <MouseEvent>[];
        final sub = app.binding.inputManager.onMouse(events.add);

        try {
          app.mockMouse.click(10, 5);
          app.mockMouse.drag(1, 2, 3, 4);
          for (final direction in ScrollDirection.values) {
            app.mockMouse.scroll(6, 7, direction);
          }

          expect(events[0].type, MouseEventType.down);
          expect(events[0].x, 10);
          expect(events[0].y, 5);
          expect(events[1].type, MouseEventType.up);
          expect(events[2].type, MouseEventType.down);
          expect(events[3].type, MouseEventType.move);
          expect(events[4].type, MouseEventType.up);
          expect(
            events.skip(5).map((event) => event.scroll?.direction),
            MouseScrollDirection.values,
          );
          expect(events.skip(5).map((event) => event.scroll?.magnitude), [
            1,
            1,
            1,
            1,
          ]);
          expect(events.skip(5).map((event) => event.button), [
            MouseButton.left,
            MouseButton.middle,
            MouseButton.right,
            MouseButton.left,
          ]);
        } finally {
          sub.cancel();
          app.dispose();
        }
      },
    );

    test('mockMouse preserves named modifier flags and raw direction', () {
      final app = createTuiTestApp(const Text('mouse'));
      final events = <MouseEvent>[];
      final sub = app.binding.inputManager.onMouse(events.add);

      try {
        app.mockMouse.scroll(
          0,
          0,
          ScrollDirection.left,
          shift: true,
          alt: true,
          control: true,
        );
        app.mockMouse.scroll(
          0,
          0,
          ScrollDirection.right,
          alt: true,
          control: true,
        );

        expect(events[0].scroll?.direction, MouseScrollDirection.left);
        expect(
          events[0].modifiers &
              (KeyModifiers.shift | KeyModifiers.alt | KeyModifiers.ctrl),
          KeyModifiers.shift | KeyModifiers.alt | KeyModifiers.ctrl,
        );
        expect(events[1].scroll?.direction, MouseScrollDirection.right);
        expect(
          events[1].modifiers & (KeyModifiers.alt | KeyModifiers.ctrl),
          KeyModifiers.alt | KeyModifiers.ctrl,
        );
        expect(events[1].modifiers & KeyModifiers.shift, 0);
      } finally {
        sub.cancel();
        app.dispose();
      }
    });

    test(
      'shifted parser input rotates at vertical and horizontal ScrollBox',
      () {
        final vertical = ScrollController(initialOffset: 2);
        final verticalApp = createTuiTestApp(
          SizedBox(
            width: 10,
            height: 3,
            child: ScrollBox(
              controller: vertical,
              showScrollbar: false,
              child: Column(
                children: List<Widget>.generate(10, (index) => Text('$index')),
              ),
            ),
          ),
          width: 10,
          height: 3,
        );

        try {
          verticalApp.pumpFrame();
          verticalApp.mockMouse.scroll(0, 0, ScrollDirection.left, shift: true);
          expect(vertical.offset, 1);
          verticalApp.mockMouse.scroll(
            0,
            0,
            ScrollDirection.right,
            shift: true,
          );
          expect(vertical.offset, 2);
        } finally {
          verticalApp.dispose();
        }

        final horizontal = ScrollController(initialOffset: 2);
        final horizontalApp = createTuiTestApp(
          SizedBox(
            width: 4,
            height: 1,
            child: ScrollBox(
              controller: horizontal,
              scrollDirection: Axis.horizontal,
              showScrollbar: false,
              child: const Text('0123456789', softWrap: false),
            ),
          ),
          width: 4,
          height: 1,
        );

        try {
          horizontalApp.pumpFrame();
          horizontalApp.mockMouse.scroll(0, 0, ScrollDirection.up, shift: true);
          expect(horizontal.offset, 1);
          horizontalApp.mockMouse.scroll(
            0,
            0,
            ScrollDirection.down,
            shift: true,
          );
          expect(horizontal.offset, 2);
        } finally {
          horizontalApp.dispose();
        }
      },
    );
  });
}
