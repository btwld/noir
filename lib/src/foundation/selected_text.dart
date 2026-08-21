import 'package:meta/meta.dart';

import 'text_selection.dart';

/// Immutable selection payload reported by selectable document widgets.
@immutable
final class SelectedText {
  /// Creates selected [text] paired with its UTF-16 [selection].
  const SelectedText({required this.selection, required this.text});

  /// UTF-16 source range and direction.
  final TextSelection selection;

  /// Plain source text covered by [selection].
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SelectedText &&
      other.selection == selection &&
      other.text == text;

  @override
  int get hashCode => Object.hash(selection, text);
}
