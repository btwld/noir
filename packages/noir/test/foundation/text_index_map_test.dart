import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  group('TextIndexMap', () {
    test('maps emoji between UTF-16 offsets and grapheme indices', () {
      final map = TextIndexMap('a😀b');

      expect(map.graphemeCount, 3);
      expect(map.utf16ToGrapheme(2), 1);
      expect(map.graphemeToUtf16(2), 3);
    });

    test('treats combining marks and ZWJ sequences as single graphemes', () {
      final combining = TextIndexMap('e\u0301');
      expect(combining.graphemeCount, 1);
      expect(combining.graphemeToUtf16(1), 2);

      final zwj = TextIndexMap('👩‍💻');
      expect(zwj.graphemeCount, 1);
      expect(zwj.graphemeToUtf16(1), '👩‍💻'.length);
    });
  });
}
