import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';

const _tabs = <SelectOption<String>>[
  SelectOption(name: 'One', description: 'first', value: 'one'),
  SelectOption(name: 'Two', description: 'second', value: 'two'),
  SelectOption(name: 'Three', description: 'third', value: 'three'),
];

void main() {
  test('TabSelect supports arrows, brackets, wrapping, and Enter', () async {
    final changes = <int>[];
    final selections = <int>[];
    final driver = KeyDriver(
      TabSelect<String>(
        options: _tabs,
        selectedIndex: 2,
        wrapSelection: true,
        autofocus: true,
        onChanged: (index, _) => changes.add(index),
        onSelect: (index, _) => selections.add(index),
      ),
    );
    await driver.ready();

    await driver.sendLogicalKey(LogicalKeyboardKey.arrowRight);
    await driver.sendCharacter('[');
    await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);

    expect(changes, <int>[0, 2]);
    expect(selections, <int>[2]);
    driver.dispose();
  });

  test('TabSelect paints fixed-width tabs, underline, and description', () {
    final capture = BufferCapture(width: 12, height: 3);
    try {
      final frame = capture.capture(
        const TabSelect<String>(options: _tabs, tabWidth: 6, selectedIndex: 1),
      );

      expect(frame.getChar(7, 0), 'T');
      expect(frame.getChar(6, 1), '▬');
      expect(frame.getChar(1, 2), 's');
    } finally {
      capture.dispose();
    }
  });

  test('TabSelect paints content-sized tabs from terminal cell widths', () {
    const contentTabs = <SelectOption<String>>[
      SelectOption(name: '表', value: 'wide'),
      SelectOption(name: 'Two', value: 'two'),
    ];
    final capture = BufferCapture(width: 9, height: 1);
    try {
      final frame = capture.capture(
        const TabSelect<String>(
          options: contentTabs,
          tabWidth: null,
          selectedIndex: 1,
          showScrollArrows: false,
          showDescription: false,
          showUnderline: false,
        ),
      );

      expect(frame.getChar(1, 0), '表');
      expect(frame.getChar(5, 0), 'T');
      expect(frame.getChar(7, 0), 'o');
    } finally {
      capture.dispose();
    }
  });

  test('TabSelect applies terminal attributes to the selected label', () {
    final capture = BufferCapture(width: 10, height: 1);
    try {
      final frame = capture.capture(
        const TabSelect<String>(
          options: _tabs,
          tabWidth: 5,
          selectedTextAttributes: Attr.bold,
          showDescription: false,
          showUnderline: false,
        ),
      );

      expect(frame.getCell(1, 0).isBold, isTrue);
      expect(frame.getCell(6, 0).isBold, isFalse);
    } finally {
      capture.dispose();
    }
  });

  test('TabSelect pointer selects a visible cell-width tab', () async {
    final changes = <int>[];
    final selections = <int>[];
    final driver = KeyDriver(
      TabSelect<String>(
        options: _tabs,
        tabWidth: 5,
        onChanged: (index, _) => changes.add(index),
        onSelect: (index, _) => selections.add(index),
      ),
      paintFrames: true,
    );
    await driver.ready();

    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 6,
        y: 0,
      ),
    );

    expect(changes, <int>[1]);
    expect(selections, <int>[1]);
    driver.dispose();
  });

  test('TabSelect pointer maps content-sized tab boundaries', () async {
    final changes = <int>[];
    final selections = <int>[];
    final driver = KeyDriver(
      TabSelect<String>(
        options: _tabs,
        tabWidth: null,
        showDescription: false,
        showUnderline: false,
        onChanged: (index, _) => changes.add(index),
        onSelect: (index, _) => selections.add(index),
      ),
      paintFrames: true,
    );
    await driver.ready();

    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 10,
        y: 0,
      ),
    );

    expect(changes, <int>[2]);
    expect(selections, <int>[2]);
    driver.dispose();
  });

  test('TabSelect can preserve existing focus on pointer selection', () async {
    final focusNode = FocusNode();
    final selections = <int>[];
    final driver = KeyDriver(
      TabSelect<String>(
        options: _tabs,
        tabWidth: 5,
        focusNode: focusNode,
        requestFocusOnPointer: false,
        onSelect: (index, _) => selections.add(index),
      ),
      paintFrames: true,
    );
    await driver.ready();

    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 6,
        y: 0,
      ),
    );

    expect(selections, <int>[1]);
    expect(focusNode.hasFocus, isFalse);
    driver.dispose();
    focusNode.dispose();
  });
}
