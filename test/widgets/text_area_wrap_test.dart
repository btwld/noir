import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart' show RenderTextArea;
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';
import '../helpers/tui_test_app.dart';
import '../helpers/widget_tester.dart';

void main() {
  test('soft wrap is cell-aware and grows only to its bounded content', () {
    final tester = WidgetTester(maxWidth: 3, maxHeight: 10);
    addTearDown(tester.dispose);

    tester.pumpWidget(
      const TextArea(
        value: 'ab中',
        width: 3,
        height: 1,
        maxHeight: 3,
        softWrap: true,
      ),
    );

    final render = tester.renderObject<RenderTextArea>(RenderTextArea)!;
    expect(render.size.width, 3);
    expect(render.size.height, 2);
  });

  test('soft wrap paints wide graphemes without splitting cells', () {
    final capture = BufferCapture(width: 3, height: 2);
    addTearDown(capture.dispose);

    final frame = capture.capture(
      const TextArea(
        value: 'ab中',
        width: 3,
        height: 1,
        maxHeight: 2,
        softWrap: true,
      ),
    );

    expect(frame.getRegion(0, 0, 3, 1), 'ab ');
    expect(frame.getRegion(0, 1, 3, 1), '中  ');
  });

  test('bounded growth caps and scrolls the wrapped caret into view', () async {
    final controller = TextEditingController(text: 'abcdefgh')
      ..selection = const TextSelection.collapsed(offset: 8);
    final app = createTuiTestApp(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextArea(
            autofocus: true,
            controller: controller,
            width: 2,
            height: 1,
            maxHeight: 2,
            softWrap: true,
          ),
        ],
      ),
      width: 2,
      height: 3,
    );
    addTearDown(app.dispose);
    addTearDown(controller.dispose);

    app.pumpFrame();
    await Future<void>.delayed(Duration.zero);
    app.pumpFrame();

    final frame = app.captureFrame();
    expect(frame.toLines().take(2), ['gh', '']);
    expect(frame.cursor.visible, isTrue);
    expect(frame.cursor.x, 0);
    expect(frame.cursor.y, 1);
  });

  test('wrapped ArrowUp and ArrowDown move by visual rows', () async {
    final controller = TextEditingController(text: 'abcd')
      ..selection = const TextSelection.collapsed(offset: 4);
    final driver = KeyDriver(
      TextArea(
        autofocus: true,
        controller: controller,
        width: 2,
        height: 1,
        maxHeight: 3,
        softWrap: true,
      ),
      width: 2,
      height: 3,
      paintFrames: true,
    );
    await driver.ready();

    await driver.sendLogicalKey(LogicalKeyboardKey.arrowUp);
    expect(controller.selection.extentOffset, 2);
    await driver.sendLogicalKey(LogicalKeyboardKey.arrowUp);
    expect(controller.selection.extentOffset, 0);
    await driver.sendLogicalKey(LogicalKeyboardKey.arrowDown);
    expect(controller.selection.extentOffset, 2);

    driver.dispose();
    controller.dispose();
  });

  test('visual arrows retain the requested side of wrap boundaries', () async {
    final controller = TextEditingController(text: 'abcd')
      ..selection = const TextSelection.collapsed(
        offset: 2,
        affinity: TextAffinity.upstream,
      );
    final driver = KeyDriver(
      TextArea(
        autofocus: true,
        controller: controller,
        width: 2,
        height: 1,
        maxHeight: 3,
        softWrap: true,
      ),
      width: 2,
      height: 3,
      paintFrames: true,
    );
    await driver.ready();

    await driver.sendLogicalKey(LogicalKeyboardKey.arrowDown);
    expect(controller.selection.extentOffset, 4);
    expect(controller.selection.affinity, TextAffinity.upstream);
    driver.app.debugFlushFrame();
    expect(driver.app.buildOwner.cursorController.y, 1);

    await driver.sendLogicalKey(LogicalKeyboardKey.arrowUp);
    expect(controller.selection.extentOffset, 2);
    expect(controller.selection.affinity, TextAffinity.upstream);
    driver.app.debugFlushFrame();
    expect(driver.app.buildOwner.cursorController.y, 0);

    driver.dispose();
    controller.dispose();
  });

  test('trailing newline contributes an empty visual editor row', () {
    final tester = WidgetTester(maxWidth: 4, maxHeight: 10);
    addTearDown(tester.dispose);

    tester.pumpWidget(
      const TextArea(
        value: 'a\n',
        width: 4,
        height: 1,
        maxHeight: 3,
        softWrap: true,
      ),
    );

    expect(tester.renderObject<RenderTextArea>(RenderTextArea)!.size.height, 2);
  });

  test('middle empty logical lines remain distinct visual rows', () {
    final capture = BufferCapture(width: 3, height: 3);
    addTearDown(capture.dispose);

    final frame = capture.capture(
      const TextArea(
        value: 'a\n\nb',
        width: 3,
        height: 1,
        maxHeight: 3,
        softWrap: true,
      ),
    );

    expect(frame.toLines(), ['a', '', 'b']);
  });

  test(
    'an exact-width hard break keeps before and after positions distinct',
    () async {
      final controller = TextEditingController(text: 'ab\nc')
        ..selection = const TextSelection.collapsed(offset: 2);
      final app = createTuiTestApp(
        TextArea(
          autofocus: true,
          controller: controller,
          width: 2,
          height: 2,
          softWrap: true,
        ),
        width: 2,
        height: 2,
      );
      addTearDown(app.dispose);
      addTearDown(controller.dispose);

      app.pumpFrame();
      await Future<void>.delayed(Duration.zero);
      app.pumpFrame();
      expect(app.captureFrame().cursor.visible, isTrue);
      expect(app.captureFrame().cursor.y, 0);

      controller.selection = const TextSelection.collapsed(offset: 3);
      app.pumpFrame();
      expect(app.captureFrame().cursor.visible, isTrue);
      expect(app.captureFrame().cursor.x, 0);
      expect(app.captureFrame().cursor.y, 1);
    },
  );

  test('selection affinity chooses a side of a soft-wrap boundary', () async {
    final controller = TextEditingController(text: 'abcd')
      ..selection = const TextSelection.collapsed(
        offset: 2,
        affinity: TextAffinity.upstream,
      );
    final app = createTuiTestApp(
      TextArea(
        autofocus: true,
        controller: controller,
        width: 2,
        height: 2,
        softWrap: true,
      ),
      width: 2,
      height: 2,
    );
    addTearDown(app.dispose);
    addTearDown(controller.dispose);

    app.pumpFrame();
    await Future<void>.delayed(Duration.zero);
    app.pumpFrame();
    expect(app.captureFrame().cursor.visible, isTrue);
    expect(app.captureFrame().cursor.y, 0);

    controller.selection = const TextSelection.collapsed(offset: 2);
    app.pumpFrame();
    expect(app.captureFrame().cursor.visible, isTrue);
    expect(app.captureFrame().cursor.x, 0);
    expect(app.captureFrame().cursor.y, 1);
  });

  test(
    'resize recomputes wrapping and keeps the trailing caret visible',
    () async {
      final controller = TextEditingController(text: 'abcdef')
        ..selection = const TextSelection.collapsed(offset: 6);
      final app = createTuiTestApp(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextArea(
              autofocus: true,
              controller: controller,
              height: 1,
              maxHeight: 3,
              softWrap: true,
            ),
          ],
        ),
        width: 3,
        height: 5,
      );
      addTearDown(app.dispose);
      addTearDown(controller.dispose);

      app.pumpFrame();
      await Future<void>.delayed(Duration.zero);
      app.pumpFrame();
      expect(app.captureFrame().cursor.visible, isTrue);
      expect(app.captureFrame().cursor.y, 2);

      app.resize(2, 5);
      app.pumpFrame();
      expect(app.captureFrame().cursor.visible, isTrue);
      expect(app.captureFrame().cursor.y, 2);

      app.resize(4, 5);
      app.pumpFrame();
      expect(app.captureFrame().cursor.visible, isTrue);
      expect(app.captureFrame().cursor.y, 1);
    },
  );
}
