import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/listenable_liveness.dart';
import '../helpers/test_element_host.dart';
import '../helpers/tui_test_app.dart';

void main() {
  group('ScrollBox', () {
    late BufferCapture capture;

    setUp(() {
      capture = BufferCapture(width: 6, height: 3);
    });

    tearDown(() {
      capture.dispose();
    });

    test('clips multi-line text output to the vertical viewport', () {
      final captured = capture.capture(
        const SizedBox(
          width: 4,
          height: 1,
          child: ScrollBox(showScrollbar: false, child: Text('AA\nBB')),
        ),
      );

      expect(captured.getRegion(0, 0, 4, 1), 'AA  ');
      expect(captured.getRegion(0, 1, 4, 1), '    ');
    });

    test('clips long text output to the horizontal viewport', () {
      final captured = capture.capture(
        SizedBox(
          width: 2,
          height: 1,
          child: ScrollBox(
            controller: ScrollController(initialOffset: 1),
            scrollDirection: Axis.horizontal,
            showScrollbar: false,
            child: const Text('WXYZ', softWrap: false),
          ),
        ),
      );

      expect(captured.getRegion(0, 0, 4, 1), 'XY  ');
    });

    test('notifies listeners for real scroll state changes only', () {
      final controller = ScrollController(initialOffset: 12);
      var calls = 0;
      controller.addListener(() {
        calls++;
      });

      controller.updateMaxScrollExtent(10);

      expect(controller.maxScrollExtent, 10);
      expect(controller.offset, 10);
      expect(calls, 1);

      controller.updateMaxScrollExtent(10);
      expect(calls, 1);

      controller.jumpTo(5);
      expect(controller.offset, 5);
      expect(calls, 2);

      controller.jumpTo(5);
      expect(calls, 2);
    });

    test('clamps initial offset even when first max extent is unchanged', () {
      final controller = ScrollController(initialOffset: 12);
      var calls = 0;
      controller.addListener(() {
        calls++;
      });

      controller.updateMaxScrollExtent(0);

      expect(controller.maxScrollExtent, 0);
      expect(controller.offset, 0);
      expect(calls, 1);
    });

    test('followTail attaches, detaches, and reattaches at the end', () {
      final controller = ScrollController(followTail: true);
      var calls = 0;
      controller.addListener(() => calls++);

      controller.updateMaxScrollExtent(10);
      expect(controller.offset, 10);
      expect(controller.isFollowingTail, isTrue);
      expect(calls, 1);

      controller.updateMaxScrollExtent(14);
      expect(controller.offset, 14);
      expect(controller.isFollowingTail, isTrue);
      expect(calls, 2);

      controller.jumpTo(6);
      expect(controller.offset, 6);
      expect(controller.isFollowingTail, isFalse);
      expect(calls, 3);

      controller.updateMaxScrollExtent(20);
      expect(controller.offset, 6);
      expect(controller.isFollowingTail, isFalse);
      expect(calls, 4);

      controller.jumpTo(20);
      expect(controller.isFollowingTail, isTrue);
      expect(calls, 5);

      controller.updateMaxScrollExtent(24);
      expect(controller.offset, 24);
      expect(controller.isFollowingTail, isTrue);
      expect(calls, 6);

      controller.updateMaxScrollExtent(8);
      expect(controller.offset, 8);
      expect(controller.isFollowingTail, isTrue);
      expect(calls, 7);
    });

    test('can opt out of focus traversal when used as a preview', () async {
      final first = FocusNode(debugLabel: 'first');
      final second = FocusNode(debugLabel: 'second');
      final app = createTuiTestApp(
        FocusScope(
          child: Column(
            children: [
              Button(label: 'First', focusNode: first, onPressed: () {}),
              const SizedBox(
                height: 1,
                child: ScrollBox(
                  canRequestFocus: false,
                  showScrollbar: false,
                  child: Text('preview'),
                ),
              ),
              Button(label: 'Second', focusNode: second, onPressed: () {}),
            ],
          ),
        ),
        width: 20,
        height: 3,
      );
      addTearDown(() {
        app.dispose();
        first.dispose();
        second.dispose();
      });
      first.requestFocus();
      expect(first.hasFocus, isTrue);

      app.mockInput.pressTab();
      await Future<void>.delayed(Duration.zero);

      expect(second.hasFocus, isTrue);
    });

    test('clips a focused editor cursor with its scrolled child', () {
      final controller = ScrollController(initialOffset: 2);
      final editor = TextEditingController(text: 'draft');
      final focusNode = FocusNode(debugLabel: 'scrolled-editor');
      final key = GlobalKey<_CursorClipHarnessState>();
      final app = createTuiTestApp(
        _CursorClipHarness(
          key: key,
          controller: controller,
          editor: editor,
          focusNode: focusNode,
        ),
        width: 10,
        height: 2,
      );
      addTearDown(() {
        app.dispose();
        controller.dispose();
        editor.dispose();
        focusNode.dispose();
      });

      focusNode.requestFocus();
      app.pumpFrame();
      expect(app.captureFrame().cursor.visible, isTrue);

      controller.jumpTo(0);
      app.pumpFrame();

      expect(app.captureFrame().cursor.visible, isFalse);

      controller.jumpTo(controller.maxScrollExtent);
      app.pumpFrame();

      expect(app.captureFrame().cursor.visible, isTrue);

      key.currentState!.setHeight(0);
      app.pumpFrame();

      expect(app.captureFrame().cursor.visible, isFalse);
    });
  });

  test(
    'an unusable controller replacement leaves the previous controller attached',
    () {
      final original = ScrollController();
      final host = TestElementHost()
        ..mount(
          ScrollBox(
            controller: original,
            showScrollbar: false,
            child: const Text('x'),
          ),
        );
      original.updateMaxScrollExtent(10);
      expect(original.hasListeners, isTrue);

      final disposed = ScrollController()..dispose();
      expect(
        () => host.update(
          ScrollBox(
            controller: disposed,
            showScrollbar: false,
            child: const Text('x'),
          ),
        ),
        throwsStateError,
      );

      expect(isLive(original), isTrue);
      expect(
        original.hasListeners,
        isTrue,
        reason:
            'the previous controller must stay subscribed after a failed swap',
      );

      host.dispose();
      expect(isLive(original), isTrue);
      original.dispose();
    },
  );

  test(
    'followTail preserves a detached chronological viewport across appends',
    () {
      final controller = ScrollController(followTail: true);
      final key = GlobalKey<_TailFollowHarnessState>();
      final app = createTuiTestApp(
        _TailFollowHarness(key: key, controller: controller),
        width: 8,
        height: 3,
      );

      try {
        app.pumpFrame();
        expect(controller.offset, 3);
        expect(app.captureFrame().toLines(), ['row 3', 'row 4', 'row 5']);

        key.currentState!.append('row 6\nrow 7');
        app.pumpFrame();
        expect(controller.offset, 5);
        expect(app.captureFrame().toLines(), ['row 5', 'row 6', 'row 7']);

        controller.jumpTo(1);
        app.pumpFrame();
        final detached = app.captureFrame().toLines();
        expect(controller.isFollowingTail, isFalse);

        key.currentState!.append('row 8\nrow 9\nrow 10');
        app.pumpFrame();
        expect(controller.offset, 1);
        expect(app.captureFrame().toLines(), detached);

        controller.jumpTo(controller.maxScrollExtent);
        expect(controller.isFollowingTail, isTrue);
        key.currentState!.append('row 11');
        app.pumpFrame();
        expect(controller.offset, controller.maxScrollExtent);
        expect(app.captureFrame().toLines().last, 'row 11');

        key.currentState!.removeLast(2);
        app.pumpFrame();
        expect(controller.offset, controller.maxScrollExtent);
        expect(controller.maxScrollExtent, 5);
        expect(controller.isFollowingTail, isTrue);

        key.currentState!.setViewportHeight(5);
        app.resize(8, 5);
        app.pumpFrame();
        expect(controller.viewportExtent, 5);
        expect(controller.offset, controller.maxScrollExtent);
        expect(controller.maxScrollExtent, 3);
        expect(controller.isFollowingTail, isTrue);
      } finally {
        app.dispose();
        controller.dispose();
      }
    },
  );
}

