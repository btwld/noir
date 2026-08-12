import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  group('TextEditingValue', () {
    test('defaults to collapsed selection and empty composing range', () {
      const value = TextEditingValue(text: 'hello');

      expect(value.text, 'hello');
      expect(value.selection, const TextSelection.collapsed(offset: -1));
      expect(value.composing, TextRange.empty);
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
      expect(updated.composing, value.composing);
    });

    test('equality includes text, selection, and composing range', () {
      const first = TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      const second = TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      const different = TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 0),
        composing: TextRange(start: 0, end: 5),
      );

      expect(first, second);
      expect(first, isNot(different));
    });
  });
}
