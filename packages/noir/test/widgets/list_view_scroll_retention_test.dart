import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';

void main() {
  late ViewportController controller;
  late GlobalKey<_ListHostState> key;
  late TuiTestApp app;

  setUp(() {
    controller = ViewportController(
      contentExtent: 20,
      viewportExtent: 3,
      scrollOffset: 8,
    );
    key = GlobalKey<_ListHostState>();
    app = createTuiTestApp(
      _ListHost(key: key, controller: controller),
      width: 20,
      height: 3,
    );
    app.pumpFrame();
  });

  tearDown(() {
    app.dispose();
    controller.dispose();
  });

  test('plain mount preserves the supplied window', () {
    expect(controller.scrollOffset, 8);
    _expectWindow(app, 8);
  });

  test(
    'plain count changes preserve the window and clamp only when needed',
    () {
      controller.jumpTo(8);
      app.pumpFrame();
      _expectWindow(app, 8);

      for (final count in [21, 18, 10]) {
        key.currentState!.change(() => key.currentState!.itemCount = count);
        app.pumpFrame();
        final expectedOffset = count == 10 ? 7 : 8;
        expect(controller.scrollOffset, expectedOffset);
        _expectWindow(app, expectedOffset);
      }
    },
  );

  test(
    'plain controller replacement uses its position and removes old listener',
    () {
      final replacement = ViewportController(
        contentExtent: 20,
        viewportExtent: 3,
        scrollOffset: 11,
      );
      expect(controller.hasListeners, isTrue);
      expect(replacement.hasListeners, isFalse);
      try {
        key.currentState!.change(
          () => key.currentState!.controller = replacement,
        );
        app.pumpFrame();
        expect(controller.hasListeners, isFalse);
        expect(replacement.hasListeners, isTrue);
        expect(replacement.scrollOffset, 11);
        _expectWindow(app, 11);

        controller.jumpTo(2);
        app.pumpFrame();
        _expectWindow(app, 11);
        app.dispose();
        expect(replacement.hasListeners, isFalse);
        expect(
          replacement.jumpTo(12),
          isTrue,
          reason: 'the list borrows its caller-owned controller',
        );
      } finally {
        app.dispose();
        replacement.dispose();
      }
    },
  );

  test(
    'leaving selection preserves the window and entering it follows selection',
    () {
      key.currentState!.change(() => key.currentState!.selectedIndex = 14);
      app.pumpFrame();
      expect(controller.scrollOffset, 12);
      _expectWindow(app, 12);

      key.currentState!.change(() => key.currentState!.selectedIndex = null);
      app.pumpFrame();
      expect(controller.scrollOffset, 12);
      _expectWindow(app, 12);

      key.currentState!.change(() => key.currentState!.selectedIndex = 4);
      app.pumpFrame();
      expect(controller.scrollOffset, 4);
      _expectWindow(app, 4);
    },
  );

  for (final changeItemExtent in [false, true]) {
    test(
      'paired extents preserve a valid offset (item extent: $changeItemExtent)',
      () {
        key.currentState!.change(() {
          key.currentState!
            ..itemCount = 10
            ..height = changeItemExtent ? 3 : 1
            ..itemExtent = changeItemExtent ? 3 : 1;
        });
        app.pumpFrame();
        expect(controller.viewportExtent, 1);
        expect(controller.scrollOffset, 8);
        expect(app.captureFrame().toLines().first, 'item 8');

        key.currentState!.change(() {
          key.currentState!
            ..itemCount = 20
            ..height = 3
            ..itemExtent = 1;
        });
        app.pumpFrame();
        expect(controller.viewportExtent, 3);
        expect(controller.scrollOffset, 8);
        _expectWindow(app, 8);
      },
    );
  }

  test('controller and selection change use the new highlight together', () {
    key.currentState!.change(() => key.currentState!.selectedIndex = 1);
    app.pumpFrame();
    final replacement = ViewportController(
      contentExtent: 20,
      viewportExtent: 3,
      scrollOffset: 8,
    );
    try {
      key.currentState!.change(() {
        key.currentState!
          ..controller = replacement
          ..selectedIndex = 9;
      });
      app.pumpFrame();
      expect(
        replacement.scrollOffset,
        8,
        reason: 'the new highlight was already inside the supplied window',
      );
      _expectWindow(app, 8);
    } finally {
      app.dispose();
      replacement.dispose();
    }
  });
}

void _expectWindow(TuiTestApp app, int first) {
  final frame = app.captureFrame();
  expect(frame, BufferMatchers.hasCharAt(0, 0, 'i'));
  expect(frame.toLines(), [
    for (var index = first; index < first + 3; index++) 'item $index',
  ]);
}

class _ListHost extends StatefulWidget {
  const _ListHost({required this.controller, super.key});

  final ViewportController controller;

  @override
  State<_ListHost> createState() => _ListHostState();
}

class _ListHostState extends State<_ListHost> {
  late ViewportController controller;
  int itemCount = 20;
  int height = 3;
  int itemExtent = 1;
  int? selectedIndex;

  @override
  void initState() {
    super.initState();
    controller = widget.controller;
  }

  void change(VoidCallback update) => setState(update);

  @override
  Widget build(BuildContext context) => ListView(
    itemCount: itemCount,
    height: height,
    itemExtent: itemExtent,
    controller: controller,
    selectedIndex: selectedIndex,
    itemBuilder: (context, index, selected) => Text('item $index'),
  );
}
