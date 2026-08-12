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

  /// Whether [start] is less than or equal to [end].
  bool get isNormalized => end >= start;

  /// Whether this range contains no text.
  bool get isCollapsed => start == end;

  /// Text before this range.
  ///
  /// Flutter-parity member; kept for API parity — see Flutter's
  /// `TextRange.textBefore`.
  String textBefore(String text) => text.substring(0, start);

  /// Text inside this range.
  String textInside(String text) => text.substring(start, end);

  /// Text after this range.
  ///
  /// Flutter-parity member; kept for API parity — see Flutter's
  /// `TextRange.textAfter`.
  String textAfter(String text) => text.substring(end);

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
