import 'package:meta/meta.dart';

import 'text_selection.dart';

/// Immutable text editing state: text and selection.
@immutable
class TextEditingValue {
  /// Creates a text editing value.
  const TextEditingValue({
    this.text = '',
    this.selection = const TextSelection.collapsed(offset: -1),
  });

  /// The current text.
  final String text;

  /// The current selection.
  final TextSelection selection;

  /// Returns a copy of this value with the given fields replaced.
  TextEditingValue copyWith({String? text, TextSelection? selection}) =>
      TextEditingValue(
        text: text ?? this.text,
        selection: selection ?? this.selection,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextEditingValue &&
          other.text == text &&
          other.selection == selection;

  @override
  int get hashCode => Object.hash(text, selection);

  @override
  String toString() => 'TextEditingValue(text: $text, selection: $selection)';
}
