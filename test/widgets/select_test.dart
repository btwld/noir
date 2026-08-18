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
  });

  group('Select theming', () {
    test('an unthemed list keeps its original literal colors', () {
      final capture = BufferCapture(width: 6, height: 2);
      try {
        final frame = capture.capture(
          const Select<String>(height: 2, options: _abcOptions),
        );
        expect(frame, BufferMatchers.hasColorAt(0, 1, Color.white));
        expect(
          frame,
          BufferMatchers.hasBackgroundAt(0, 0, const Color(0.2, 0.4, 0.8)),
        );
        expect(
          frame,
          BufferMatchers.hasBackgroundAt(0, 1, Color.black),
          reason: 'no ancestor Theme still means no list fill',
        );
      } finally {
        capture.dispose();
      }
    });

    test('an ancestor Theme supplies every unset color', () {
      final capture = BufferCapture(width: 8, height: 2);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(
              text: Color.yellow,
              surface: Color.blue,
              selectedBackground: Color.magenta,
              selectedForeground: Color.cyan,
            ),
            child: const Select<String>(height: 2, options: _abcOptions),
          ),
        );
        expect(frame, BufferMatchers.hasColorAt(0, 0, Color.cyan));
        expect(frame, BufferMatchers.hasBackgroundAt(0, 0, Color.magenta));
        expect(frame, BufferMatchers.hasColorAt(0, 1, Color.yellow));
        expect(frame, BufferMatchers.hasBackgroundAt(0, 1, Color.blue));
      } finally {
        capture.dispose();
      }
    });

    test('an explicit color wins over the theme', () {
      final capture = BufferCapture(width: 8, height: 2);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(text: Color.yellow),
            child: const Select<String>(
              height: 2,
              color: Color.red,
              options: _abcOptions,
            ),
          ),
        );
        expect(frame, BufferMatchers.hasColorAt(0, 1, Color.red));
      } finally {
        capture.dispose();
      }
    });

    test('Color.transparent opts a themed list back out of a fill', () {
      final capture = BufferCapture(width: 8, height: 2);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(surface: Color.blue),
            child: const Select<String>(
              height: 2,
              backgroundColor: Color.transparent,
              options: _abcOptions,
            ),
          ),
        );
        expect(frame, isNot(BufferMatchers.hasBackgroundAt(0, 1, Color.blue)));
      } finally {
        capture.dispose();
      }
    });
  });
}
