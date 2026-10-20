import 'package:meta/meta.dart';

/// A range of text represented with UTF-16 offsets.
@immutable
class TextRange {
  /// Creates a text range from [start] to [end].
  const TextRange({required this.start, required this.end});

  /// Creates a collapsed range at [offset].
  const TextRange.collapsed(int offset) : start = offset, end = offset;

  /// An invalid empty range.
  static const TextRange empty = TextRange(start: -1, end: -1);

  /// The UTF-16 offset before the first selected code unit.
  final int start;

  /// The UTF-16 offset after the last selected code unit.
  final int end;

  /// Whether this range has non-negative endpoints.
  bool get isValid => start >= 0 && end >= 0;

  /// Whether this range contains no text.
  bool get isCollapsed => start == end;

  /// Text inside this range.
  String textInside(String text) => text.substring(start, end);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextRange &&
          other.runtimeType == runtimeType &&
          other.start == start &&
          other.end == end;

  @override
  int get hashCode => Object.hash(runtimeType, start, end);

  @override
  String toString() => 'TextRange(start: $start, end: $end)';
}
