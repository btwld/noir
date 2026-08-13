import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

void main() {
  test('Border and BoxOptions snapshot custom character tables', () {
    final source = List<int>.generate(11, (index) => index + 1);
    final border = Border.all(borderChars: source);
    final options = BoxOptions(borderChars: source);
    final borderHash = border.hashCode;

    source[0] = 999;

    expect(border.borderChars!.first, 1);
    expect(options.borderChars!.first, 1);
    expect(border.hashCode, borderHash);
    expect(() => border.borderChars![0] = 2, throwsUnsupportedError);
    expect(() => options.borderChars![0] = 2, throwsUnsupportedError);
  });

  test('Border and BoxOptions reject malformed character tables', () {
    for (final length in <int>[0, 10, 12]) {
      final source = List<int>.filled(length, 0x2500);
      expect(() => Border.all(borderChars: source), throwsArgumentError);
      expect(() => BoxOptions(borderChars: source), throwsArgumentError);
    }
  });

  test('TextStyle decorations are immutable composable values', () {
    final decoration = TextDecoration.combine([
      TextDecoration.underline,
      TextDecoration.lineThrough,
    ]);
    final style = TextStyle(decoration: decoration);

    expect(style.computedAttributes & Attr.underline, isNot(0));
    expect(style.computedAttributes & Attr.strike, isNot(0));
  });

  test('TextLayout snapshots lines and line runs', () {
    const run = TextLayoutRun(
      text: 'a',
      style: TextStyle(),
      sourceStart: 0,
      sourceEnd: 1,
    );
    final runs = <TextLayoutRun>[run];
    final line = TextLayoutLine(runs: runs, width: 1);
    final lines = <TextLayoutLine>[line];
    final layout = TextLayout(
      text: 'a',
      style: const TextStyle(),
      indexMap: TextIndexMap('a'),
      lines: lines,
      size: const Size(1, 1),
    );

    runs.clear();
    lines.clear();

    expect(layout.lines, hasLength(1));
    expect(layout.lines.single.runs, hasLength(1));
    expect(layout.lines.clear, throwsUnsupportedError);
    expect(line.runs.clear, throwsUnsupportedError);
  });

  test('RenderParagraph snapshots a caller-owned span tree', () {
    final children = <InlineSpan>[const TextSpan(text: 'before')];
    final span = TextSpan(children: children);
    final paragraph = RenderParagraph(text: span);

    children[0] = const TextSpan(text: 'after');
    paragraph.layout(const BoxConstraints.tight(width: 20, height: 1));

    expect(paragraph.debugTextLayout!.text, 'before');

    paragraph.text = span;
    paragraph.layout(const BoxConstraints.tight(width: 20, height: 1));
    expect(paragraph.debugTextLayout!.text, 'after');
  });
}
