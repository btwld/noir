import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  group('TextEditingValue', () {
    test('defaults to a collapsed selection', () {
      const value = TextEditingValue(text: 'hello');

      expect(value.text, 'hello');
      expect(value.selection, const TextSelection.collapsed(offset: -1));
    });

    test('copyWith replaces selected fields', () {
      const value = TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      );

      final updated = value.copyWith(
        text: 'hello!',
        selection: const TextSelection.collapsed(offset: 6),
      );

      expect(updated.text, 'hello!');
      expect(updated.selection, const TextSelection.collapsed(offset: 6));
    });

    test('equality includes text and selection', () {
      const first = TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      );
      const second = TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      );
      const different = TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 0),
      );

      expect(first, second);
      expect(first, isNot(different));
    });
  });
}
