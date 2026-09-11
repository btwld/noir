import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/tui_test_app.dart';

void main() {
  test('TextInput receives emoji and CJK through UTF-8 parser path', () async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final app = createTuiTestApp(
      TextInput(autofocus: true, controller: controller),
      width: 12,
    );
    addTearDown(app.dispose);

    app.pumpFrame();
    await Future<void>.delayed(Duration.zero);
    app.mockInput.typeText('a😀中');
    app.pumpFrame();

    final captured = app.captureFrame();
    expect(controller.text, 'a😀中');
    // Each wide glyph owns its overhang cell, so the region reads as the
    // glyphs themselves rather than glyph, blank, glyph.
    expect(captured.getRegion(0, 0, 6, 1), startsWith('a😀中'));
    expect(captured.cursor, isNotNull);
    expect(captured.cursor.x, 5);
  });

  test('TextInput moves the cursor by grapheme through parser keys', () async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final app = createTuiTestApp(
      TextInput(autofocus: true, controller: controller),
      width: 24,
    );
    addTearDown(app.dispose);

    app.pumpFrame();
    await Future<void>.delayed(Duration.zero);
    app.mockInput.typeText('a😀中é👩‍💻');
    app.pumpFrame();

    expect(controller.selection, const TextSelection.collapsed(offset: 11));

    app.mockInput.pressArrow(ArrowDirection.left);
    app.pumpFrame();
    expect(controller.selection, const TextSelection.collapsed(offset: 6));

    app.mockInput.pressArrow(ArrowDirection.left);
    app.pumpFrame();
    expect(controller.selection, const TextSelection.collapsed(offset: 4));

    app.mockInput.pressArrow(ArrowDirection.left);
    app.pumpFrame();
    expect(controller.selection, const TextSelection.collapsed(offset: 3));

    app.mockInput.pressArrow(ArrowDirection.right);
    app.pumpFrame();
    expect(controller.selection, const TextSelection.collapsed(offset: 4));
  });

  test(
    'TextInput replaces selected multi-cell graphemes from UTF-8 input',
    () async {
      final controller = TextEditingController(text: 'a😀中b')
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 4);
      addTearDown(controller.dispose);
      final app = createTuiTestApp(
        TextInput(autofocus: true, controller: controller),
        width: 12,
      );
      addTearDown(app.dispose);

      app.pumpFrame();
      await Future<void>.delayed(Duration.zero);
      app.mockInput.typeText('é');
      app.pumpFrame();

      expect(controller.text, 'aéb');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
    },
  );

  test('TextArea paste keeps multiline Unicode grapheme boundaries', () async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final app = createTuiTestApp(
      TextArea(autofocus: true, width: 8, height: 2, controller: controller),
      width: 10,
      height: 3,
    );
    addTearDown(app.dispose);

    app.pumpFrame();
    await Future<void>.delayed(Duration.zero);
    app.mockInput.paste('é\n👩‍💻');
    app.pumpFrame();

    final captured = app.captureFrame();
    expect(controller.text, 'é\n👩‍💻');
    expect(captured.getRegion(0, 0, 4, 1), 'é   ');
    expect(captured.getRegion(0, 1, 4, 1), startsWith('👩'));
  });

  test(
    'TextArea replaces multiline Unicode selection from parser paste',
    () async {
      final controller = TextEditingController(text: 'α😀\n中👩‍💻z')
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 10);
      addTearDown(controller.dispose);
      final app = createTuiTestApp(
        TextArea(autofocus: true, width: 10, height: 2, controller: controller),
        width: 12,
        height: 3,
      );
      addTearDown(app.dispose);

      app.pumpFrame();
      await Future<void>.delayed(Duration.zero);
      app.mockInput.paste('é\nβ');
      app.pumpFrame();

      expect(controller.text, 'αé\nβz');
      expect(controller.selection, const TextSelection.collapsed(offset: 4));
    },
  );

  test('TextInput obscureText masks one cell per Unicode grapheme', () async {
    final controller = TextEditingController(text: 'a😀é👩‍💻')
      ..selection = const TextSelection.collapsed(offset: 10);
    addTearDown(controller.dispose);
    final app = createTuiTestApp(
      TextInput(autofocus: true, controller: controller, obscureText: true),
      width: 12,
    );
    addTearDown(app.dispose);

    app.pumpFrame();
    await Future<void>.delayed(Duration.zero);
    app.pumpFrame();
    final captured = app.captureFrame();

    expect(controller.text, 'a😀é👩‍💻');
    expect(captured.getRegion(0, 0, 6, 1), '****  ');
    expect(captured.cursor.x, 4);
  });
}
