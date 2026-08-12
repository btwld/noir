// ignore_for_file: cascade_invocations
import 'dart:convert';
import 'dart:io';

import 'package:noir/noir.dart';
import 'package:noir/src/core/unicode_width_table.dart';
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

    test('matches canonical Unicode clusters used by pinned OpenTUI', () {
      expect(terminalCellWidth('\t'), 2, reason: 'OpenTUI tab width is 2');
      expect(
        terminalCellWidth('\u200B'),
        0,
        reason: 'retain source semantics despite native leading-run bug',
      );
      expect(terminalCellWidth('🇺🇸'), 2);
      expect(terminalCellWidth('1️⃣'), 2);
      expect(terminalCellWidth('❤️'), 2);
      expect(terminalCellWidth('👩‍🚀'), 2);
      expect(terminalCellWidth('क्त'), 2);
      expect(terminalCellWidth('क्‍ष'), 2);
      expect(terminalStringWidth('नमस्ते'), 4);
    });

    test('matches native v0.5.1 widths outside the sparse upstream map', () {
      const nativeDerivedWidths = <int, int>{
        0x061C: 1, // ARABIC LETTER MARK (Cf)
        0x200E: 1, // LEFT-TO-RIGHT MARK (Cf)
        0x1161: 1, // HANGUL JUNGSEONG A (Lo)
        0xE0020: 1, // TAG SPACE (Cf)
        0x3164: 2, // HANGUL FILLER
        0x31E4: 2, // CJK STROKE Q
        0x4DC0: 2, // HEXAGRAM FOR THE CREATIVE HEAVEN
        0x1D300: 2, // MONOGRAM FOR EARTH
        0x1FA89: 2, // FIGHT CLOUD
      };

      for (final MapEntry(key: codePoint, value: expected)
          in nativeDerivedWidths.entries) {
        expect(
          terminalCellWidth(String.fromCharCode(codePoint)),
          expected,
          reason:
              'official OpenTUI v0.5.1 encodeUnicode U+'
              '${codePoint.toRadixString(16).toUpperCase()}',
        );
      }
    });

    test('wide membership matches every official v0.5.1 scalar result', () {
      final oracle =
          jsonDecode(
                File(
                  'test/fixtures/opentui_v051_scalar_widths.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(oracle['validScalarCount'], 1112064);
      expect(
        (oracle['opentui']! as Map<String, Object?>)['sha256'],
        '196d4994f8ff02a2b8c6e5581eadf315040ff8cfdb487791a7f7ec01669ee10f',
      );

      final expectedWide = <int>{};
      for (final range in oracle['width2Ranges']! as List<Object?>) {
        final endpoints = range! as List<Object?>;
        final start = int.parse(
          (endpoints[0]! as String).substring(2),
          radix: 16,
        );
        final end = int.parse(
          (endpoints[1]! as String).substring(2),
          radix: 16,
        );
        for (var codePoint = start; codePoint <= end; codePoint++) {
          expectedWide.add(codePoint);
        }
      }

      for (var codePoint = 0; codePoint <= 0x10FFFF; codePoint++) {
        if (codePoint >= 0xD800 && codePoint <= 0xDFFF) continue;
        expect(
          openTuiCodePointWidthFromTable(codePoint) == 2,
          expectedWide.contains(codePoint),
          reason: 'U+${codePoint.toRadixString(16).toUpperCase()}',
        );
      }
    });

    test('matches the pinned OpenTUI code-point width map', () {
      final source = File(
        'external/opentui/packages/core/src/zig/tests/unicode-width-map.zon',
      ).readAsStringSync();
      final entries = RegExp(
        r'codepoint = "U\+([0-9A-F]+)", \.width = (-?\d+)',
      ).allMatches(source);

      expect(entries.length, greaterThan(3900));
      for (final entry in entries) {
        final codePoint = int.parse(entry.group(1)!, radix: 16);
        final expected = int.parse(entry.group(2)!);
        expect(
          terminalCellWidth(String.fromCharCode(codePoint)),
          expected,
          reason: 'U+${codePoint.toRadixString(16).toUpperCase()}',
        );
      }
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