class _CursorClipHarness extends StatefulWidget {
  const _CursorClipHarness({
    required this.controller,
    required this.editor,
    required this.focusNode,
    super.key,
  });

  final ScrollController controller;
  final TextEditingController editor;
  final FocusNode focusNode;

  @override
  State<_CursorClipHarness> createState() => _CursorClipHarnessState();
}

class _CursorClipHarnessState extends State<_CursorClipHarness> {
  var _height = 2;

  void setHeight(int height) {
    setState(() => _height = height);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 10,
    height: _height,
    child: ScrollBox(
      controller: widget.controller,
      showScrollbar: false,
      child: Column(
        children: [
          const Text('row 0\nrow 1\nrow 2'),
          TextArea(
            controller: widget.editor,
            focusNode: widget.focusNode,
            height: 1,
          ),
        ],
      ),
    ),
  );
}

class _TailFollowHarness extends StatefulWidget {
  const _TailFollowHarness({required this.controller, super.key});

  final ScrollController controller;

  @override
  State<_TailFollowHarness> createState() => _TailFollowHarnessState();
}

class _TailFollowHarnessState extends State<_TailFollowHarness> {
  var _viewportHeight = 3;
  final _blocks = <String>[
    'row 0',
    'row 1',
    'row 2',
    'row 3',
    'row 4',
    'row 5',
  ];

  void append(String block) {
    setState(() => _blocks.add(block));
  }

  void removeLast(int count) {
    setState(() => _blocks.removeRange(_blocks.length - count, _blocks.length));
  }

  void setViewportHeight(int height) {
    setState(() => _viewportHeight = height);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 8,
    height: _viewportHeight,
    child: ScrollBox(
      controller: widget.controller,
      showScrollbar: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final block in _blocks) Text(block)],
      ),
    ),
  );
}
