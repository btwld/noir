import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';
import '../helpers/tui_test_app.dart';

void main() {
  for (final softWrap in [false, true]) {
    test(
      'CRLF editing keeps source and painted caret aligned ($softWrap)',
      () async {
        final controller = TextEditingController(text: 'ab\r\ncde')
          ..selection = const TextSelection.collapsed(offset: 0);
        final driver = KeyDriver(
          TextArea(
            controller: controller,
            autofocus: true,
            height: 3,
            softWrap: softWrap,
          ),
          width: 6,
          height: 3,
          paintFrames: true,
        );
        addTearDown(controller.dispose);
        addTearDown(driver.dispose);
        await driver.ready();

        Future<void> move(
          LogicalKeyboardKey key,
          int offset,
          int x,
          int y,
        ) async {
          await driver.sendLogicalKey(key);
          driver.app.debugFlushFrame();
          final cursor = driver.app.buildOwner.cursorController;
          expect(controller.selection.extentOffset, offset);
          expect(cursor.isVisible, isTrue);
          expect((cursor.x, cursor.y), (x, y));
        }

        await move(LogicalKeyboardKey.end, 2, 2, 0);
        await driver.sendCharacter('x');
        expect(controller.text, 'abx\r\ncde');
        await move(LogicalKeyboardKey.home, 0, 0, 0);
        await move(LogicalKeyboardKey.arrowDown, 5, 0, 1);
        await move(LogicalKeyboardKey.end, 8, 3, 1);
        await move(LogicalKeyboardKey.arrowUp, 3, 3, 0);
        await move(LogicalKeyboardKey.arrowRight, 5, 0, 1);
        await move(LogicalKeyboardKey.arrowLeft, 3, 3, 0);
        expect(controller.text, 'abx\r\ncde');
      },
    );
  }

  for (final multiline in [false, true]) {
    test(
      'maxLength counts the composed edit (multiline: $multiline)',
      () async {
        final controller = TextEditingController(text: 'a')
          ..selection = const TextSelection.collapsed(offset: 1);
        final changes = <String>[];
        final driver = KeyDriver(
          multiline
              ? TextArea(
                  controller: controller,
                  autofocus: true,
                  maxLength: 1,
                  onChanged: changes.add,
                )
              : TextInput(
                  controller: controller,
                  autofocus: true,
                  maxLength: 1,
                  onChanged: changes.add,
                ),
        );
        addTearDown(controller.dispose);
        addTearDown(driver.dispose);
        await driver.ready();

        await driver.sendCharacter('\u0301');
        expect(controller.text, 'a\u0301');
        expect(changes, ['a\u0301']);

        await driver.sendCharacter('b');
        expect(controller.text, 'a\u0301');
        expect(changes, ['a\u0301']);
      },
    );
  }

  test(
    'one-cell TextInput does not publish its caret over a sibling',
    () async {
      final controller = TextEditingController(text: 'abc')
        ..selection = const TextSelection.collapsed(offset: 3);
      final app = createTuiTestApp(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 1,
              child: TextInput(controller: controller, autofocus: true),
            ),
            const Text('next'),
          ],
        ),
      );
      addTearDown(controller.dispose);
      addTearDown(app.dispose);
      app.pumpFrame();
      await Future<void>.delayed(Duration.zero);
      app.pumpFrame();

      final frame = app.captureFrame();
      expect(frame, BufferMatchers.cursorAt(0, 0));
      expect(frame.getRegion(1, 0, 4, 1), 'next');
    },
  );

  test('zero-width TextInput publishes no caret', () async {
    final app = createTuiTestApp(
      const SizedBox(width: 0, child: TextInput(autofocus: true)),
    );
    addTearDown(app.dispose);
    app.pumpFrame();
    await Future<void>.delayed(Duration.zero);
    app.pumpFrame();

    expect(app.captureFrame().cursor.visible, isFalse);
  });

  test('exact-height unwrapped TextArea keeps its caret on resize', () async {
    final controller = TextEditingController(text: 'abcdefgh\nijklmnop')
      ..selection = const TextSelection.collapsed(offset: 17);
    final app = createTuiTestApp(
      TextArea(controller: controller, autofocus: true, height: 2),
      width: 12,
      height: 2,
    );
    addTearDown(controller.dispose);
    addTearDown(app.dispose);
    app.pumpFrame();
    await Future<void>.delayed(Duration.zero);
    app.pumpFrame();
    expect(app.captureFrame(), BufferMatchers.cursorAt(8, 1));

    app.resize(4, 1);
    app.pumpFrame();
    final narrow = app.captureFrame();
    expect(narrow, BufferMatchers.cursorAt(3, 0));
    expect(narrow.toLines(), ['nop']);

    app.resize(12, 2);
    app.pumpFrame();
    expect(app.captureFrame(), BufferMatchers.cursorAt(8, 1));
  });

  test(
    'TextArea preserves cell alignment after clipping a wide glyph',
    () async {
      final controller = TextEditingController(text: '中ab')
        ..selection = const TextSelection.collapsed(offset: 2);
      final app = createTuiTestApp(
        TextArea(controller: controller, autofocus: true, width: 3, height: 1),
        width: 3,
        height: 1,
      );
      addTearDown(controller.dispose);
      addTearDown(app.dispose);
      app.pumpFrame();
      await Future<void>.delayed(Duration.zero);
      app.pumpFrame();

      final frame = app.captureFrame();
      expect(frame, BufferMatchers.hasCharAt(0, 0, ' '));
      expect(frame, BufferMatchers.hasCharAt(1, 0, 'a'));
      expect(frame, BufferMatchers.hasCharAt(2, 0, 'b'));
      expect(frame, BufferMatchers.cursorAt(2, 0));
    },
  );
}
