// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  group('grapheme cell width', () {
    test('ASCII characters are 1 cell wide', () {
      expect(terminalCellWidth('A'), 1);
      expect(terminalCellWidth('1'), 1);
      expect(terminalCellWidth(' '), 1);
    });

    test('CJK ideographs are 2 cells wide', () {
      expect(terminalCellWidth('中'), 2);
      expect(terminalCellWidth('日'), 2);
      expect(terminalCellWidth('가'), 2); // Hangul syllable
    });

    test('Common emoji are 2 cells wide', () {
      expect(terminalCellWidth('😀'), 2);
      expect(terminalCellWidth('🎉'), 2);
    });

    test('terminalStringWidth sums grapheme widths', () {
      expect(terminalStringWidth('hello'), 5);
      expect(terminalStringWidth('中文'), 4);
      expect(terminalStringWidth('hi😀'), 4); // 1 + 1 + 2
    });

    test('graphemeIndexToCell maps grapheme positions to cell columns', () {
      // "ab中c": positions 0..4 should map to cells 0, 1, 2, 4, 5
      expect(graphemeIndexToCell('ab中c', 0), 0);
      expect(graphemeIndexToCell('ab中c', 1), 1);
      expect(graphemeIndexToCell('ab中c', 2), 2);
      expect(graphemeIndexToCell('ab中c', 3), 4);
      expect(graphemeIndexToCell('ab中c', 4), 5);
    });

    test('cellToGraphemeIndex maps cell columns back to grapheme index', () {
      // "ab中c": cell 3 falls inside the wide "中" → grapheme index stays at 2
      expect(cellToGraphemeIndex('ab中c', 0), 0);
      expect(cellToGraphemeIndex('ab中c', 1), 1);
      expect(cellToGraphemeIndex('ab中c', 2), 2);
      expect(cellToGraphemeIndex('ab中c', 3), 2);
      expect(cellToGraphemeIndex('ab中c', 4), 3);
    });

    test('sliceByCells respects cell budget and never half-paints wide', () {
      expect(sliceByCells('ab中c', 3), 'ab');
      expect(sliceByCells('ab中c', 4), 'ab中');
      expect(sliceByCells('中中', 1), '');
      expect(sliceByCells('中中', 2), '中');
    });
  });

  group('TextEditingController grapheme-aware editing', () {
    test('cursor advances one grapheme at a time over an emoji', () {
      final controller = TextEditingController(text: 'a😀b')..setCursor(0, 0);
      controller.moveCursorRight();
      expect(controller.col, 1);
      controller.moveCursorRight();
      expect(controller.col, 2); // skipped past the whole emoji as one unit
      controller.moveCursorRight();
      expect(controller.col, 3);
    });

    test('cursor moves over CJK characters one at a time', () {
      final controller = TextEditingController(text: '中文')..setCursor(0, 0);
      controller.moveCursorRight();
      expect(controller.col, 1);
      controller.moveCursorRight();
      expect(controller.col, 2);
    });

    test('deleteBack removes one grapheme cluster (emoji)', () {
      final controller = TextEditingController(text: 'a😀b')
        ..setCursor(0, 2); // after the emoji
      expect(controller.deleteBack(), isTrue);
      expect(controller.text, 'ab');
      expect(controller.col, 1);
    });

    test('deleteForward removes one grapheme cluster (CJK)', () {
      final controller = TextEditingController(text: '中文')..setCursor(0, 0);
      expect(controller.deleteForward(), isTrue);
      expect(controller.text, '文');
      expect(controller.col, 0);
    });

    test('moveLineEnd jumps to end in grapheme units, not code units', () {
      final controller = TextEditingController(text: 'a😀')..setCursor(0, 0);
      controller.moveLineEnd();
      // 'a😀' is 2 graphemes even though it's 3 UTF-16 code units.
      expect(controller.col, 2);
    });

    test('insert at cursor advances cursor by inserted grapheme count', () {
      final controller = TextEditingController(text: 'xy')..setCursor(0, 1);
      controller.insert('😀');
      expect(controller.text, 'x😀y');
      expect(controller.col, 2);
    });
  });
}
