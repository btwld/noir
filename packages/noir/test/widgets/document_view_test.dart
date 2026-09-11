import 'package:noir/noir.dart';
import 'package:noir/src/widgets/document_view.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

const _fill = Color(0.5, 0.1, 0.1);

void main() {
  test('row backgrounds map a blank line that follows a wrapped line', () {
    final capture = BufferCapture(width: 5, height: 4);
    addTearDown(capture.dispose);
    const text = 'aaaa bbbb\n\ncc';

    final frame = capture.capture(
      const DocumentView(
        text: TextSpan(text: text),
        plainText: text,
        rowBackgrounds: <DocumentRowBackground>[
          // The blank source line, which lays out with no runs.
          DocumentRowBackground(start: 10, color: _fill),
          // The first glyph of the last line only.
          DocumentRowBackground(start: 11, end: 12, color: _fill),
        ],
      ),
    );

    final surface = ThemeData.dark.surface.toHex();
    expect(frame.toLines().take(4), <String>['aaaa', 'bbbb', '', 'cc']);
    expect(frame.getBackgroundColor(4, 0).toHex(), surface);
    expect(frame.getBackgroundColor(4, 1).toHex(), surface);
    expect(frame.getBackgroundColor(0, 2).toHex(), _fill.toHex());
    expect(frame.getBackgroundColor(4, 2).toHex(), _fill.toHex());
    expect(frame.getBackgroundColor(0, 3).toHex(), _fill.toHex());
    expect(frame.getBackgroundColor(1, 3).toHex(), surface);
  });

  test('row backgrounds start after the line-number gutter', () {
    final capture = BufferCapture(width: 8, height: 2);
    addTearDown(capture.dispose);
    const text = 'ab\ncd';

    final frame = capture.capture(
      const DocumentView(
        text: TextSpan(text: text),
        plainText: text,
        showLineNumbers: true,
        rowBackgrounds: <DocumentRowBackground>[
          DocumentRowBackground(start: 3, color: _fill),
        ],
      ),
    );

    final surface = ThemeData.dark.surface.toHex();
    expect(frame.toLines().take(2), <String>[' 1 ab', ' 2 cd']);
    expect(frame.getBackgroundColor(7, 0).toHex(), surface);
    expect(frame.getBackgroundColor(0, 1).toHex(), surface);
    expect(frame.getBackgroundColor(2, 1).toHex(), surface);
    expect(frame.getBackgroundColor(3, 1).toHex(), _fill.toHex());
    expect(frame.getBackgroundColor(7, 1).toHex(), _fill.toHex());
  });
}
