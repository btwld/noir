import 'dart:io' as io;

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/counter.dart';
import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';

final _surface = Color.fromHex('#FAFAFA');
final _materialBlue = Color.fromHex('#1976D2');
final _mutedText = Color.fromHex('#616161');

void main() {
  test('counter renders the Flutter-style visual hierarchy', () async {
    final app = createTuiTestApp(const CounterApp(), width: 64, height: 18);

    try {
      await _settle(app);
      final frame = app.captureFrame();
      final title = frame.findText('Noir Counter').single;
      final firstLine = frame.findText('You have pushed the button').single;
      final secondLine = frame.findText('this many times:').single;
      final count = frame.findText('0').single;
      final hint = frame.findText('Up/+ add').single;
      final increment = _incrementGlyph(frame);

      expect(
        frame,
        BufferMatchers.containsText(
          'Up/+ add | Down/- subtract | Enter/Space | Ctrl+C',
        ),
      );

      expect(title.x, 2);
      expect(title.y, 1);
      expect(frame.getForegroundColor(title.x, title.y), Color.white);
      expect(frame.getBackgroundColor(title.x, title.y), _materialBlue);
      expect(frame.getCell(title.x, title.y).isBold, isTrue);
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < frame.width; x++) {
          expect(
            frame.getBackgroundColor(x, y),
            _materialBlue,
            reason: 'app-bar cell ($x, $y) must use one flat blue surface',
          );
        }
      }
      expect(frame.getChar(0, 2), ' ');
      expect(frame.getBackgroundColor(0, 3), _surface);

      expect(
        firstLine.x,
        (frame.width - 'You have pushed the button'.length) ~/ 2,
      );
      expect(secondLine.x, (frame.width - 'this many times:'.length) ~/ 2);
      expect(count.x, frame.width ~/ 2);
      expect(count.y, greaterThan(secondLine.y));
      expect(frame.getForegroundColor(count.x, count.y), _materialBlue);
      expect(frame.getCell(count.x, count.y).isBold, isTrue);

      expect(hint.y, greaterThan(count.y));
      expect(frame.getForegroundColor(hint.x, hint.y), _mutedText);
      final actionLeft = increment.x - 3;
      final actionTop = increment.y - 1;
      expect(actionLeft, frame.width - 9);
      expect(actionTop, frame.height - 4);
      expect(frame.getForegroundColor(increment.x, increment.y), Color.white);
      expect(frame.getBackgroundColor(increment.x, increment.y), _materialBlue);
      expect(frame.getCell(increment.x, increment.y).isBold, isTrue);
      for (var y = actionTop; y < actionTop + 3; y++) {
        for (var x = actionLeft; x < actionLeft + 7; x++) {
          expect(
            frame.getBackgroundColor(x, y),
            _materialBlue,
            reason: 'action cell ($x, $y) must be part of the solid surface',
          );
        }
      }
      final actionRegion = frame.getRegion(actionLeft, actionTop, 7, 3);
      for (final borderGlyph in ['╭', '╮', '╰', '╯', '─', '│']) {
        expect(actionRegion, isNot(contains(borderGlyph)));
      }
      expect(frame.getBackgroundColor(0, frame.height - 1), _surface);
    } finally {
      app.dispose();
    }
  });

  test(
    'counter handles every parsed keyboard control and ignores releases',
    () async {
      final app = createTuiTestApp(const CounterApp(), width: 64, height: 18);

      try {
        await _settle(app);
        _expectCount(app, 0);

        app.mockInput.pressArrow(ArrowDirection.up);
        await _settle(app);
        _expectCount(app, 1);

        app.mockInput.typeText('+');
        await _settle(app);
        _expectCount(app, 2);

        app.mockInput.pressEnter();
        await _settle(app);
        _expectCount(app, 3);

        app.mockInput.typeText(' ');
        await _settle(app);
        _expectCount(app, 4);

        app.mockInput.pressArrow(ArrowDirection.down);
        await _settle(app);
        _expectCount(app, 3);

        app.mockInput.typeText('-');
        await _settle(app);
        _expectCount(app, 2);

        app.mockInput.typeText('x');
        app.mockInput.pressKittyKey(43, eventType: 3);
        await _settle(app);
        _expectCount(app, 2);
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'counter increments only on left-button down inside the action',
    () async {
      final app = createTuiTestApp(const CounterApp(), width: 64, height: 18);

      try {
        await _settle(app);
        final increment = _incrementGlyph(app.captureFrame());
        final actionLeft = increment.x - 3;
        final actionTop = increment.y - 1;

        app.mockMouse.pressDown(actionLeft, actionTop);
        await _settle(app);
        _expectCount(app, 1);

        app.mockMouse.release(actionLeft, actionTop);
        await _settle(app);
        _expectCount(app, 1);

        app.mockMouse.click(
          increment.x,
          increment.y,
          button: MouseButton.right,
        );
        app.mockMouse.click(
          increment.x,
          increment.y,
          button: MouseButton.middle,
        );
        await _settle(app);
        _expectCount(app, 1);
      } finally {
        app.dispose();
      }
    },
  );

  test('real counter entrypoint enables basic mouse reporting once', () {
    final source = io.File('example/counter.dart').readAsStringSync();

    expect(RegExp(r'app\.enableMouse\(\);').allMatches(source), hasLength(1));
    expect(source, isNot(contains('enableMouse(enableMovement: true)')));
    expect(source, contains('registerHotReloadExtension(app);'));
  });

  test('counter keeps its primary hierarchy at compact dimensions', () async {
    final app = createTuiTestApp(const CounterApp(), width: 32, height: 12);

    try {
      await _settle(app);
      final frame = app.captureFrame();

      expect(frame, BufferMatchers.containsText('Noir Counter'));
      expect(frame, BufferMatchers.containsText('this many times:'));
      expect(frame.findText('0'), hasLength(1));
      expect(_incrementGlyph(frame).x, greaterThan(frame.width ~/ 2));
    } finally {
      app.dispose();
    }
  });
}

BufferPosition _incrementGlyph(CapturedBuffer frame) => frame
    .findText('+')
    .where((position) => position.x > frame.width ~/ 2)
    .reduce((left, right) => left.x > right.x ? left : right);

void _expectCount(TuiTestApp app, int expected) {
  final frame = app.captureFrame();
  final position = frame.findText('$expected').single;
  expect(position.x, closeTo(frame.width / 2, 1));
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
