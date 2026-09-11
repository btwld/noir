import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('RenderParagraph records TextLayout instead of owning TextBuffer', () {
    final source = File('lib/src/rendering/paragraph.dart').readAsStringSync();

    expect(source, isNot(contains("import '../core/text_buffer.dart';")));
    expect(source, isNot(contains('TextBuffer')));
    expect(source, contains('TextLayout'));
    expect(source, contains('drawTextLayout'));
  });
}
