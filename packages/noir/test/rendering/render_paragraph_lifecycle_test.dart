import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

void main() {
  group('RenderParagraph lifecycle', () {
    test('detach has no native text-buffer ownership to dispose', () {
      final paragraph = RenderParagraph(text: const TextSpan(text: 'hello'))
        ..layout(const BoxConstraints.tight(width: 10, height: 1));

      expect(paragraph.debugTextLayout, isNotNull);

      paragraph.detach();

      expect(paragraph.debugTextLayout, isNull);
    });
  });
}
