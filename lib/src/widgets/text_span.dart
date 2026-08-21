import 'package:meta/meta.dart';

import 'text_style.dart';

/// Base class for inline text content.
abstract class InlineSpan {
  /// Creates an inline span.
  const InlineSpan();

  /// Appends plain text to [buffer].
  void computePlainText(StringBuffer buffer);

  /// Returns all plain text in this span tree.
  String toPlainText() {
    final buffer = StringBuffer();
    computePlainText(buffer);
    return buffer.toString();
  }
}

/// A text span with optional children.
final class TextSpan extends InlineSpan {
  /// Creates a text span.
  const TextSpan({
    this.text,
    this.style,
    this.uri,
    this.children = const <InlineSpan>[],
  });

  /// Text content for this span.
  final String? text;

  /// Style for this span and unstyled descendants.
  final TextStyle? style;

  /// Semantic hyperlink inherited by unlinked descendants.
  final Uri? uri;

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
}

/// Creates an owned recursive snapshot for a long-lived rendering boundary.
@internal
InlineSpan snapshotInlineSpan(InlineSpan span) {
  if (span is TextSpan) {
    return TextSpan(
      text: span.text,
      style: span.style,
      uri: span.uri,
      children: List<InlineSpan>.unmodifiable(
        span.children.map(snapshotInlineSpan),
      ),
    );
  }
  return TextSpan(text: span.toPlainText());
}
