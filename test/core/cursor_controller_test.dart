// ignore_for_file: cascade_invocations
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

void main() {
  group('CursorController', () {
    test('gracefully handles show/hide without renderer', () {
      final controller = CursorController();
      final owner = Object();

      expect(() => controller.showCursor(owner, 1, 1), returnsNormally);
      expect(controller.isVisible, isTrue);

      expect(() => controller.hideCursorFor(owner), returnsNormally);
      expect(controller.isVisible, isFalse);
    });

    test('attaches to renderer and hides on detach', () {
      final renderer = Renderer.create(4, 2, testing: true);
      final controller = CursorController();
      final owner = Object();

      controller.attachRenderer(renderer);
      controller.showCursor(owner, 1, 0);
      expect(controller.isVisible, isTrue);

      controller.detachRenderer();
      expect(controller.isVisible, isFalse);

      renderer.dispose();
    });

    test('dispose hides cursor and is idempotent', () {
      final controller = CursorController();
      final owner = Object();

      controller.showCursor(owner, 1, 0);
      expect(controller.isVisible, isTrue);

      controller
        ..dispose()
        ..dispose();

      expect(controller.isVisible, isFalse);
      expect(controller.owner, isNull);
    });
  });
}
