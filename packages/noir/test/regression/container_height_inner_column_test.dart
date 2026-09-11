// Regression test for layout_demo.dart bug where
//   Container(height: 4, padding: EdgeInsets.all(1),
//            decoration: BoxDecoration(border: Border.all(...)),
//            child: Column(crossAxisAlignment: stretch,
//              children: [Text(label), Expanded(Row([colored boxes]))]))
// rendered an empty outlined rectangle: no label, no colored cells.
//
// The root cause was Container layering an inner Padding for
// `padding + decoration.padding` (= 1 + 1 = 2 cells on every side), which
// consumed the entire 4-row height and left zero rows for content. The fix
// is to use max(padding, border-thickness) instead of summing them so the
// explicit padding still leaves room for content inside a bordered box.

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  test(
    'Container(height: 4) with border + padding renders label and colored row',
    () {
      final capture = BufferCapture(width: 40, height: 6);
      try {
        final captured = capture.capture(
          Container(
            height: 4,
            padding: EdgeInsets.all(1),
            decoration: BoxDecoration(border: Border.all(color: Color.white)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Start'),
                Expanded(
                  child: Row(
                    children: const [
                      _Block(label: 'A', color: Color(0.9, 0.3, 0.3), width: 5),
                      _Block(label: 'B', color: Color(0.3, 0.9, 0.3), width: 5),
                      _Block(label: 'C', color: Color(0.3, 0.5, 0.9), width: 5),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

        // Label should be visible inside the bordered box.
        expect(
          captured,
          BufferMatchers.containsText('Start'),
          reason:
              'Expected the label "Start" to render inside the 4-row '
              'bordered Container, but the buffer was:\n${captured.toText()}',
        );

        // At least one colored block cell should exist (the red/green/blue
        // background of _Block A/B/C). Buffer stores colors as 8-bit
        // channels so we tolerate small differences from the source RGB
        // floats: a cell counts as "colored" when its background is neither
        // the cleared default (black) nor a uniform gray.
        var foundColoredCell = false;
        const black = Color.black;
        outer:
        for (var y = 0; y < captured.height; y++) {
          for (var x = 0; x < captured.width; x++) {
            final bg = captured.getBackgroundColor(x, y);
            if (bg == black) continue;
            // A coloured block has uneven RGB components (warm red, green,
            // or cool blue). Skip near-gray cells like borders or padding.
            final r = bg.r;
            final g = bg.g;
            final b = bg.b;
            final maxC = [r, g, b].reduce((a, b) => a > b ? a : b);
            final minC = [r, g, b].reduce((a, b) => a < b ? a : b);
            if (maxC - minC > 0.2) {
              foundColoredCell = true;
              break outer;
            }
          }
        }
        expect(
          foundColoredCell,
          isTrue,
          reason:
              'Expected at least one colored _Block cell to render inside '
              'the bordered Container, but the buffer was:\n${captured.toText()}',
        );
      } finally {
        capture.dispose();
      }
    },
  );
}

class _Block extends StatelessWidget {
  const _Block({required this.label, required this.color, required this.width});

  final String label;
  final Color color;
  final int width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    alignment: Alignment.center,
    color: color,
    child: Text(label),
  );
}
