import 'text_style.dart';

/// Base class for inline text content.
abstract class InlineSpan {
  /// Creates an inline span.
  const InlineSpan();

  /// Appends plain text to [buffer].
  void computePlainText(StringBuffer buffer);
}

/// A text span with optional children.
final class TextSpan extends InlineSpan {
  /// Creates a text span.
  const TextSpan({this.text, this.style, this.children = const <InlineSpan>[]});

  /// Text content for this span.
  final String? text;

  /// Style for this span and unstyled descendants.
  final TextStyle? style;

  /// Child spans.
  final List<InlineSpan> children;

  @override
  void computePlainText(StringBuffer buffer) {
    final value = text;
    if (value != null) {
      buffer.write(value);
    }
    for (final child in children) {
      child.computePlainText(buffer);
    }
  }

  /// Returns all text in this span tree.
  ///
  /// Flutter-parity member; kept for API parity — see Flutter's
  /// `TextSpan.toPlainText`.
  String toPlainText() {
    final buffer = StringBuffer();
    computePlainText(buffer);
    return buffer.toString();
  }
}
