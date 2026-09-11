import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  group('TextRange', () {
    test('uses UTF-16 offsets for text slices', () {
      const range = TextRange(start: 1, end: 3);

      expect(range.textBefore('a😀b'), 'a');
      expect(range.textInside('a😀b'), '😀');
      expect(range.textAfter('a😀b'), 'b');
    });

    test('reports collapsed, valid, and normalized state', () {
      const collapsed = TextRange.collapsed(2);
      const empty = TextRange.empty;
      const reversed = TextRange(start: 3, end: 1);

      expect(collapsed.isCollapsed, isTrue);
      expect(collapsed.isValid, isTrue);
      expect(collapsed.isNormalized, isTrue);

      expect(empty.isValid, isFalse);
      expect(empty.isCollapsed, isTrue);

      expect(reversed.isValid, isTrue);
      expect(reversed.isNormalized, isFalse);
    });

    test('does not compare equal to selection subclasses', () {
      const range = TextRange(start: 2, end: 5);
      const selection = TextSelection(baseOffset: 5, extentOffset: 2);

      expect(range == selection, isFalse);
      expect(selection == range, isFalse);
    });
  });
}
