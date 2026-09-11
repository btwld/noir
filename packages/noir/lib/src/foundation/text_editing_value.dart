import 'package:meta/meta.dart';

import 'text_range.dart';
import 'text_selection.dart';

/// Immutable text editing state: text, selection, and composing range.
@immutable
class TextEditingValue {
  /// Creates a text editing value.
  const TextEditingValue({
    this.text = '',
    this.selection = const TextSelection.collapsed(offset: -1),
    this.composing = TextRange.empty,
  });

  /// The current text.
  final String text;

  /// The current selection.
  final TextSelection selection;

  /// The active composing range.
  final TextRange composing;

  /// Returns a copy of this value with the given fields replaced.
  TextEditingValue copyWith({
    String? text,
    TextSelection? selection,
    TextRange? composing,
  }) => TextEditingValue(
    text: text ?? this.text,
    selection: selection ?? this.selection,
    composing: composing ?? this.composing,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextEditingValue &&
          other.text == text &&
          other.selection == selection &&
          other.composing == composing;

  @override
  int get hashCode => Object.hash(text, selection, composing);

  @override
  String toString() =>
      'TextEditingValue(text: $text, selection: $selection, '
      'composing: $composing)';
}
