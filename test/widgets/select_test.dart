import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';

const _optionA = SelectOption<String>(name: 'A', value: 'a');
const _optionB = SelectOption<String>(name: 'B', value: 'b');
const _optionC = SelectOption<String>(name: 'C', value: 'c');
const _abcOptions = <SelectOption<String>>[_optionA, _optionB, _optionC];

void main() {
  group('Select', () {
    test(
      'ArrowDown advances highlight and fires onChanged but not onSelect',
      () async {
        final focusNode = FocusNode();
        final changes = <int>[];
        final selects = <int>[];
        final driver = KeyDriver(
          Select<String>(
            focusNode: focusNode,
            autofocus: true,
            height: 3,
            options: _abcOptions,
            onChanged: (i, _) => changes.add(i),
            onSelect: (i, _) => selects.add(i),
          ),
        );
        await driver.ready();
        expect(focusNode.hasFocus, isTrue);

        await driver.sendLogicalKey(LogicalKeyboardKey.arrowDown);
        expect(changes, equals([1]));
        expect(selects, isEmpty);
        driver.dispose();
      },
    );

    test('Enter fires onSelect with current highlight', () async {
      final focusNode = FocusNode();
      final selects = <int>[];
      final driver = KeyDriver(
        Select<String>(
          focusNode: focusNode,
          autofocus: true,
          selectedIndex: 1,
          height: 3,
          options: _abcOptions,
          onSelect: (i, _) => selects.add(i),
        ),
      );
      await driver.ready();
      await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
      expect(selects, equals([1]));
      driver.dispose();
    });

    test('left click moves highlight and fires onSelect', () async {
      final changes = <int>[];
      final selects = <int>[];
      final driver = KeyDriver(
        Select<String>(
          height: 3,
          options: _abcOptions,
          onChanged: (i, _) => changes.add(i),
          onSelect: (i, _) => selects.add(i),
        ),
        paintFrames: true,
      );
      await driver.ready();

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 0,
          y: 1,
        ),
      );

      expect(changes, equals([1]));
      expect(selects, equals([1]));
      driver.dispose();
    });

    test('left click confirms already highlighted option', () async {
      final selects = <int>[];
      final driver = KeyDriver(
        Select<String>(
          selectedIndex: 1,
          height: 3,
          options: _abcOptions,
          onSelect: (i, _) => selects.add(i),
        ),
        paintFrames: true,
      );
      await driver.ready();

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 0,
          y: 1,
        ),
      );

      expect(selects, equals([1]));
      driver.dispose();
    });

    test('Home and End jump to bounds', () async {
      final changes = <int>[];
      final driver = KeyDriver(
        Select<int>(
          autofocus: true,
          height: 2,
          options: const [
            SelectOption(name: '1', value: 1),
            SelectOption(name: '2', value: 2),
            SelectOption(name: '3', value: 3),
            SelectOption(name: '4', value: 4),
          ],
          onChanged: (i, _) => changes.add(i),
        ),
      );
      await driver.ready();
      await driver.sendLogicalKey(LogicalKeyboardKey.end);
      await driver.sendLogicalKey(LogicalKeyboardKey.home);
      expect(changes, equals([3, 0]));
      driver.dispose();
    });

    test('PageDown clamps at end of list', () async {
      final changes = <int>[];
      final driver = KeyDriver(
        Select<int>(
          autofocus: true,
          height: 2,
          options: const [
            SelectOption(name: '1', value: 1),
            SelectOption(name: '2', value: 2),
            SelectOption(name: '3', value: 3),
          ],
          onChanged: (i, _) => changes.add(i),
        ),
      );
      await driver.ready();
      await driver.sendLogicalKey(LogicalKeyboardKey.pageDown);
      await driver.sendLogicalKey(LogicalKeyboardKey.pageDown);
      expect(changes, equals([2]));
      driver.dispose();
    });

    test('renders Unicode option text by terminal cells', () {
      final capture = BufferCapture(width: 8, height: 1);
      try {
        final captured = capture.capture(
          Select<int>(
            height: 1,
            options: const [
              SelectOption(name: '中', description: '😀', value: 1),
            ],
          ),
        );

        expect(captured.getChar(0, 0), '中');
        expect(captured.getChar(1, 0), ' ');
        expect(captured.getChar(2, 0), ' ');
        expect(captured.getChar(3, 0), '😀');
      } finally {
        capture.dispose();
      }
    });

    test('scroll indicator follows the laid-out rows, not the height '
        'hint', () {
      // The host grants fewer rows than `height` asks for, so the list
      // overflows its painted window even though `options.length` is below
      // the hint. The arrows have to describe what was painted.
      final capture = BufferCapture(width: 10, height: 4);
      try {
        final captured = capture.capture(
          SizedBox(
            width: 10,
            height: 4,
            child: Select<int>(
              height: 13,
              showScrollIndicator: true,
              options: List<SelectOption<int>>.generate(
                10,
                (i) => SelectOption(name: 'Item ${i + 1}', value: i),
              ),
            ),
          ),
        );

        expect(captured.getChar(9, 0), ' ', reason: 'top of list, no up arrow');
        expect(captured.getChar(9, 3), '▼', reason: 'six rows remain below');
      } finally {
        capture.dispose();
      }
    });

    test('a zero-row Select paints no indicator outside its box', () {
      // `height: 0` is a legal hint, and a parent can still force the box
      // taller. Nothing is painted, so there is no window for an arrow to
      // describe — and the row above belongs to a sibling.
      final capture = BufferCapture(width: 10, height: 4);
      try {
        final captured = capture.capture(
          Column(
            children: [
              const Text('sentinel'),
              SizedBox(
                width: 10,
                height: 3,
                child: Select<int>(
                  height: 0,
                  showScrollIndicator: true,
                  options: List<SelectOption<int>>.generate(
                    5,
                    (i) => SelectOption(name: 'Item ${i + 1}', value: i),
                  ),
                ),
              ),
            ],
          ),
        );

        expect(
          captured.getChar(9, 0),
          ' ',
          reason: 'sentinel row is untouched',
        );
      } finally {
        capture.dispose();
      }
    });
  });
}
