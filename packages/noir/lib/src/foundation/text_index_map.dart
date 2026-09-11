import 'package:characters/characters.dart';

/// Maps between UTF-16 code-unit offsets and grapheme indices for a single
/// immutable text snapshot.
final class TextIndexMap {
  /// Creates a text index map for [text].
  TextIndexMap(this.text) {
    var utf16 = 0;
    for (final cluster in text.characters) {
      _utf16Starts.add(utf16);
      utf16 += cluster.length;
    }
    _utf16Starts.add(utf16);
  }

  /// Source text.
  final String text;

  final List<int> _utf16Starts = <int>[];

  /// Number of grapheme clusters.
  int get graphemeCount => _utf16Starts.length - 1;

  /// Converts a UTF-16 code-unit offset to a grapheme index.
  int utf16ToGrapheme(int utf16Offset) =>
      _floorIndex(_utf16Starts, utf16Offset);

  /// Converts a grapheme index to a UTF-16 code-unit offset.
  int graphemeToUtf16(int graphemeIndex) =>
      _utf16Starts[graphemeIndex.clamp(0, graphemeCount)];

  int _floorIndex(List<int> starts, int offset) {
    final clamped = offset.clamp(0, starts.last);
    var low = 0;
    var high = starts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (starts[mid] <= clamped) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}
