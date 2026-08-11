/// Terminal-cell width tables and helpers for grapheme clusters.
///
/// Cell widths follow the common terminal convention:
/// - Most characters occupy 1 cell.
/// - CJK ideographs, fullwidth ASCII forms, and common emoji occupy 2 cells.
/// - Zero-width control characters and combining marks within a cluster do not
///   contribute extra width — the cluster width is determined by its base
///   character.
///
/// The classification is intentionally simple and does not try to perfectly
/// emulate `wcwidth`. The OpenTUI text engine handles the precise per-cell
/// layout when it draws to the buffer; this helper is for editing and
/// cursor math in widget State where we need a quick, dependency-free
/// approximation.
library;

import 'package:characters/characters.dart';

/// Returns the terminal cell width of a single grapheme cluster.
///
/// `cluster` should be a single grapheme cluster (as produced by
/// `Characters(str).first`); callers that pass arbitrary strings get the
/// width of the first cluster only.
int terminalCellWidth(String cluster) {
  if (cluster.isEmpty) return 0;
  final iter = cluster.characters.iterator;
  if (!iter.moveNext()) return 0;
  final first = iter.current;
  // The base code point of the cluster decides the cell width; combining
  // marks attach without adding cells.
  final runes = first.runes.iterator;
  if (!runes.moveNext()) return 0;
  final base = runes.current;
  return _isWide(base) ? 2 : 1;
}

/// Returns the terminal cell width of [text] by summing the width of each
/// grapheme cluster.
int terminalStringWidth(String text) {
  if (text.isEmpty) return 0;
  var width = 0;
  for (final cluster in text.characters) {
    width += terminalCellWidth(cluster);
  }
  return width;
}

/// True if [codePoint] is rendered as a wide (2-cell) character in typical
/// terminal fonts. Uses a small inline range table covering CJK, common
/// fullwidth blocks, and emoji ranges used by text layout.
bool _isWide(int codePoint) {
  // Fast bail for ASCII / Latin-1.
  if (codePoint < 0x1100) return false;
  return (codePoint >= 0x1100 && codePoint <= 0x115F) || // Hangul Jamo
      (codePoint >= 0x2E80 && codePoint <= 0x303E) || // CJK Radicals
      (codePoint >= 0x3041 && codePoint <= 0x33FF) || // Kana, CJK symbols
      (codePoint >= 0x3400 && codePoint <= 0x4DBF) || // CJK Extension A
      (codePoint >= 0x4E00 && codePoint <= 0x9FFF) || // CJK Unified
      (codePoint >= 0xA000 && codePoint <= 0xA4CF) || // Yi
      (codePoint >= 0xAC00 && codePoint <= 0xD7A3) || // Hangul Syllables
      (codePoint >= 0xF900 && codePoint <= 0xFAFF) || // CJK Compat Ideographs
      (codePoint >= 0xFE30 && codePoint <= 0xFE4F) || // CJK Compat Forms
      (codePoint >= 0xFF00 && codePoint <= 0xFF60) || // Fullwidth ASCII
      (codePoint >= 0xFFE0 && codePoint <= 0xFFE6) || // Fullwidth Signs
      (codePoint >= 0x1F300 && codePoint <= 0x1F64F) || // Misc Symbols & Emoji
      (codePoint >= 0x1F900 && codePoint <= 0x1F9FF) || // Supplemental Symbols
      (codePoint >= 0x1FA70 && codePoint <= 0x1FAFF); // Symbols & Pictographs
}

/// Slice [text] to fit within [maxCells] terminal cells starting from the
/// beginning, respecting grapheme cluster boundaries. A wide cluster that
/// would push the result past [maxCells] is dropped entirely (we never paint
/// a "half" wide cluster).
String sliceByCells(String text, int maxCells) {
  if (maxCells <= 0 || text.isEmpty) return '';
  final buf = StringBuffer();
  var used = 0;
  for (final cluster in text.characters) {
    final w = terminalCellWidth(cluster);
    if (used + w > maxCells) break;
    buf.write(cluster);
    used += w;
  }
  return buf.toString();
}

/// Cell-column position of grapheme [index] within [text] (assuming `text`
/// is laid out left-to-right with each cluster taking [terminalCellWidth]
/// cells). Equivalent to `terminalStringWidth(text up to grapheme #index)`.
int graphemeIndexToCell(String text, int index) {
  if (index <= 0 || text.isEmpty) return 0;
  var used = 0;
  var seen = 0;
  for (final cluster in text.characters) {
    if (seen >= index) break;
    used += terminalCellWidth(cluster);
    seen++;
  }
  return used;
}

/// Inverse of [graphemeIndexToCell]: given a column offset in cells, return
/// the grapheme index that starts at or just before that column. Used by
/// click-to-cursor mapping.
int cellToGraphemeIndex(String text, int cell) {
  if (cell <= 0 || text.isEmpty) return 0;
  var used = 0;
  var index = 0;
  for (final cluster in text.characters) {
    final w = terminalCellWidth(cluster);
    if (used + w > cell) break;
    used += w;
    index++;
  }
  return index;
}
