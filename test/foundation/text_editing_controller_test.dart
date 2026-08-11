// ignore_for_file: cascade_invocations

import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  group('TextEditingController', () {
    test('constructor and text setter clear selection and notify once', () {
      final controller = TextEditingController(text: 'hello');
      var calls = 0;
      controller.addListener(() => calls++);

      expect(controller.selection, const TextSelection.collapsed(offset: -1));

      controller.text = 'hello!';

      expect(controller.text, 'hello!');
      expect(controller.selection, const TextSelection.collapsed(offset: -1));
      expect(calls, 1);
    });

    test('selection setter updates value without changing text', () {
      final controller = TextEditingController(text: 'hello');
      final values = <TextEditingValue>[];
      controller.addListener(() => values.add(controller.value));

      controller.selection = const TextSelection.collapsed(offset: 2);

      expect(controller.text, 'hello');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
      expect(values, [
        const TextEditingValue(
          text: 'hello',
          selection: TextSelection.collapsed(offset: 2),
        ),
      ]);
    });

    test('clear empties text and collapses selection', () {
      final controller = TextEditingController(text: 'hello');

      controller.clear();

      expect(
        controller.value,
        const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
      );
    });

    test('selection setter rejects offsets outside the current text', () {
      final controller = TextEditingController(text: 'hello');

      expect(
        () => controller.selection = const TextSelection.collapsed(offset: 6),
        throwsRangeError,
      );
      expect(controller.selection, const TextSelection.collapsed(offset: -1));
    });

    test('dispose is idempotent and rejects new listeners', () {
      final controller = TextEditingController(text: 'hello');

      controller
        ..dispose()
        ..dispose();

      expect(() => controller.addListener(() {}), throwsStateError);
    });

    test('insert and delete operate on grapheme clusters', () {
      final controller = TextEditingController(text: 'a😀b')
        ..selection = const TextSelection.collapsed(offset: 3);

      expect(controller.deleteBack(), isTrue);
      expect(controller.text, 'ab');
      expect(controller.selection, const TextSelection.collapsed(offset: 1));

      expect(controller.insert('中'), isTrue);
      expect(controller.text, 'a中b');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
    });

    test('multiline movement preserves preferred column by grapheme index', () {
      final controller = TextEditingController(text: 'hello\nhi')
        ..selection = const TextSelection.collapsed(offset: 5);

      controller.moveCursorDown();

      expect(controller.selection, const TextSelection.collapsed(offset: 8));
    });
  });
}
