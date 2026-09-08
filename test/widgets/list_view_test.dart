// ignore_for_file: avoid_positional_boolean_parameters
import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';
import '../helpers/test_element_host.dart';
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

      final event = MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 0,
        y: 2,
      );
      await driver.sendMouse(event);
      expect(changes, [2]);
      expect(selects, [2]);
      expect(event.isConsumed, isTrue);
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

  group('ListView row identity', () {
    test('a keyed row carries its key on exactly one element', () {
      final tester = WidgetTester();
      try {
        tester.pumpWidget(
          ListView(
            itemCount: 3,
            height: 3,
            itemBuilder: (context, index, selected) =>
                Text('item $index', key: ValueKey<String>('row-$index')),
          ),
        );
        expect(_countKey(tester.element!, const ValueKey<String>('row-1')), 1);
      } finally {
        tester.dispose();
      }
    });

    test('a keyed row keeps its State while it stays in the window', () {
      final log = _RowStateLog();
      final viewport = ViewportController();
      final host = TestElementHost();
      try {
        host
          ..mount(_keyedList(log: log, itemCount: 6, controller: viewport))
          ..pumpFrame(constraints: _rowConstraints);
        final before = log.stateOf('b');
        viewport.jumpTo(1);
        host.pumpFrame(constraints: _rowConstraints);
        expect(log.stateOf('b'), same(before));
        expect(log.disposed, ['a']);
      } finally {
        host.dispose();
        viewport.dispose();
      }
    });

    test('reordering keyed rows moves their State with the key', () {
      final log = _RowStateLog();
      final viewport = ViewportController();
      final host = TestElementHost();
      try {
        host
          ..mount(_keyedList(log: log, itemCount: 3, controller: viewport))
          ..pumpFrame(constraints: _rowConstraints);
        final before = log.stateOf('c');
        host
          ..update(
            _keyedList(
              log: log,
              itemCount: 3,
              controller: viewport,
              reversed: true,
            ),
          )
          ..pumpFrame(constraints: _rowConstraints);
        expect(log.stateOf('c'), same(before));
        expect(log.disposed, isEmpty);
      } finally {
        host.dispose();
        viewport.dispose();
      }
    });

    test('a row leaving the window disposes its State', () {
      final log = _RowStateLog();
      final viewport = ViewportController();
      final host = TestElementHost();
      try {
        host
          ..mount(_keyedList(log: log, itemCount: 6, controller: viewport))
          ..pumpFrame(constraints: _rowConstraints);
        viewport.jumpTo(3);
        host.pumpFrame(constraints: _rowConstraints);
        expect(log.disposed..sort(), ['a', 'b', 'c']);
      } finally {
        host.dispose();
        viewport.dispose();
      }
    });
  });

  group('ListView height changes', () {
    test('a shorter list scrolls the highlight back into view', () {
      final host = TestElementHost();
      final viewport = ViewportController();
      try {
        host
          ..mount(_heightList(controller: viewport, height: 6))
          ..pumpFrame(constraints: _rowConstraints);
        expect(viewport.scrollOffset, 4);

        host
          ..update(_heightList(controller: viewport, height: 3))
          ..pumpFrame(constraints: _rowConstraints);

        expect(viewport.scrollOffset, 7);
      } finally {
        host.dispose();
        viewport.dispose();
      }
    });

    test('a resized plain list keeps the window where the user left it', () {
      final host = TestElementHost();
      final viewport = ViewportController();
      Widget build(int height) => ListView(
        itemCount: 10,
        height: height,
        controller: viewport,
        itemBuilder: (context, index, selected) => Text('item $index'),
      );
      try {
        host
          ..mount(build(3))
          ..pumpFrame(constraints: _rowConstraints);
        viewport.jumpTo(5);
        host
          ..update(build(4))
          ..pumpFrame(constraints: _rowConstraints);

        expect(viewport.scrollOffset, 5);
      } finally {
        host.dispose();
        viewport.dispose();
      }
    });

    test('a taller list keeps a scroll position its content allows', () {
      final host = TestElementHost();
      final viewport = ViewportController();
      try {
        host
          ..mount(_heightList(controller: viewport, height: 3))
          ..pumpFrame(constraints: _rowConstraints);
        expect(viewport.scrollOffset, 7);

        host
          ..update(_heightList(controller: viewport, height: 8))
          ..pumpFrame(constraints: _rowConstraints);

        expect(viewport.scrollOffset, 2);
      } finally {
        host.dispose();
        viewport.dispose();
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

      final event = MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 0,
        y: 1,
      );
      await driver.sendMouse(event);
      expect(selects, isEmpty);
      expect(focusNode.hasFocus, isTrue);
      expect(event.isConsumed, isFalse);
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

/// A ten-row list whose last row is selected, used to watch the window follow
/// the highlight as the list height changes.
Widget _heightList({
  required ViewportController controller,
  required int height,
}) => ListView(
  itemCount: 10,
  height: height,
  controller: controller,
  selectedIndex: 9,
  itemBuilder: (context, index, selected) => Text('item $index'),
);

/// Constraints wide enough for a three-row window of short labels.
const _rowConstraints = BoxConstraints(maxWidth: 20, maxHeight: 10);

/// Row identifiers used by the keyed-row identity tests, in list order.
const _rowIds = ['a', 'b', 'c', 'd', 'e', 'f'];

/// Builds a three-row window of keyed [_RowProbe] rows over [itemCount] items.
///
/// [reversed] keeps the same identifiers and reverses only their order, so a
/// rebuild reorders keyed rows without adding or removing any.
Widget _keyedList({
  required _RowStateLog log,
  required int itemCount,
  required ViewportController controller,
  bool reversed = false,
}) => ListView(
  itemCount: itemCount,
  height: 3,
  controller: controller,
  itemBuilder: (context, index, selected) {
    final id = _rowIds[reversed ? itemCount - 1 - index : index];
    return _RowProbe(key: ValueKey<String>(id), id: id, log: log);
  },
);

/// Counts the elements whose widget carries [key].
int _countKey(Element element, Key key) {
  var count = element.widget.key == key ? 1 : 0;
  for (final child in element.children) {
    count += _countKey(child, key);
  }
  return count;
}

/// Records which row [State] currently serves each identifier, and which
/// identifiers have been disposed.
class _RowStateLog {
  final Map<String, State<_RowProbe>> _current = {};

  /// Identifiers whose row [State] the framework has disposed, in order.
  final List<String> disposed = [];

  /// The [State] that most recently built the row named [id].
  State<_RowProbe>? stateOf(String id) => _current[id];
}

/// A row that reports its [State] identity and disposal to [log].
class _RowProbe extends StatefulWidget {
  const _RowProbe({required this.id, required this.log, super.key});

  /// Identifier this row shows and reports under.
  final String id;

  /// Log this row reports to.
  final _RowStateLog log;

  @override
  State<_RowProbe> createState() => _RowProbeState();
}

class _RowProbeState extends State<_RowProbe> {
  @override
  void dispose() {
    widget.log.disposed.add(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.log._current[widget.id] = this;
    return Text(widget.id);
  }
}
