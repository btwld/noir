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
}
