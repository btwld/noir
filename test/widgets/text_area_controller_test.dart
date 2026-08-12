import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';
import '../helpers/test_element_host.dart';

void main() {
  group('TextArea controller', () {
    test('user input updates the supplied controller across lines', () async {
      final controller = TextEditingController();
      final driver = KeyDriver(
        TextArea(autofocus: true, height: 3, width: 20, controller: controller),
      );
      await driver.ready();

      await driver.sendCharacter('h');
      await driver.sendCharacter('i');
      await driver.sendLogicalKey(LogicalKeyboardKey.enter);
      await driver.sendCharacter('y');

      expect(controller.text, 'hi\ny');
      expect(controller.selection, const TextSelection.collapsed(offset: 4));

      driver.dispose();
      controller.dispose();
    });

    test('programmatic controller text changes repaint the field', () {
      final controller = TextEditingController(text: 'old');
      final renderer = Renderer.create(12, 3, testing: true);
      final buffer = renderer.nextBuffer;
      final host = TestElementHost(renderer: renderer)
        ..mount(TextArea(controller: controller, height: 3, width: 12));

      try {
        buffer.clear(Color.black);
        host.pumpFrame(buffer: buffer);
        expect(
          CapturedBuffer.fromBuffer(buffer).getRegion(0, 0, 12, 1),
          startsWith('old'),
        );

        controller.text = 'new\nline';
        host.owner.buildScope();
        buffer.clear(Color.black);
        host.pumpFrame(buffer: buffer);
        final captured = CapturedBuffer.fromBuffer(buffer);

        expect(captured.getRegion(0, 0, 12, 1), startsWith('new'));
        expect(captured.getRegion(0, 1, 12, 1), startsWith('line'));
      } finally {
        host.dispose();
        renderer.dispose();
        controller.dispose();
      }
    });

    test(
      'autofocus activates invalid controller selection before painting',
      () async {
        final controller = TextEditingController(text: 'abc\ndef');
        final driver = KeyDriver(
          TextArea(
            autofocus: true,
            height: 3,
            width: 12,
            controller: controller,
          ),
          paintFrames: true,
          width: 12,
          height: 3,
        );
        await driver.ready();

        final cursor = driver.app.buildOwner.cursorController;
        expect(controller.selection, const TextSelection.collapsed(offset: 7));
        expect(cursor.x, 3);
        expect(cursor.y, 1);

        driver.dispose();
        controller.dispose();
      },
    );

    test(
      'programmatic selection changes scroll the cursor into view',
      () async {
        final controller = TextEditingController(
          text: List.generate(8, (index) => 'line$index').join('\n'),
        );
        final driver = KeyDriver(
          TextArea(
            autofocus: true,
            height: 3,
            width: 8,
            controller: controller,
          ),
          paintFrames: true,
          width: 8,
          height: 3,
        );
        await driver.ready();

        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
        driver.app.debugFlushFrame();

        final cursor = driver.app.buildOwner.cursorController;
        expect(cursor.isVisible, isTrue);
        expect(cursor.y, 2);

        driver.dispose();
        controller.dispose();
      },
    );

    test(
      'completed 4x2 layout beats null-width and configured-height hints',
      () async {
        final controller = TextEditingController(text: _longMultilineText)
          ..selection = const TextSelection.collapsed(offset: 0);
        final driver = KeyDriver(
          TextArea(
            autofocus: true,
            // Explicit because this case distinguishes layout from this hint.
            // ignore: avoid_redundant_argument_values
            height: 5,
            controller: controller,
          ),
          paintFrames: true,
          width: 4,
          height: 2,
        );
        await driver.ready();

        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
        driver.app.debugFlushFrame();

        final cursor = driver.app.buildOwner.cursorController;
        expect(cursor.isVisible, isTrue);
        expect(cursor.x, 3);
        expect(cursor.y, 1);

        driver.dispose();
        controller.dispose();
      },
    );

    test('latest completed resize replaces the previous layout pair', () async {
      final controller = TextEditingController(text: _longMultilineText)
        ..selection = const TextSelection.collapsed(offset: 0);
      final driver = KeyDriver(
        TextArea(
          autofocus: true,
          // Explicit because this case distinguishes layout from this hint.
          // ignore: avoid_redundant_argument_values
          height: 5,
          controller: controller,
        ),
        paintFrames: true,
        width: 8,
        height: 4,
      );
      await driver.ready();

      driver.app
        ..handleResize(4, 2)
        ..debugFlushFrame();
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      driver.app.debugFlushFrame();

      final cursor = driver.app.buildOwner.cursorController;
      expect(cursor.isVisible, isTrue);
      expect(cursor.x, 3);
      expect(cursor.y, 1);

      driver.dispose();
      controller.dispose();
    });

    test('pre-layout cursor repair uses the complete fallback pair', () {
      final controller = TextEditingController(text: _fallbackMultilineText);
      final focusNode = FocusNode();
      final renderer = Renderer.create(4, 2, testing: true);
      final buffer = renderer.nextBuffer;
      final host = TestElementHost(renderer: renderer)
        ..mount(
          TextArea(
            controller: controller,
            focusNode: focusNode,
            // Explicit because this case characterizes the fallback pair.
            // ignore: avoid_redundant_argument_values
            height: 5,
          ),
        );

      try {
        focusNode.requestFocus();
        expect(
          controller.selection,
          TextSelection.collapsed(offset: controller.text.length),
        );

        buffer.clear(Color.black);
        host.pumpFrame(
          buffer: buffer,
          constraints: const BoxConstraints.tight(width: 4, height: 2),
        );
        final captured = CapturedBuffer.fromBuffer(buffer);

        expect(captured.getRegion(0, 0, 4, 1), 'aaaa');
        expect(captured.getRegion(0, 1, 4, 1), 'bbbb');
        expect(host.owner.cursorController.isVisible, isFalse);
      } finally {
        host.dispose();
        renderer.dispose();
        focusNode.dispose();
        controller.dispose();
      }
    });

    for (final zeroAxis in <({int width, int height})>[
      (width: 0, height: 2),
      (width: 4, height: 0),
    ]) {
      test(
        'completed ${zeroAxis.width}x${zeroAxis.height} layout falls back as a pair',
        () {
          final controller = TextEditingController(text: _longMultilineText)
            ..selection = const TextSelection.collapsed(offset: 0);
          final focusNode = FocusNode();
          final renderer = Renderer.create(4, 2, testing: true);
          final buffer = renderer.nextBuffer;
          final host = TestElementHost(renderer: renderer)
            ..mount(
              TextArea(
                controller: controller,
                focusNode: focusNode,
                // Explicit because this case characterizes the fallback pair.
                // ignore: avoid_redundant_argument_values
                height: 5,
              ),
            );

          try {
            focusNode.requestFocus();
            host.pumpFrame(
              constraints: BoxConstraints.tight(
                width: zeroAxis.width,
                height: zeroAxis.height,
              ),
            );

            controller.selection = TextSelection.collapsed(
              offset: controller.text.length,
            );
            buffer.clear(Color.black);
            host.pumpFrame(
              buffer: buffer,
              constraints: const BoxConstraints.tight(width: 4, height: 2),
            );
            final captured = CapturedBuffer.fromBuffer(buffer);

            expect(captured.getRegion(0, 0, 4, 1), 'bbbb');
            expect(captured.getRegion(0, 1, 4, 1), 'cccc');
            expect(host.owner.cursorController.isVisible, isFalse);
          } finally {
            host.dispose();
            renderer.dispose();
            focusNode.dispose();
            controller.dispose();
          }
        },
      );
    }

    test(
      'completed narrow layout preserves wide-cell cursor scrolling',
      () async {
        final controller = TextEditingController(text: '中中中')
          ..selection = const TextSelection.collapsed(offset: 0);
        final driver = KeyDriver(
          TextArea(autofocus: true, height: 2, controller: controller),
          paintFrames: true,
          width: 4,
          height: 2,
        );
        await driver.ready();

        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
        driver.app.debugFlushFrame();

        final cursor = driver.app.buildOwner.cursorController;
        expect(cursor.isVisible, isTrue);
        expect(cursor.x, 3);
        expect(cursor.y, 0);

        driver.dispose();
        controller.dispose();
      },
    );

    test('multi-line paste is one change transaction', () async {
      final controller = TextEditingController();
      final changes = <String>[];
      final driver = KeyDriver(
        TextArea(
          autofocus: true,
          height: 3,
          width: 20,
          controller: controller,
          onChanged: changes.add,
        ),
      );
      await driver.ready();

      await driver.sendPaste('hello\nworld');

      expect(controller.text, 'hello\nworld');
      expect(changes, ['hello\nworld']);

      driver.dispose();
      controller.dispose();
    });

    test('maxLength counts grapheme clusters, not UTF-16 code units', () async {
      final controller = TextEditingController();
      final changes = <String>[];
      final driver = KeyDriver(
        TextArea(
          autofocus: true,
          height: 3,
          width: 20,
          maxLength: 2,
          controller: controller,
          onChanged: changes.add,
        ),
      );
      await driver.ready();

      await driver.sendCharacter('😀');
      await driver.sendCharacter('a');
      await driver.sendCharacter('b');

      expect(controller.text, '😀a');
      expect(changes, ['😀', '😀a']);

      driver.dispose();
      controller.dispose();
    });

    test('controller and value cannot both be supplied', () {
      final controller = TextEditingController();
      try {
        expect(
          () => TextArea(controller: controller, value: 'initial'),
          throwsA(isA<AssertionError>()),
        );
      } finally {
        controller.dispose();
      }
    });
  });
}

const _longMultilineText =
    'aaaaaaaaaaaa\n'
    'bbbbbbbbbbbb\n'
    'cccccccccccc\n'
    'dddddddddddd\n'
    'eeeeeeeeeeee\n'
    'ffffffffffff';

const _fallbackMultilineText =
    'aaaaaaaaaaaa\n'
    'bbbbbbbbbbbb\n'
    'cccccccccccc\n'
    'dddddddddddd\n'
    'eeeeeeeeeeee';
