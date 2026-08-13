import 'package:noir/src/core/color.dart';
import 'package:noir/src/core/renderer.dart';
import 'package:noir/src/core/terminal_style.dart';
import 'package:noir/src/painting/tui_canvas.dart';
import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/text_highlight.dart';
import 'package:noir/src/widgets/text_layout.dart';
import 'package:noir/src/widgets/text_span.dart';
import 'package:noir/src/widgets/text_style.dart';
import 'package:test/test.dart';

void main() {
  test('TuiCanvas records and encodes draw commands into a buffer', () {
    final renderer = Renderer.create(8, 3, testing: true);
    final buffer = renderer.nextBuffer;
    addTearDown(renderer.dispose);

    final canvas = createTuiCanvas()
      ..fillRect(const Rect.fromLTWH(0, 0, 8, 3), Color.blue)
      ..drawText('Hi', const Offset(1, 1), Color.yellow)
      ..setCell(const Offset(4, 1), '!', Color.green, Color.red, 0);

    commitTuiCanvas(buffer, canvas);

    final direct = buffer.getDirectAccess();
    expect(direct.getBackground(0, 0), Color.blue);
    expect(direct.getChar(1, 1), 'H');
    expect(direct.getForeground(1, 1), Color.yellow);
    expect(direct.getChar(4, 1), '!');
    expect(direct.getForeground(4, 1), Color.green);
    expect(direct.getBackground(4, 1), Color.red);
  });

  test('TuiCanvas clips encoded commands with save and restore', () {
    final renderer = Renderer.create(6, 2, testing: true);
    final buffer = renderer.nextBuffer;
    addTearDown(renderer.dispose);

    final canvas = createTuiCanvas()
      ..save()
      ..clipRect(const Rect.fromLTWH(1, 0, 3, 2))
      ..drawText('ABCDE', Offset.zero, Color.white)
      ..restore()
      ..setCell(const Offset(5, 0), 'Z', Color.green, Color.black, 0);

    commitTuiCanvas(buffer, canvas);

    final direct = buffer.getDirectAccess();
    expect(direct.getChar(0, 0), ' ');
    expect(direct.getChar(1, 0), 'B');
    expect(direct.getChar(2, 0), 'C');
    expect(direct.getChar(3, 0), 'D');
    expect(direct.getChar(4, 0), ' ');
    expect(direct.getChar(5, 0), 'Z');
  });

  test('TuiCanvas encodes text layouts with styles and selection', () {
    final renderer = Renderer.create(8, 2, testing: true);
    final buffer = renderer.nextBuffer;
    addTearDown(renderer.dispose);

    final layout = const TextLayoutEngine().layout(
      const TextSpan(
        children: [
          TextSpan(
            text: 'A',
            style: TextStyle(color: Color.red),
          ),
          TextSpan(
            text: 'B',
            style: TextStyle(color: Color.green, attributes: Attr.bold),
          ),
          TextSpan(
            text: 'C',
            style: TextStyle(color: Color.yellow),
          ),
        ],
      ),
      const BoxConstraints(maxWidth: 8, maxHeight: 2),
    );
    final canvas = createTuiCanvas()
      ..drawTextLayout(
        layout,
        Offset.zero,
        selection: const TextHighlight(
          start: 1,
          end: 2,
          foregroundColor: Color.black,
          backgroundColor: Color.blue,
        ),
      );

    commitTuiCanvas(buffer, canvas);

    final direct = buffer.getDirectAccess();
    expect(direct.getChar(0, 0), 'A');
    expect(direct.getForeground(0, 0), Color.red);
    expect(direct.getChar(1, 0), 'B');
    expect(direct.getForeground(1, 0), Color.black);
    expect(direct.getBackground(1, 0), Color.blue);
    expect(direct.getAttributes(1, 0), Attr.bold);
    expect(direct.getChar(2, 0), 'C');
    expect(direct.getForeground(2, 0), Color.yellow);
  });

  test('TuiCanvas encodes text layout source clips with Unicode text', () {
    final renderer = Renderer.create(8, 2, testing: true);
    final buffer = renderer.nextBuffer;
    addTearDown(renderer.dispose);

    final layout = const TextLayoutEngine().layout(
      const TextSpan(text: 'AéC'),
      const BoxConstraints(maxWidth: 8, maxHeight: 2),
    );
    final canvas = createTuiCanvas()
      ..drawTextLayout(
        layout,
        Offset.zero,
        sourceRect: const Rect.fromLTWH(1, 0, 2, 1),
      );

    commitTuiCanvas(buffer, canvas);

    final direct = buffer.getDirectAccess();
    expect(_isPackedGraphemeStart(direct.getEncodedCellAt(0)), isTrue);
    expect(direct.getChar(1, 0), 'C');
    expect(direct.getChar(2, 0), ' ');
  });

  test('text-layout painter preserves wide graphemes and selection styles', () {
    final renderer = Renderer.create(8, 2, testing: true);
    final buffer = renderer.nextBuffer;
    addTearDown(renderer.dispose);

    final layout = const TextLayoutEngine().layout(
      const TextSpan(text: 'A👩‍💻中B'),
      const BoxConstraints(maxWidth: 8, maxHeight: 2),
    );
    final canvas = createTuiCanvas()
      ..drawTextLayout(
        layout,
        Offset.zero,
        selection: const TextHighlight(
          start: 1,
          end: 6,
          foregroundColor: Color.black,
          backgroundColor: Color.blue,
        ),
      );

    commitTuiCanvas(buffer, canvas);

    final direct = buffer.getDirectAccess();
    expect(direct.getChar(0, 0), 'A');
    expect(_isPackedGraphemeStart(direct.getEncodedCellAt(1)), isTrue);
    expect(_isPackedContinuation(direct.getEncodedCellAt(2)), isTrue);
    expect(direct.getForeground(1, 0), Color.black);
    expect(direct.getBackground(1, 0), Color.blue);
    expect(_isPackedGraphemeStart(direct.getEncodedCellAt(3)), isTrue);
    expect(_isPackedContinuation(direct.getEncodedCellAt(4)), isTrue);
    expect(direct.getChar(5, 0), 'B');
  });

  test('source clipping drops a wide grapheme that crosses the clip edge', () {
    final renderer = Renderer.create(8, 2, testing: true);
    final buffer = renderer.nextBuffer;
    addTearDown(renderer.dispose);

    final layout = const TextLayoutEngine().layout(
      const TextSpan(text: 'A👩‍💻中B'),
      const BoxConstraints(maxWidth: 8, maxHeight: 2),
    );
    final canvas = createTuiCanvas()
      ..drawTextLayout(
        layout,
        Offset.zero,
        sourceRect: const Rect.fromLTWH(2, 0, 4, 1),
      );

    commitTuiCanvas(buffer, canvas);

    final direct = buffer.getDirectAccess();
    expect(direct.getChar(0, 0), ' ');
    expect(_isPackedGraphemeStart(direct.getEncodedCellAt(1)), isTrue);
    expect(_isPackedContinuation(direct.getEncodedCellAt(2)), isTrue);
    expect(direct.getChar(3, 0), 'B');
  });
}

bool _isPackedGraphemeStart(int code) => (code & 0xC0000000) == 0x80000000;

bool _isPackedContinuation(int code) => (code & 0xC0000000) == 0xC0000000;
