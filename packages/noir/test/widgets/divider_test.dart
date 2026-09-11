import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  group('Divider', () {
    test('spans the full width of a loosely constrained column', () {
      final capture = BufferCapture(width: 8, height: 3);
      try {
        final frame = capture.capture(
          const Column(
            children: [
              Text('ab'),
              Divider(color: Color.magenta),
              Text('cd'),
            ],
          ),
        );
        for (var x = 0; x < 8; x++) {
          expect(
            frame,
            BufferMatchers.hasBackgroundAt(x, 1, Color.magenta),
            reason: 'column $x',
          );
        }
      } finally {
        capture.dispose();
      }
    });

    test('thickness sets how many rows the rule fills', () {
      final capture = BufferCapture(width: 4, height: 4);
      try {
        final frame = capture.capture(
          const Column(
            children: [
              Divider(thickness: 2, color: Color.magenta),
              Text('z'),
            ],
          ),
        );
        expect(frame, BufferMatchers.hasBackgroundAt(0, 0, Color.magenta));
        expect(frame, BufferMatchers.hasBackgroundAt(0, 1, Color.magenta));
        expect(
          frame,
          isNot(BufferMatchers.hasBackgroundAt(0, 2, Color.magenta)),
        );
      } finally {
        capture.dispose();
      }
    });

    test('a vertical rule spans the height of a row', () {
      final capture = BufferCapture(width: 5, height: 3);
      try {
        final frame = capture.capture(
          const Row(
            children: [
              Text('a'),
              Divider(axis: Axis.vertical, color: Color.magenta),
              Text('b'),
            ],
          ),
        );
        for (var y = 0; y < 3; y++) {
          expect(
            frame,
            BufferMatchers.hasBackgroundAt(1, y, Color.magenta),
            reason: 'row $y',
          );
        }
      } finally {
        capture.dispose();
      }
    });

    test('an unbounded cross axis leaves the rule with nothing to fill', () {
      // A Row inside a Column hands its children an unbounded height, so the
      // rule has no extent to span. Callers give it one with a SizedBox.
      final capture = BufferCapture(width: 5, height: 3);
      try {
        final bare = capture.capture(
          const Column(
            children: [
              Row(
                children: [
                  Text('a'),
                  Divider(axis: Axis.vertical, color: Color.magenta),
                  Text('b'),
                ],
              ),
            ],
          ),
        );
        expect(
          bare,
          isNot(BufferMatchers.hasBackgroundAt(1, 0, Color.magenta)),
        );

        final sized = capture.capture(
          const Column(
            children: [
              Row(
                children: [
                  Text('a'),
                  SizedBox(
                    height: 2,
                    child: Divider(axis: Axis.vertical, color: Color.magenta),
                  ),
                  Text('b'),
                ],
              ),
            ],
          ),
        );
        expect(sized, BufferMatchers.hasBackgroundAt(1, 0, Color.magenta));
        expect(sized, BufferMatchers.hasBackgroundAt(1, 1, Color.magenta));
      } finally {
        capture.dispose();
      }
    });

    test('the fill falls back to the theme border token', () {
      final capture = BufferCapture(width: 4, height: 1);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(border: Color.magenta),
            child: const Column(children: [Divider()]),
          ),
        );
        expect(frame, BufferMatchers.hasBackgroundAt(0, 0, Color.magenta));
      } finally {
        capture.dispose();
      }
    });
  });
}
