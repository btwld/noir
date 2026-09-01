// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/painting/tui_canvas.dart';
import 'package:test/test.dart';

import '../helpers/key_driver.dart';

void main() {
  group('TextEditingController multiline helpers', () {
    test('insert at cursor', () {
      final controller = TextEditingController(text: 'abc')..setCursor(0, 1);
      controller.insert('X');
      expect(controller.text, 'aXbc');
      expect(controller.line, 0);
      expect(controller.col, 2);
    });

    test('newline splits line', () {
      final controller = TextEditingController(text: 'abc')..setCursor(0, 1);
      controller.newline();
      expect(controller.lines, ['a', 'bc']);
      expect(controller.line, 1);
      expect(controller.col, 0);
    });

    test('deleteBack at line start joins with previous', () {
      final controller = TextEditingController(text: 'foo\nbar')
        ..setCursor(1, 0);
      expect(controller.deleteBack(), isTrue);
      expect(controller.text, 'foobar');
      expect(controller.line, 0);
      expect(controller.col, 3);
    });

    test('deleteForward at line end joins with next', () {
      final controller = TextEditingController(text: 'foo\nbar')
        ..setCursor(0, 3);
      expect(controller.deleteForward(), isTrue);
      expect(controller.text, 'foobar');
      expect(controller.line, 0);
      expect(controller.col, 3);
    });

    test('moveDown clamps column to next line length', () {
      final controller = TextEditingController(text: 'hello\nhi')
        ..setCursor(0, 5);
      controller.moveCursorDown();
      expect(controller.line, 1);
      expect(controller.col, 2);
    });

    test('insert with allowNewline:false rejects multi-line input', () {
      final controller = TextEditingController(text: 'abc')..setCursor(0, 3);
      expect(controller.insert('x\ny', allowNewline: false), isFalse);
      expect(controller.text, 'abc');
      expect(controller.insert('x', allowNewline: false), isTrue);
      expect(controller.text, 'abcx');
    });
  });

  group('TextArea', () {
    test('Enter inserts newline and onChanged fires', () async {
      final changes = <String>[];
      final driver = KeyDriver(
        TextArea(autofocus: true, height: 3, width: 20, onChanged: changes.add),
      );
      await driver.ready();

      await driver.sendCharacter('h');
      await driver.sendCharacter('i');
      await driver.sendLogicalKey(LogicalKeyboardKey.enter);
      await driver.sendCharacter('y');

      expect(changes.last, 'hi\ny');
      driver.dispose();
    });

    test('readOnly blocks insertion but allows cursor movement', () async {
      final changes = <String>[];
      final driver = KeyDriver(
        TextArea(
          autofocus: true,
          height: 3,
          width: 20,
          readOnly: true,
          value: 'abc',
          onChanged: changes.add,
        ),
      );
      await driver.ready();
      await driver.sendCharacter('x');
      expect(changes, isEmpty);
      driver.dispose();
    });

    test('Ctrl+Enter fires onSubmit', () async {
      var submitted = false;
      final driver = KeyDriver(
        TextArea(
          autofocus: true,
          height: 3,
          width: 20,
          onSubmit: () => submitted = true,
        ),
      );
      await driver.ready();
      await driver.sendLogicalKey(
        LogicalKeyboardKey.enter,
        code: 13,
        modifiers: KeyModifiers.ctrl,
      );
      expect(submitted, isTrue);
      driver.dispose();
    });

    test('submitOnEnter submits while Ctrl+J inserts a newline', () async {
      final controller = TextEditingController();
      final changes = <String>[];
      var submits = 0;
      final driver = KeyDriver(
        TextArea(
          autofocus: true,
          controller: controller,
          height: 1,
          width: 20,
          submitOnEnter: true,
          onChanged: changes.add,
          onSubmit: () => submits++,
        ),
      );
      await driver.ready();

      await driver.sendCharacter('a');
      await driver.sendLogicalKey(LogicalKeyboardKey.enter);
      expect(controller.text, 'a');
      expect(submits, 1);

      await driver.sendLogicalKey(
        LogicalKeyboardKey.keyJ,
        code: 10,
        modifiers: KeyModifiers.ctrl,
      );
      expect(controller.text, 'a\n');
      expect(changes, ['a', 'a\n']);

      await driver.sendPaste('b\nc');
      expect(controller.text, 'a\nb\nc');
      expect(changes, ['a', 'a\n', 'a\nb\nc']);

      driver.dispose();
      controller.dispose();
    });

    test('submitOnEnter keeps Ctrl+J inside ordinary editing policy', () async {
      final readOnlyController = TextEditingController(text: 'a')
        ..selection = const TextSelection.collapsed(offset: 1);
      final readOnlyDriver = KeyDriver(
        TextArea(
          autofocus: true,
          controller: readOnlyController,
          submitOnEnter: true,
          readOnly: true,
        ),
      );
      await readOnlyDriver.ready();
      await readOnlyDriver.sendLogicalKey(
        LogicalKeyboardKey.keyJ,
        code: 10,
        modifiers: KeyModifiers.ctrl,
      );
      expect(readOnlyController.text, 'a');
      readOnlyDriver.dispose();
      readOnlyController.dispose();

      final limitedController = TextEditingController(text: 'a')
        ..selection = const TextSelection.collapsed(offset: 1);
      final limitedDriver = KeyDriver(
        TextArea(
          autofocus: true,
          controller: limitedController,
          submitOnEnter: true,
          maxLength: 1,
        ),
      );
      await limitedDriver.ready();
      await limitedDriver.sendLogicalKey(
        LogicalKeyboardKey.keyJ,
        code: 10,
        modifiers: KeyModifiers.ctrl,
      );
      expect(limitedController.text, 'a');
      limitedDriver.dispose();
      limitedController.dispose();

      var bubbled = 0;
      final submitDriver = KeyDriver(
        Focus(
          onKeyEvent: (node, event) {
            bubbled++;
            return KeyEventResult.ignored;
          },
          child: const TextArea(autofocus: true, submitOnEnter: true),
        ),
      );
      await submitDriver.ready();
      await submitDriver.sendLogicalKey(LogicalKeyboardKey.enter);
      expect(bubbled, 0);
      submitDriver.dispose();
    });

    test(
      'submits multiline text and renders cursor at edited position',
      () async {
        var currentValue = '';
        String? submittedText;
        final driver = KeyDriver(
          TextArea(
            autofocus: true,
            height: 3,
            width: 20,
            onChanged: (value) => currentValue = value,
            onSubmit: () => submittedText = currentValue,
          ),
        );
        await driver.ready();

        for (final key in ['h', 'e', 'l', 'l', 'o']) {
          await driver.sendCharacter(key);
        }
        await driver.sendLogicalKey(LogicalKeyboardKey.enter);
        for (final key in ['w', 'o', 'r', 'l', 'd']) {
          await driver.sendCharacter(key);
        }
        await driver.sendLogicalKey(
          LogicalKeyboardKey.enter,
          code: 13,
          modifiers: KeyModifiers.ctrl,
        );
        driver.dispose();

        expect(submittedText, 'hello\nworld');

        final controller = TextEditingController(text: 'hello\nworld')
          ..setCursor(1, 5);

        final cursor = CursorController();
        final render = RenderTextArea(
          cursorController: cursor,
          lines: controller.lines,
          cursorLine: controller.line,
          cursorColumn: controller.col,
          placeholder: null,
          heightLines: 3,
          explicitWidth: 20,
          color: Color.white,
          backgroundColor: null,
          cursorColor: Color.white,
          cursorStyle: CursorStyle.block,
          focused: true,
          scrollLine: 0,
          scrollCell: 0,
        );
        final renderer = Renderer.create(20, 3, testing: true);
        try {
          render.performBoxLayout(
            const BoxConstraints.tight(width: 20, height: 3),
          );
          final buffer = renderer.nextBuffer;
          buffer.clear(Color.black);
          final canvas = createTuiCanvas();
          render.paint(PaintingContext(canvas), Offset.zero);
          commitTuiCanvas(buffer, canvas);
        } finally {
          renderer.dispose();
        }

        expect(controller.text, 'hello\nworld');
        expect(controller.line, 1);
        expect(controller.col, 5);
        expect(cursor.isVisible, isTrue);
        expect(cursor.x, 5);
        expect(cursor.y, 1);
        controller.dispose();
      },
    );
  });
}
