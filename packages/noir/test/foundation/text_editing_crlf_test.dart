import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  for (final newline in ['\n', '\r\n']) {
    test('line movement excludes the hard break ${newline.codeUnits}', () {
      final text = 'a$newline$newline中b';
      final controller = TextEditingController(text: text)
        ..selection = const TextSelection.collapsed(offset: 0);
      addTearDown(controller.dispose);

      expect(controller.lines, text.split('\n'));
      controller.moveLineEnd();
      expect(controller.selection.extentOffset, 1);
      expect((controller.line, controller.col), (0, 1));

      controller.moveCursorDown();
      expect(controller.selection.extentOffset, 1 + newline.length);
      expect((controller.line, controller.col), (1, 0));
      controller.moveLineEnd();
      expect(controller.selection.extentOffset, 1 + newline.length);

      controller.moveCursorDown();
      expect(controller.selection.extentOffset, 1 + newline.length * 2);
      controller.moveLineEnd();
      expect(controller.selection.extentOffset, text.length);
      controller.moveCursorUp();
      expect(controller.selection.extentOffset, 1 + newline.length);
      controller.moveCursorUp();
      expect(controller.selection.extentOffset, 0);

      controller.setCursor(0, 99);
      expect(controller.selection.extentOffset, 1);
      controller.moveLineStart();
      expect(controller.selection.extentOffset, 0);
      expect(controller.text, text);
    });
  }

  test('End insertion preserves CRLF and horizontal movement skips it', () {
    final controller = TextEditingController(text: 'a\r\nb')
      ..selection = const TextSelection.collapsed(offset: 0);
    addTearDown(controller.dispose);

    controller.moveLineEnd();
    controller.insert('x');
    expect(controller.text, 'ax\r\nb');
    expect(controller.selection.extentOffset, 2);
    controller.moveCursorRight();
    expect(controller.selection.extentOffset, 4);
    expect((controller.line, controller.col), (1, 0));
    controller.moveCursorLeft();
    expect(controller.selection.extentOffset, 2);
    controller.moveCursorRight();
    expect(controller.deleteBack(), isTrue);
    expect(controller.text, 'axb');
    expect(controller.selection.extentOffset, 2);
  });

  test('standalone CR remains line content', () {
    for (final text in ['a\rb', 'a\r']) {
      final controller = TextEditingController(text: text)
        ..selection = const TextSelection.collapsed(offset: 0);
      addTearDown(controller.dispose);
      controller.moveLineEnd();
      expect(controller.selection.extentOffset, text.length);
      expect((controller.line, controller.col), (0, text.length));
      expect(controller.lines, [text]);
    }
  });
}
