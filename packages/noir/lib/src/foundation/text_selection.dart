import 'package:meta/meta.dart';

import 'text_range.dart';

/// Directional preference for a collapsed text selection at a line break.
enum TextAffinity {
  /// Positions the caret at the upstream (before) side of the adjacent boundary.
  upstream,

  /// Positions the caret at the downstream (after) side of the adjacent boundary.
  downstream,
}

/// A text selection represented with base and extent UTF-16 offsets.
@immutable
class TextSelection extends TextRange {
  /// Creates a text selection from [baseOffset] to [extentOffset].
  const TextSelection({
    required this.baseOffset,
    required this.extentOffset,
    this.affinity = TextAffinity.downstream,
    this.isDirectional = false,
  }) : super(
         start: baseOffset < extentOffset ? baseOffset : extentOffset,
         end: baseOffset < extentOffset ? extentOffset : baseOffset,
       );

  /// Creates a collapsed selection at [offset].
  const TextSelection.collapsed({
    required int offset,
    this.affinity = TextAffinity.downstream,
  }) : baseOffset = offset,
       extentOffset = offset,
       isDirectional = false,
       super.collapsed(offset);

  /// The fixed end of the selection.
  final int baseOffset;

  /// The moving end of the selection.
  final int extentOffset;

  /// Preference when this selection is collapsed at a soft boundary.
  final TextAffinity affinity;

  /// Whether the selection direction should be preserved.
  final bool isDirectional;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextSelection &&
          other.baseOffset == baseOffset &&
          other.extentOffset == extentOffset &&
          other.affinity == affinity &&
          other.isDirectional == isDirectional;

  @override
  int get hashCode =>
      Object.hash(baseOffset, extentOffset, affinity, isDirectional);

  @override
  String toString() =>
      'TextSelection(baseOffset: $baseOffset, extentOffset: $extentOffset, '
      'affinity: $affinity, isDirectional: $isDirectional)';
}
