// ignore_for_file: avoid_positional_boolean_parameters
import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';
import '../helpers/tui_test_app.dart';
import '../helpers/widget_tester.dart';

/// Records every index the list asks for so windowing is observable.
class _Recorder {
  final List<int> built = [];
  final List<int> selectedFlags = [];

  Widget build(BuildContext context, int index, bool selected) {
    built.add(index);
    if (selected) selectedFlags.add(index);
    return Text('item $index');
  }

  void reset() {
    built.clear();
    selectedFlags.clear();
  }
}

void main() {
  group('ListView windowing', () {
    test('builds only the visible window, not every item', () {
      final recorder = _Recorder();
      final tester = WidgetTester();
      try {
        tester.pumpWidget(
          ListView(itemCount: 1000, height: 4, itemBuilder: recorder.build),
        );
        expect(recorder.built, [0, 1, 2, 3]);
      } finally {
        tester.dispose();
      }
    });

    test('itemExtent divides the height into fewer, taller rows', () {
      final recorder = _Recorder();
      final tester = WidgetTester();
      try {
        tester.pumpWidget(
          ListView(
            itemCount: 100,
            height: 6,
            itemExtent: 2,
            itemBuilder: recorder.build,
          ),
        );
        expect(recorder.built, [0, 1, 2]);
      } finally {
        tester.dispose();
      }
    });

    test('a short list builds only the items it has', () {
      final recorder = _Recorder();
      final tester = WidgetTester();
      try {
        tester.pumpWidget(
          ListView(itemCount: 2, height: 6, itemBuilder: recorder.build),
        );
        expect(recorder.built, [0, 1]);
      } finally {
        tester.dispose();
      }
    });
  });

  group('ListView selection mode', () {
    test('ArrowDown moves the highlight and fires onChanged only', () async {
      final recorder = _Recorder();
      final changes = <int>[];
      final selects = <int>[];
      final driver = KeyDriver(
        ListView(
          autofocus: true,
          itemCount: 10,
          height: 4,
          selectedIndex: 0,
          itemBuilder: recorder.build,
          onChanged: changes.add,
          onSelect: selects.add,
        ),
      );
      await driver.ready();

      await driver.sendLogicalKey(LogicalKeyboardKey.arrowDown);
      expect(changes, [1]);
      expect(selects, isEmpty);
      driver.dispose();
    });

    test('Enter confirms the highlight', () async {
      final recorder = _Recorder();
      final selects = <int>[];
      final driver = KeyDriver(
        ListView(
          autofocus: true,
          itemCount: 10,
          height: 4,
          selectedIndex: 2,
          itemBuilder: recorder.build,
          onSelect: selects.add,
        ),
      );
      await driver.ready();

      await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
      expect(selects, [2]);
      driver.dispose();
    });

    test('moving past the window bottom scrolls it', () async {
      final recorder = _Recorder();
      final app = createTuiTestApp(
        ListView(
          autofocus: true,
          itemCount: 10,
          height: 3,
          selectedIndex: 0,
          itemBuilder: recorder.build,
        ),
      );
      try {
        await _settle(app);
        for (var i = 0; i < 4; i++) {
          app.mockInput.pressArrow(ArrowDirection.down);
        }
        recorder.reset();
        app.pumpFrame();
        expect(recorder.built, [2, 3, 4]);
      } finally {
        app.dispose();
      }
    });

    test('End jumps to the last item and Home back to the first', () async {
      final recorder = _Recorder();
      final changes = <int>[];
      final driver = KeyDriver(
        ListView(
          autofocus: true,
          itemCount: 10,
          height: 3,
          selectedIndex: 0,
          itemBuilder: recorder.build,
          onChanged: changes.add,
        ),
      );
      await driver.ready();

      await driver.sendLogicalKey(LogicalKeyboardKey.end);
      expect(changes, [9]);
      await driver.sendLogicalKey(LogicalKeyboardKey.home);
      expect(changes, [9, 0]);
      driver.dispose();
    });

    test('swapping the controller keeps the highlight on screen', () {
      final recorder = _Recorder();
      final first = ViewportController();
      final second = ViewportController();
      final owner = BuildOwner();
      final element = ListView(
        itemCount: 100,
        height: 4,
        selectedIndex: 50,
        controller: first,
        itemBuilder: recorder.build,
      ).createElement();

      element.mount(null, owner);
      owner.buildScope();
      expect(recorder.built, [47, 48, 49, 50]);

      recorder.reset();
      element.update(
        ListView(
          itemCount: 100,
          height: 4,
          selectedIndex: 50,
          controller: second,
          itemBuilder: recorder.build,
        ),
      );
      owner.buildScope();
      expect(
        recorder.built,
        [47, 48, 49, 50],
        reason:
            'a fresh controller must be scrolled back to the highlight, '
            'and adopting it must not schedule a redundant rebuild',
      );

      element.unmount();
      first.dispose();
      second.dispose();
    });

    test('the builder is told which row is selected', () {
      final recorder = _Recorder();
      final tester = WidgetTester();
      try {
        tester.pumpWidget(
          ListView(
            itemCount: 5,
            height: 4,
            selectedIndex: 2,
            itemBuilder: recorder.build,
          ),
        );
        expect(recorder.selectedFlags, [2]);
      } finally {
        tester.dispose();
      }
    });

    test('a left click selects and confirms the clicked row', () async {
      final recorder = _Recorder();
      final changes = <int>[];
      final selects = <int>[];
      final driver = KeyDriver(
        ListView(
          itemCount: 10,
          height: 4,
          selectedIndex: 0,
          itemBuilder: recorder.build,
          onChanged: changes.add,
          onSelect: selects.add,
        ),
        paintFrames: true,
      );
      await driver.ready();

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 0,
          y: 2,
        ),
      );
      expect(changes, [2]);
      expect(selects, [2]);
      driver.dispose();
    });

    test(
      'a focused list paints its highlight on selectedBackgroundColor',
      () async {
        final app = createTuiTestApp(
          ListView(
            autofocus: true,
            itemCount: 4,
            height: 4,
            selectedIndex: 1,
            selectedBackgroundColor: Color.magenta,
            itemBuilder: (context, index, selected) => Text('r$index'),
          ),
          width: 10,
          height: 4,
        );
        try {
          await _settle(app);
          final frame = app.captureFrame();
          expect(frame, BufferMatchers.hasBackgroundAt(0, 1, Color.magenta));
        } finally {
          app.dispose();
        }
      },
    );

    test('an unfocused list mutes its highlight to the surface variant', () {
      // BufferCapture never runs the autofocus microtask, so this capture is
      // the unfocused appearance by construction.
      final capture = BufferCapture(width: 10, height: 4);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(surfaceVariant: Color.blue),
            child: ListView(
              itemCount: 4,
              height: 4,
              selectedIndex: 1,
              selectedBackgroundColor: Color.magenta,
              itemBuilder: (context, index, selected) => Text('r$index'),
            ),
          ),
        );
        expect(
          frame,
          BufferMatchers.hasBackgroundAt(0, 1, Color.blue),
          reason: 'without focus the highlight is chrome, not accent',
        );
        expect(
          frame,
          isNot(BufferMatchers.hasBackgroundAt(0, 1, Color.magenta)),
        );
      } finally {
        capture.dispose();
      }
    });
  });

  group('ListView plain scroll mode', () {
    test('ArrowDown scrolls the window without a selection callback', () async {
      final recorder = _Recorder();
      final changes = <int>[];
      final app = createTuiTestApp(
        ListView(
          autofocus: true,
          itemCount: 10,
          height: 3,
          itemBuilder: recorder.build,
          onChanged: changes.add,
        ),
      );
      try {
        await _settle(app);
        app.mockInput.pressArrow(ArrowDirection.down);
        recorder.reset();
        app.pumpFrame();
        expect(recorder.built, [1, 2, 3]);
        expect(changes, isEmpty);
      } finally {
        app.dispose();
      }
    });

    test('Enter reports nothing and stays available to an ancestor', () async {
      final selects = <int>[];
      var ancestorSawEnter = false;
      final recorder = _Recorder();
      final driver = KeyDriver(
        Focus(
          canRequestFocus: false,
          onKeyEvent: (node, event) {
            if (event.isPress && event.logicalKey == LogicalKeyboardKey.enter) {
              ancestorSawEnter = true;
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: ListView(
            autofocus: true,
            itemCount: 10,
            height: 3,
            itemBuilder: recorder.build,
            onSelect: selects.add,
          ),
        ),
      );
      await driver.ready();

      await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
      expect(selects, isEmpty, reason: 'a plain list has no row to confirm');
      expect(ancestorSawEnter, isTrue);
      driver.dispose();
    });

    test('a click reports nothing but still takes focus', () async {
      final selects = <int>[];
      final focusNode = FocusNode();
      final recorder = _Recorder();
      final driver = KeyDriver(
        ListView(
          focusNode: focusNode,
          itemCount: 10,
          height: 3,
          itemBuilder: recorder.build,
          onSelect: selects.add,
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
      expect(selects, isEmpty);
      expect(focusNode.hasFocus, isTrue);
      driver.dispose();
      focusNode.dispose();
    });

    test('the mouse wheel scrolls the window', () async {
      final recorder = _Recorder();
      final app = createTuiTestApp(
        ListView(itemCount: 20, height: 3, itemBuilder: recorder.build),
      );
      try {
        await _settle(app);
        app.mockMouse.scroll(0, 0, ScrollDirection.down);
        app.mockMouse.scroll(0, 0, ScrollDirection.down);
        recorder.reset();
        app.pumpFrame();
        expect(recorder.built, [2, 3, 4]);
      } finally {
        app.dispose();
      }
    });

    test('no ancestor Theme leaves the list background unfilled', () {
      final capture = BufferCapture(width: 6, height: 2);
      try {
        final frame = capture.capture(
          ListView(
            itemCount: 2,
            height: 2,
            itemBuilder: (context, index, selected) => Text('r$index'),
          ),
        );
        expect(frame, BufferMatchers.hasBackgroundAt(0, 0, Color.black));
      } finally {
        capture.dispose();
      }
    });

    test('an ancestor Theme supplies the list background', () {
      final capture = BufferCapture(width: 6, height: 2);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(surface: Color.blue),
            child: ListView(
              itemCount: 2,
              height: 2,
              itemBuilder: (context, index, selected) => Text('r$index'),
            ),
          ),
        );
        expect(frame, BufferMatchers.hasBackgroundAt(0, 0, Color.blue));
      } finally {
        capture.dispose();
      }
    });
  });
}

/// Lets autofocus and the first build settle before a test drives input.
Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
