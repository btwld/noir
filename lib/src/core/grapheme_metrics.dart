/// Terminal-cell width helpers for grapheme clusters.
///
/// Width follows the pinned OpenTUI v0.5.1 Unicode algorithm so layout, direct
/// painting, selection, clipping, and cursor math share its cell placement
/// without crossing the native boundary during widget work.
library;

import 'package:characters/characters.dart';

import 'unicode_width_table.dart';

/// Returns the terminal cell width of a single grapheme cluster.
///
/// `cluster` should be a single grapheme cluster (as produced by
/// `Characters(str).first`); callers that pass arbitrary strings get the
/// width of the first cluster only.
int terminalCellWidth(String cluster) {
  if (cluster.isEmpty) return 0;
  final iter = cluster.characters.iterator;
  if (!iter.moveNext()) return 0;
  final runes = iter.current.runes.iterator;
  if (!runes.moveNext()) return 0;

  final first = runes.current;
  var width = _openTuiCodePointWidth(first);
  var hasWidth = width > 0;
  final regionalIndicatorPair = _isRegionalIndicator(first);
  var hasIndicMark = false;

  while (runes.moveNext()) {
    final codePoint = runes.current;
    final codePointWidth = _openTuiCodePointWidth(codePoint);

    if (codePoint == 0xFE0F) {
      if (hasWidth && width == 1) width = 2;
      continue;
    }

    if (_isDevanagariNonspacingMark(codePoint)) {
      hasIndicMark = true;
      continue;
    }

    if (regionalIndicatorPair && _isRegionalIndicator(codePoint)) {
      width += codePointWidth;
      hasWidth = true;
    } else if (!hasWidth && codePointWidth > 0) {
      width = codePointWidth;
      hasWidth = true;
    } else if (hasWidth &&
        hasIndicMark &&
        _isDevanagariBase(codePoint) &&
        codePointWidth > 0) {
      if (codePoint != 0x0930) width += codePointWidth;
      hasIndicMark = false;
    }
  }
  return width;
}

int _openTuiCodePointWidth(int codePoint) =>
    openTuiCodePointWidthFromTable(codePoint);

bool _isRegionalIndicator(int codePoint) =>
    codePoint >= 0x1F1E6 && codePoint <= 0x1F1FF;

bool _isDevanagariBase(int codePoint) =>
    (codePoint >= 0x0915 && codePoint <= 0x0939) ||
    (codePoint >= 0x0958 && codePoint <= 0x095F);

bool _isDevanagariNonspacingMark(int codePoint) =>
    (codePoint >= 0x0900 && codePoint <= 0x0902) ||
    codePoint == 0x093A ||
    codePoint == 0x093C ||
    (codePoint >= 0x0941 && codePoint <= 0x0948) ||
    codePoint == 0x094D ||
    (codePoint >= 0x0951 && codePoint <= 0x0957) ||
    (codePoint >= 0x0962 && codePoint <= 0x0963);

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
