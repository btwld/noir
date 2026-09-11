import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  group('ViewportController', () {
    test('jumpTo clamps to [0, maxScrollOffset]', () {
      final v = ViewportController(contentExtent: 10, viewportExtent: 3);
      // max scroll = 10 - 3 = 7
      expect(v.maxScrollOffset, 7);
      v.jumpTo(100);
      expect(v.scrollOffset, 7);
      v.jumpTo(-5);
      expect(v.scrollOffset, 0);
    });

    test('pageDown moves by viewportExtent and stops at the bottom', () {
      final v = ViewportController(contentExtent: 100, viewportExtent: 5);
      expect(v.scrollOffset, 0);
      v.pageDown();
      expect(v.scrollOffset, 5);
      v.pageDown();
      expect(v.scrollOffset, 10);
      // Clamp at maxScrollOffset = 95.
      while (v.scrollOffset < v.maxScrollOffset) {
        v.pageDown();
      }
      expect(v.scrollOffset, 95);
      // Already at bottom; pageDown is a no-op.
      v.pageDown();
      expect(v.scrollOffset, 95);
    });

    test('pageUp moves by viewportExtent and stops at the top', () {
      final v = ViewportController(
        contentExtent: 100,
        viewportExtent: 5,
        scrollOffset: 12,
      );
      v.pageUp();
      expect(v.scrollOffset, 7);
      v.pageUp();
      expect(v.scrollOffset, 2);
      v.pageUp();
      expect(v.scrollOffset, 0);
      v.pageUp();
      expect(v.scrollOffset, 0);
    });

    test('ensureVisible scrolls the minimum amount when item is below', () {
      final v = ViewportController(contentExtent: 20, viewportExtent: 5);
      // Item 7 is below viewport [0..5). Scroll so it's the last visible row.
      v.ensureVisible(7, 8);
      expect(v.scrollOffset, 3); // 7 - 5 + 1 = 3
    });

    test('ensureVisible scrolls the minimum amount when item is above', () {
      final v = ViewportController(
        contentExtent: 20,
        viewportExtent: 5,
        scrollOffset: 10,
      );
      v.ensureVisible(3, 4);
      expect(v.scrollOffset, 3); // top of viewport is item 3
    });

    test('ensureVisible is a no-op when item is already visible', () {
      final v = ViewportController(
        contentExtent: 20,
        viewportExtent: 5,
        scrollOffset: 5,
      );
      v.ensureVisible(7, 8); // 7 is in [5..10)
      expect(v.scrollOffset, 5);
    });

    test('viewportExtent change re-clamps the offset', () {
      final v = ViewportController(
        contentExtent: 10,
        viewportExtent: 3,
        scrollOffset: 7,
      );
      expect(v.scrollOffset, 7);
      // Grow viewport so maxScrollOffset shrinks to 5.
      v.viewportExtent = 5;
      expect(v.scrollOffset, 5);
    });

    test('notifies listeners when state changes', () {
      final v = ViewportController(contentExtent: 10, viewportExtent: 5);
      var calls = 0;
      v.addListener(() {
        calls++;
      });

      expect(v.jumpTo(1), isTrue);
      expect(v.scrollOffset, 1);
      expect(calls, 1);

      expect(v.jumpTo(1), isFalse);
      expect(calls, 1);

      v.contentExtent = 12;
      expect(calls, 2);

      v.viewportExtent = 20;
      expect(v.scrollOffset, 0);
      expect(calls, 3);
    });

    test('zero / degenerate viewport: paging is a no-op', () {
      final v = ViewportController(contentExtent: 10);
      // viewportExtent == 0 by default.
      expect(v.pageDown(), isFalse);
      expect(v.pageUp(), isFalse);
      expect(v.ensureVisible(5, 6), isFalse);
    });
  });
}
