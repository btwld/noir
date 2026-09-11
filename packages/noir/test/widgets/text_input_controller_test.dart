import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';
import '../helpers/test_element_host.dart';

void main() {
  group('TextInput controller', () {
    test('user input updates the supplied controller', () async {
      final controller = TextEditingController();
      final driver = KeyDriver(
        TextInput(autofocus: true, controller: controller),
      );
      await driver.ready();

      await driver.sendCharacter('h');
      await driver.sendCharacter('i');
      await driver.sendLogicalKey(LogicalKeyboardKey.backspace);

      expect(controller.text, 'h');
      expect(controller.selection, const TextSelection.collapsed(offset: 1));

      driver.dispose();
      controller.dispose();
    });

    test('programmatic controller text changes repaint the field', () {
      final controller = TextEditingController(text: 'old');
      final renderer = Renderer.create(12, 1, testing: true);
      final buffer = renderer.nextBuffer;
      final host = TestElementHost(renderer: renderer)
        ..mount(TextInput(controller: controller));

      try {
        buffer.clear(Color.black);
        host.pumpFrame(buffer: buffer);
        expect(
          CapturedBuffer.fromBuffer(buffer).getRegion(0, 0, 12, 1),
          startsWith('old'),
        );

        controller.text = 'new';
        host.owner.buildScope();
        buffer.clear(Color.black);
        host.pumpFrame(buffer: buffer);

        expect(
          CapturedBuffer.fromBuffer(buffer).getRegion(0, 0, 12, 1),
          startsWith('new'),
        );
      } finally {
        host.dispose();
        renderer.dispose();
        controller.dispose();
      }
    });

    test(
      'autofocus activates invalid controller selection before painting',
      () async {
        final controller = TextEditingController(text: 'abc');
        final driver = KeyDriver(
          TextInput(autofocus: true, controller: controller),
          paintFrames: true,
          width: 12,
          height: 1,
        );
        await driver.ready();

        expect(controller.selection, const TextSelection.collapsed(offset: 3));
        expect(driver.app.buildOwner.cursorController.x, 3);

        driver.dispose();
        controller.dispose();
      },
    );

    test('onChanged fires once for a paste transaction', () async {
      final controller = TextEditingController();
      final changes = <String>[];
      final driver = KeyDriver(
        TextInput(
          autofocus: true,
          controller: controller,
          onChanged: changes.add,
        ),
      );
      await driver.ready();

      await driver.sendPaste('secret');

      expect(controller.text, 'secret');
      expect(changes, ['secret']);

      driver.dispose();
      controller.dispose();
    });

    test('obscureText masks rendering but keeps controller text raw', () {
      final controller = TextEditingController(text: 'pass');
      final capture = BufferCapture(width: 12, height: 1);
      try {
        final captured = capture.capture(
          TextInput(controller: controller, obscureText: true),
        );

        expect(captured.getRegion(0, 0, 12, 1), startsWith('****'));
        expect(controller.text, 'pass');
      } finally {
        capture.dispose();
        controller.dispose();
      }
    });

    test('selection survives rebuild with the same controller', () {
      final controller = TextEditingController(text: 'abcd')
        ..selection = const TextSelection.collapsed(offset: 2);
      final capture = BufferCapture(width: 12, height: 1);
      try {
        capture
          ..capture(TextInput(controller: controller))
          ..capture(TextInput(controller: controller, color: Color.green));

        expect(controller.selection, const TextSelection.collapsed(offset: 2));
      } finally {
        capture.dispose();
        controller.dispose();
      }
    });

    test('controller and value cannot both be supplied', () {
      final controller = TextEditingController();
      try {
        expect(
          () => TextInput(controller: controller, value: 'initial'),
          throwsA(isA<AssertionError>()),
        );
      } finally {
        controller.dispose();
      }
    });
  });
}
