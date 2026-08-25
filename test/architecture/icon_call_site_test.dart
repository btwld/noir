import 'dart:io';

import 'package:test/test.dart';

/// Guards the authoring contract at the call sites, not just inside [Icons].
///
/// `icon_width_class_test.dart` proves the catalog itself is emoji-free, but
/// nothing stopped a widget from writing a raw `Text('▶')` and reintroducing
/// the exact defect the catalog exists to prevent. A character carrying the
/// Unicode `Emoji` property renders at double width through an emoji fallback
/// font in ordinary, correctly configured terminals — not only in the
/// ambiguous-doubling configuration — so a glyph literal that carries it is a
/// layout bug wherever it is painted.
///
/// Doc comments are exempt: `icons.dart` and `checkbox.dart` name the excluded
/// characters on purpose, and naming them is how the rule stays legible.
void main() {
  test('no authored source paints a character with the Emoji property', () {
    final violations = <String>[];

    for (final file in _authoredDartFiles()) {
      final path = file.path;
      var inBlockComment = false;
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        final trimmed = line.trim();
        if (inBlockComment) {
          if (trimmed.contains('*/')) inBlockComment = false;
          continue;
        }
        if (trimmed.startsWith('/*')) {
          if (!trimmed.contains('*/')) inBlockComment = true;
          continue;
        }
        if (trimmed.startsWith('//')) continue;
        for (final codePoint in line.runes) {
          if (codePoint < 0x80) continue;
          if (!_contains(_emojiPropertyRanges, codePoint)) continue;
          violations.add(
            '$path:${index + 1} '
            'U+${codePoint.toRadixString(16).toUpperCase().padLeft(4, '0')} '
            "'${String.fromCharCode(codePoint)}' in ${trimmed.trim()}",
          );
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'These characters carry the Unicode Emoji property and terminals '
          'widen them through an emoji fallback font. Take the glyph from '
          'Icons instead, which is emoji-free by construction.\n'
          '${violations.join('\n')}',
    );
  });
}

/// Every authored Dart file that can paint a glyph. Generated FFI bindings are
/// excluded because they are machine-written and paint nothing.
Iterable<File> _authoredDartFiles() sync* {
  const generated = <String>{
    'lib/src/ffi/generated_bindings.dart',
    'lib/src/ffi/native_asset_bindings.dart',
  };
  for (final root in const ['lib', 'example']) {
    for (final entry in Directory(root).listSync(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.dart')) continue;
      if (generated.contains(entry.path.replaceAll(r'\\', '/'))) continue;
      yield entry;
    }
  }
}

bool _contains(List<int> ranges, int codePoint) {
  var low = 0;
  var high = ranges.length ~/ 2 - 1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    if (codePoint < ranges[middle * 2]) {
      high = middle - 1;
    } else if (codePoint > ranges[middle * 2 + 1]) {
      low = middle + 1;
    } else {
      return true;
    }
  }
  return false;
}

// Generated from Unicode 17.0 emoji-data.txt (Emoji property), BMP only.
// Do not edit range values by hand.
const _emojiPropertyRanges = <int>[
  0x00A9,
  0x00A9,
  0x00AE,
  0x00AE,
  0x203C,
  0x203C,
  0x2049,
  0x2049,
  0x2122,
  0x2122,
  0x2139,
  0x2139,
  0x2194,
  0x2199,
  0x21A9,
  0x21AA,
  0x231A,
  0x231B,
  0x2328,
  0x2328,
  0x23CF,
  0x23CF,
  0x23E9,
  0x23F3,
  0x23F8,
  0x23FA,
  0x24C2,
  0x24C2,
  0x25AA,
  0x25AB,
  0x25B6,
  0x25B6,
  0x25C0,
  0x25C0,
  0x25FB,
  0x25FE,
  0x2600,
  0x2604,
  0x260E,
  0x260E,
  0x2611,
  0x2611,
  0x2614,
  0x2615,
  0x2618,
  0x2618,
  0x261D,
  0x261D,
  0x2620,
  0x2620,
  0x2622,
  0x2623,
  0x2626,
  0x2626,
  0x262A,
  0x262A,
  0x262E,
  0x262F,
  0x2638,
  0x263A,
  0x2640,
  0x2640,
  0x2642,
  0x2642,
  0x2648,
  0x2653,
  0x265F,
  0x2660,
  0x2663,
  0x2663,
  0x2665,
  0x2666,
  0x2668,
  0x2668,
  0x267B,
  0x267B,
  0x267E,
  0x267F,
  0x2692,
  0x2697,
  0x2699,
  0x2699,
  0x269B,
  0x269C,
  0x26A0,
  0x26A1,
  0x26A7,
  0x26A7,
  0x26AA,
  0x26AB,
  0x26B0,
  0x26B1,
  0x26BD,
  0x26BE,
  0x26C4,
  0x26C5,
  0x26C8,
  0x26C8,
  0x26CE,
  0x26CF,
  0x26D1,
  0x26D1,
  0x26D3,
  0x26D4,
  0x26E9,
  0x26EA,
  0x26F0,
  0x26F5,
  0x26F7,
  0x26FA,
  0x26FD,
  0x26FD,
  0x2702,
  0x2702,
  0x2705,
  0x2705,
  0x2708,
  0x270D,
  0x270F,
  0x270F,
  0x2712,
  0x2712,
  0x2714,
  0x2714,
  0x2716,
  0x2716,
  0x271D,
  0x271D,
  0x2721,
  0x2721,
  0x2728,
  0x2728,
  0x2733,
  0x2734,
  0x2744,
  0x2744,
  0x2747,
  0x2747,
  0x274C,
  0x274C,
  0x274E,
  0x274E,
  0x2753,
  0x2755,
  0x2757,
  0x2757,
  0x2763,
  0x2764,
  0x2795,
  0x2797,
  0x27A1,
  0x27A1,
  0x27B0,
  0x27B0,
  0x27BF,
  0x27BF,
  0x2934,
  0x2935,
  0x2B05,
  0x2B07,
  0x2B1B,
  0x2B1C,
  0x2B50,
  0x2B50,
  0x2B55,
  0x2B55,
  0x3030,
  0x3030,
  0x303D,
  0x303D,
  0x3297,
  0x3297,
  0x3299,
  0x3299,
];
