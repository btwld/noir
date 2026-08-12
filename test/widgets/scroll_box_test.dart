// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

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
  });
}
