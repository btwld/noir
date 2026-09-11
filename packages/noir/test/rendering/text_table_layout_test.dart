import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/driver.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';
import '../helpers/widget_tester.dart';

const _content = <List<InlineSpan>>[
  <InlineSpan>[TextSpan(text: 'Name'), TextSpan(text: 'State')],
  <InlineSpan>[
    TextSpan(
      text: 'Noir',
      style: TextStyle(color: Color.cyan),
    ),
    TextSpan(
      text: 'ready',
      style: TextStyle(color: Color.green),
    ),
  ],
];

void main() {
  test('TextTable paints rich cells and single-line borders', () {
    final capture = BufferCapture(width: 18, height: 5);
    try {
      final frame = capture.capture(const TextTable(content: _content));

      expect(frame.getChar(0, 0), '┌');
      expect(frame.getChar(17, 0), '┐');
      expect(frame.getChar(0, 4), '└');
      expect(frame, BufferMatchers.hasColorAt(1, 3, Color.cyan));
      expect(frame, BufferMatchers.hasColorAt(10, 3, Color.green));
    } finally {
      capture.dispose();
    }
  });

  test('balanced and proportional full-width fitters differ', () {
    final proportional = WidgetTester(maxWidth: 10, maxHeight: 20);
    final balanced = WidgetTester(maxWidth: 10, maxHeight: 20);
    try {
      proportional.pumpWidget(
        const TextTable(
          content: <List<InlineSpan>>[
            <InlineSpan>[
              TextSpan(text: 'aaaa'),
              TextSpan(text: 'very long value!'),
            ],
          ],
          showBorders: false,
        ),
      );
      balanced.pumpWidget(
        const TextTable(
          content: <List<InlineSpan>>[
            <InlineSpan>[
              TextSpan(text: 'aaaa'),
              TextSpan(text: 'very long value!'),
            ],
          ],
          showBorders: false,
          columnFitter: TextTableColumnFitter.balanced,
        ),
      );

      final proportionalRender = proportional.renderObject<RenderTextTable>(
        RenderTextTable,
      )!;
      final balancedRender = balanced.renderObject<RenderTextTable>(
        RenderTextTable,
      )!;
      expect(
        proportionalRender.debugColumnWidths,
        isNot(balancedRender.debugColumnWidths),
      );
      expect(balancedRender.debugColumnWidths, <int>[4, 6]);
    } finally {
      proportional.dispose();
      balanced.dispose();
    }
  });

  test('proportional fitter matches pinned OpenTUI regression vectors', () {
    final tester = WidgetTester(maxWidth: 37);
    try {
      tester.pumpWidget(
        TextTable(
          content: <List<InlineSpan>>[
            <InlineSpan>[TextSpan(text: 'a' * 91), TextSpan(text: 'b' * 9)],
          ],
          showBorders: false,
        ),
      );

      final render = tester.renderObject<RenderTextTable>(RenderTextTable)!;
      expect(render.debugColumnWidths, <int>[28, 9]);
    } finally {
      tester.dispose();
    }
  });

  test('full-width tables distribute expansion evenly across columns', () {
    final tester = WidgetTester(maxWidth: 10, maxHeight: 10);
    try {
      tester.pumpWidget(
        const TextTable(
          content: <List<InlineSpan>>[
            <InlineSpan>[TextSpan(text: 'a'), TextSpan(text: 'bbbb')],
          ],
          showBorders: false,
        ),
      );

      final render = tester.renderObject<RenderTextTable>(RenderTextTable)!;
      expect(render.debugColumnWidths, <int>[4, 6]);
    } finally {
      tester.dispose();
    }
  });

  test('narrow table paint stays inside its assigned box', () {
    final capture = BufferCapture(width: 6, height: 3);
    try {
      final frame = capture.capture(
        const Stack(
          children: <Widget>[
            Positioned(left: 2, top: 1, child: Text('Z')),
            Positioned(
              left: 0,
              top: 0,
              width: 2,
              child: TextTable(
                content: <List<InlineSpan>>[
                  <InlineSpan>[TextSpan(text: 'a'), TextSpan(text: 'b')],
                ],
              ),
            ),
          ],
        ),
      );

      expect(frame.getChar(2, 1), 'Z');
    } finally {
      capture.dispose();
    }
  });

  test('no-wrap columns stay intrinsic while paint remains clipped', () {
    final tester = WidgetTester(maxWidth: 3, maxHeight: 2);
    final capture = BufferCapture(width: 5, height: 2);
    try {
      tester.pumpWidget(
        const TextTable(
          content: <List<InlineSpan>>[
            <InlineSpan>[TextSpan(text: 'abcdef')],
          ],
          wrapMode: TextTableWrapMode.none,
          showBorders: false,
        ),
      );
      expect(
        tester
            .renderObject<RenderTextTable>(RenderTextTable)!
            .debugColumnWidths,
        <int>[6],
      );

      final frame = capture.capture(
        const Stack(
          children: <Widget>[
            Positioned(left: 3, child: Text('Z')),
            Positioned(
              width: 3,
              child: TextTable(
                content: <List<InlineSpan>>[
                  <InlineSpan>[TextSpan(text: 'abcdef')],
                ],
                wrapMode: TextTableWrapMode.none,
                showBorders: false,
              ),
            ),
          ],
        ),
      );
      expect(frame.toLines().first, startsWith('abcZ'));
    } finally {
      tester.dispose();
      capture.dispose();
    }
  });

  test('character wrapping synchronizes the row height', () {
    final tester = WidgetTester(maxWidth: 5, maxHeight: 20);
    try {
      tester.pumpWidget(
        const TextTable(
          content: <List<InlineSpan>>[
            <InlineSpan>[TextSpan(text: 'abcdef'), TextSpan(text: 'x')],
          ],
          wrapMode: TextTableWrapMode.character,
          showBorders: false,
        ),
      );

      expect(tester.height, 2);
    } finally {
      tester.dispose();
    }
  });

  test('grid selection maps across cell separators', () {
    final capture = BufferCapture(width: 6, height: 1);
    try {
      final frame = capture.capture(
        const TextTable(
          content: <List<InlineSpan>>[
            <InlineSpan>[TextSpan(text: 'ab'), TextSpan(text: 'cd')],
          ],
          showBorders: false,
          columnGap: 2,
          selection: TextHighlight(
            start: 3,
            end: 5,
            backgroundColor: Color.blue,
          ),
        ),
      );
      expect(frame, BufferMatchers.hasBackgroundAt(4, 0, Color.blue));
      expect(frame, isNot(BufferMatchers.hasBackgroundAt(0, 0, Color.blue)));
    } finally {
      capture.dispose();
    }
  });

  test('content-mode tables do not stretch the last column to the parent', () {
    final host = DriverHost.create(width: 40, height: 5);
    addTearDown(host.dispose);
    host.binding
      ..runApp(
        const TextTable(
          content: _content,
          columnWidthMode: TextTableColumnWidthMode.content,
        ),
      )
      ..debugFlushFrame();

    final top = (host.capture()['lines']! as List<Object?>)
        .cast<String>()
        .first;
    expect(top, contains('┌'));
    expect(top.indexOf('┐'), inInclusiveRange(1, 20));
  });

  test('horizontal padding remains part of each hit-test cell', () {
    final tester = WidgetTester(maxWidth: 20, maxHeight: 2);
    try {
      tester.pumpWidget(
        const TextTable(
          content: <List<InlineSpan>>[
            <InlineSpan>[TextSpan(text: 'Name'), TextSpan(text: 'State')],
          ],
          columnWidthMode: TextTableColumnWidthMode.content,
          showBorders: false,
          cellPaddingX: 1,
        ),
      );
      final table = tester.renderObject<RenderTextTable>(RenderTextTable)!;

      expect(table.sourceOffsetAt(const Offset(3, 0)), 2);
      expect(table.sourceOffsetAt(const Offset(4, 0)), 3);
      expect(table.sourceOffsetAt(const Offset(6, 0)), 5);
    } finally {
      tester.dispose();
    }
  });

  test(
    'standalone table selects by pointer and copies row-major text',
    () async {
      SelectedText? selected;
      SelectedText? copied;
      bool? copySucceeded;
      final driver = KeyDriver(
        TextTable(
          content: _content,
          columnWidthMode: TextTableColumnWidthMode.content,
          onSelectionChanged: (value) => selected = value,
          onCopy: (value, {required success}) {
            copied = value;
            copySucceeded = success;
          },
        ),
        width: 18,
        height: 5,
      );
      addTearDown(driver.dispose);
      await driver.ready();

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          x: 1,
          y: 1,
          button: MouseButton.left,
        ),
      );
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.move,
          x: 2,
          y: 1,
          button: MouseButton.left,
        ),
      );
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.up,
          x: 2,
          y: 1,
          button: MouseButton.left,
        ),
      );
      expect(selected?.text, 'N');
      await driver.sendCharacter('a', modifiers: KeyModifiers.ctrl);

      expect(selected?.text, 'Name\tState\nNoir\tready');
      await driver.sendCharacter('c', modifiers: KeyModifiers.ctrl);
      expect(copied, selected);
      expect(copySucceeded, isFalse);
    },
  );

  test('standalone table supports vertical Shift+arrow selection', () async {
    SelectedText? selected;
    final driver = KeyDriver(
      TextTable(
        content: _content,
        columnWidthMode: TextTableColumnWidthMode.content,
        onSelectionChanged: (value) => selected = value,
      ),
      width: 18,
      height: 5,
    );
    addTearDown(driver.dispose);
    await driver.ready();

    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        x: 1,
        y: 1,
        button: MouseButton.left,
      ),
    );
    await driver.sendMouse(
      MouseEvent(type: MouseEventType.up, x: 1, y: 1, button: MouseButton.left),
    );
    await driver.sendLogicalKey(
      LogicalKeyboardKey.arrowDown,
      modifiers: KeyModifiers.shift,
    );

    expect(selected?.text, 'Name\tState\n');
  });
}
