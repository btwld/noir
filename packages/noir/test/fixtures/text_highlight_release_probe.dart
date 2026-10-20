import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';

/// Assertions-disabled probe for [TextHighlight] range checks.
void main() {
  _expectArgumentError('construct-negative', () {
    RenderParagraph(
      text: const TextSpan(text: 'hello'),
      selection: TextHighlight(start: -1, end: 2),
    );
  });
  _expectArgumentError('construct-reversed', () {
    RenderParagraph(
      text: const TextSpan(text: 'hello'),
      selection: TextHighlight(start: 3, end: 1),
    );
  });

  final paragraph = RenderParagraph(
    text: const TextSpan(text: 'hello'),
    selection: const TextHighlight(start: 0, end: 2),
  );
  _expectArgumentError('setter-negative', () {
    paragraph.selection = TextHighlight(start: -1, end: 4);
  });
  _expectRetained('setter-negative', paragraph, 0, 2);
  _expectArgumentError('setter-reversed', () {
    paragraph.selection = TextHighlight(start: 4, end: 1);
  });
  _expectRetained('setter-reversed', paragraph, 0, 2);

  paragraph.selection = const TextHighlight(start: 1, end: 4);
  _expectRetained('valid-selection', paragraph, 1, 4);
  print('PASS:valid-selection');
}

void _expectArgumentError(String label, void Function() action) {
  Object? error;
  try {
    action();
  } catch (caught) {
    error = caught;
  }
  if (error is! ArgumentError) {
    throw StateError('$label did not throw ArgumentError: $error');
  }
  print('PASS:$label');
}

void _expectRetained(
  String label,
  RenderParagraph paragraph,
  int start,
  int end,
) {
  final selection = paragraph.selection;
  if (selection == null || selection.start != start || selection.end != end) {
    throw StateError('$label replaced the retained highlight: $selection');
  }
}
