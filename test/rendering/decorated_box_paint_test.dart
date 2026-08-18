// Paint contract for `RenderDecoratedBox`: a child that fills the box must not
// overwrite the cells the decoration reserves for its border.
//
// `DecoratedBox` deliberately does not inset its child's layout constraints
// (that is `Container`'s job, via its `max(padding, border)` rule), so a child
// sized to the full box still lays out over the border cells. The render object
// therefore clips the child's paint to the decoration's inner rect.

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

/// A child that paints a solid block of `X` over every cell it is given.
Widget _filler(int rows) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: List<Widget>.generate(rows, (_) => const Text('XXXXXXXXXXXX')),
);

void main() {
  group('RenderDecoratedBox paint clip', () {
    late BufferCapture capture;

    setUp(() {
      capture = BufferCapture(
        width: 12,
        height: 4,
        layoutConstraints: const BoxConstraints.tight(width: 12, height: 4),
      );
    });

    tearDown(() => capture.dispose());

    test('background decoration keeps its border above a filling child', () {
      final captured = capture.capture(
        DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: Color.white)),
          child: _filler(4),
        ),
      );

      expect(
        captured.toLines(),
        ['┌──────────┐', '│XXXXXXXXXX│', '│XXXXXXXXXX│', '└──────────┘'],
        reason:
            'child paint must stop at the border cells, but got:\n'
            '${captured.toText()}',
      );
    });

    test('foreground decoration renders the same border', () {
      final captured = capture.capture(
        DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: Color.white)),
          position: DecorationPosition.foreground,
          child: _filler(4),
        ),
      );

      expect(
        captured.toLines(),
        ['┌──────────┐', '│XXXXXXXXXX│', '│XXXXXXXXXX│', '└──────────┘'],
        reason:
            'foreground repaint already covered the perimeter; the clip '
            'must not change it, but got:\n${captured.toText()}',
      );
    });

    test('a partial border only reserves the sides it draws', () {
      final captured = capture.capture(
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              color: Color.white,
              sides: const BorderSides(
                right: false,
                bottom: false,
                left: false,
              ),
            ),
          ),
          child: _filler(4),
        ),
      );

      // With the left and right sides off, the pinned `drawBox` emits no
      // corner glyphs, so the reserved top row is a full run of `─`. Only that
      // one row is reserved, so the child keeps the full width and every
      // remaining row including the bottom one.
      expect(
        captured.toLines(),
        ['────────────', 'XXXXXXXXXXXX', 'XXXXXXXXXXXX', 'XXXXXXXXXXXX'],
        reason:
            'a top-only border reserves exactly one row, but got:\n'
            '${captured.toText()}',
      );
    });
  });

  // A box smaller than its own border leaves an empty inner rect. With no
  // enclosing clip the rect is negative rather than zero-size, so pin that it
  // still drops all child paint instead of throwing or leaking cells.
  group('RenderDecoratedBox degenerate sizes', () {
    for (final entry in const {
      1: ['└'],
      2: ['┌┐', '└┘'],
      3: ['┌─┐', '│X│', '└─┘'],
    }.entries) {
      final size = entry.key;
      test('a ${size}x$size bordered box drops the overflowing child', () {
        final capture = BufferCapture(
          width: size,
          height: size,
          layoutConstraints: BoxConstraints.tight(width: size, height: size),
        );
        addTearDown(capture.dispose);

        final captured = capture.capture(
          DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: Color.white)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List<Widget>.generate(size, (_) => Text('X' * size)),
            ),
          ),
        );

        expect(
          captured.toLines(),
          entry.value,
          reason:
              'no child cell may survive outside the inner rect, but got:\n'
              '${captured.toText()}',
        );
      });
    }
  });
}
