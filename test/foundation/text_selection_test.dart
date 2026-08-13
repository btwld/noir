import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  group('TextSelection', () {
    test('normalizes range while preserving base and extent', () {
      const selection = TextSelection(
        baseOffset: 5,
        extentOffset: 2,
        affinity: TextAffinity.upstream,
      );

      expect(selection.start, 2);
      expect(selection.end, 5);
      expect(selection.baseOffset, 5);
      expect(selection.extentOffset, 2);
      expect(selection.affinity, TextAffinity.upstream);
      expect(selection.isCollapsed, isFalse);
    });

    test('collapsed selection uses one UTF-16 offset', () {
      const selection = TextSelection.collapsed(offset: 3);

      expect(selection.start, 3);
      expect(selection.end, 3);
      expect(selection.baseOffset, 3);
      expect(selection.extentOffset, 3);
      expect(selection.isCollapsed, isTrue);
    });

    test('equality includes affinity and directionality', () {
      const downstream = TextSelection.collapsed(offset: 3);
      const upstream = TextSelection.collapsed(
        offset: 3,
        affinity: TextAffinity.upstream,
      );
      const directional = TextSelection(
        baseOffset: 3,
        extentOffset: 3,
        isDirectional: true,
      );

      expect(downstream, isNot(upstream));
      expect(downstream, isNot(directional));
    });
  });
}
