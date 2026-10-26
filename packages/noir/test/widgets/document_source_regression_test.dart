import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart'
    show RenderTextTable, TextLayoutEngine;
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';
import '../helpers/widget_tester.dart';

void main() {
  test('visual-line metadata preserves CRLF and empty-row UTF-16 ranges', () {
    final layout = const TextLayoutEngine().layout(
      const TextSpan(text: 'a\r\n\r\nb'),
      const BoxConstraints(),
    );
    expect(layout.lines.map((line) => line.sourceStart), [0, 3, 5]);
    expect(layout.lines.map((line) => line.sourceEnd), [1, 3, 6]);
  });

  test('character-wrapped table preserves whole cross-span graphemes', () {
    final capture = BufferCapture(width: 1, height: 2);
    addTearDown(capture.dispose);
    final frame = capture.capture(
      const TextTable(
        content: [
          [
            TextSpan(
              children: [
                TextSpan(
                  text: 'e',
                  style: TextStyle(color: Color.red),
                ),
                TextSpan(
                  text: '\u0301b',
                  style: TextStyle(color: Color.blue),
                ),
              ],
            ),
          ],
        ],
        showBorders: false,
        wrapMode: TextTableWrapMode.character,
      ),
    );
    expect(frame, BufferMatchers.hasCharAt(0, 0, 'e\u0301'));
    expect(frame, BufferMatchers.hasColorAt(0, 0, Color.red));
    expect(frame, BufferMatchers.hasCharAt(0, 1, 'b'));
    expect(frame, BufferMatchers.hasColorAt(0, 1, Color.blue));
  });

  test('CodeView numbers blank source rows', () {
    final capture = BufferCapture(width: 12, height: 3);
    addTearDown(capture.dispose);
    final frame = capture.capture(const CodeView(code: 'aa\n\nbb'));
    expect(frame.toLines(), [' 1 aa', ' 2', ' 3 bb']);
  });

  test(
    'blank source rows retain pointer and vertical selection offsets',
    () async {
      SelectedText? selected;
      final driver = KeyDriver(
        CodeView(
          code: 'aa\n\nbb',
          showLineNumbers: false,
          onSelectionChanged: (value) => selected = value,
        ),
        width: 12,
        height: 3,
        paintFrames: true,
      );
      addTearDown(driver.dispose);
      await driver.ready();

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 0,
          y: 1,
        ),
      );
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.up,
          button: MouseButton.left,
          x: 1,
          y: 2,
        ),
      );
      expect(selected?.selection.baseOffset, 3);
      expect(selected?.text, '\nb');

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 0,
          y: 0,
        ),
      );
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.up,
          button: MouseButton.left,
          x: 0,
          y: 0,
        ),
      );
      await driver.sendLogicalKey(
        LogicalKeyboardKey.arrowDown,
        modifiers: KeyModifiers.shift,
      );
      expect(selected?.text, 'aa\n');
      await driver.sendLogicalKey(
        LogicalKeyboardKey.arrowDown,
        modifiers: KeyModifiers.shift,
      );
      expect(selected?.text, 'aa\n\n');
    },
  );

  for (final mode in TextTableWrapMode.values) {
    test('table blank row retains source offsets ($mode)', () {
      final tester = WidgetTester(maxWidth: 12, maxHeight: 3);
      addTearDown(tester.dispose);
      tester.pumpWidget(
        TextTable(
          content: const [
            [TextSpan(text: 'aa\r\n\r\nbb')],
          ],
          showBorders: false,
          columnWidthMode: TextTableColumnWidthMode.content,
          wrapMode: mode,
        ),
      );
      final table = tester.renderObject<RenderTextTable>(RenderTextTable)!;
      expect(table.sourceOffsetAt(const Offset(0, 1)), 4);
      expect(table.sourceOffsetAt(const Offset(1, 2)), 7);
    });
  }
}
