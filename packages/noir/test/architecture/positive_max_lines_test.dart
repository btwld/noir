import 'dart:io';

import 'package:test/test.dart';

void main() {
  final paragraph = File('lib/src/rendering/paragraph.dart').readAsStringSync();
  final text = File('lib/src/widgets/text.dart').readAsStringSync();
  final rich = File('lib/src/widgets/rich_text.dart').readAsStringSync();

  test('no non-positive-as-unlimited maxLines branch remains', () {
    expect(paragraph, isNot(contains('_maxLines! <= 0')));
    expect(paragraph, isNot(contains('_maxLines <= 0')));
    expect(paragraph, contains('_maxLines ?? layout.lineCount'));
    expect(paragraph, contains('_validatedMaxLines'));
  });

  test('widgets assert positive-or-null maxLines', () {
    expect(text, contains('maxLines == null || maxLines > 0'));
    expect(rich, contains('maxLines == null || maxLines > 0'));
  });

  test('widget updates validate maxLines before other render props', () {
    for (final source in [text, rich]) {
      final updateStart = source.indexOf('void updateRenderObject');
      expect(updateStart, greaterThan(0));
      final body = source.substring(updateStart);
      final maxLinesAssign = body.indexOf('maxLines = maxLines');
      final textAssign = body.indexOf('text =');
      expect(maxLinesAssign, greaterThan(0));
      expect(textAssign, greaterThan(maxLinesAssign));
    }
  });

  test('validation precedes storage in constructor and setter', () {
    expect(paragraph, contains('_maxLines = _validatedMaxLines(maxLines)'));
    expect(paragraph, contains('final validated = _validatedMaxLines(value)'));
    // Equality uses validated value, not the raw argument.
    expect(paragraph, contains('if (_maxLines == validated)'));
  });
}
