import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  group('MouseScroll', () {
    test('retains all four directions', () {
      for (final direction in MouseScrollDirection.values) {
        expect(MouseScroll(direction: direction).direction, direction);
      }
    });

    test('defaults to one tick and retains a larger magnitude', () {
      expect(MouseScroll(direction: MouseScrollDirection.up).magnitude, 1);
      expect(
        MouseScroll(
          direction: MouseScrollDirection.right,
          magnitude: 3,
        ).magnitude,
        3,
      );
    });

    test('rejects zero and negative magnitudes in all build modes', () {
      expect(
        () => MouseScroll(direction: MouseScrollDirection.down, magnitude: 0),
        throwsRangeError,
      );
      expect(
        () => MouseScroll(direction: MouseScrollDirection.left, magnitude: -1),
        throwsRangeError,
      );
    });
  });

  group('MouseEvent scroll payload', () {
    test('scroll events require a payload', () {
      expect(
        () => MouseEvent(
          type: MouseEventType.scroll,
          button: MouseButton.left,
          x: 0,
          y: 0,
        ),
        throwsArgumentError,
      );
    });

    test('non-scroll events reject a payload', () {
      expect(
        () => MouseEvent(
          type: MouseEventType.move,
          button: MouseButton.left,
          x: 0,
          y: 0,
          scroll: MouseScroll(direction: MouseScrollDirection.up),
        ),
        throwsArgumentError,
      );
    });

    test('non-scroll events without a payload remain valid', () {
      final event = MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 2,
        y: 3,
      );

      expect(event.scroll, isNull);
      expect(event.localPosition, const Offset(2, 3));
    });
  });
}
