import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart'
    show Axis, PaintingContext, RenderBox, RenderFlex;
import 'package:noir/src/painting/tui_canvas.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/widget_tester.dart';

void main() {
  group('RenderFlex correctness', () {
    test('invalid removal preserves the live child edge and flex metadata', () {
      final liveChild = _FlexRemovalProbeBox();
      final nonChild = _FlexRemovalProbeBox();
      final flex = RenderFlex(direction: Axis.horizontal)
        ..add(liveChild, flex: 1, fit: FlexFit.tight)
        ..layout(const BoxConstraints.tight(width: 4, height: 1));
      expect(liveChild.width, 4);

      expect(() => flex.remove(nonChild), throwsStateError);

      expect(liveChild.parent, same(flex));
      expect(flex.childrenBoxes.single, same(liveChild));
      flex.layout(const BoxConstraints.tight(width: 6, height: 1));
      expect(liveChild.width, 6);
    });

    test('overflow clip restores the canvas when a child paint throws', () {
      final flex = RenderFlex(direction: Axis.vertical)
        ..add(_ThrowingPaintBox())
        ..add(_ThrowingPaintBox())
        ..layout(const BoxConstraints.tight(width: 1, height: 1));

      final canvas = createTuiCanvas();
      expect(
        () => flex.paint(PaintingContext(canvas), Offset.zero),
        throwsStateError,
      );
      expect(
        canvas.restore,
        throwsStateError,
        reason: 'a leftover save would let restore succeed',
      );
    });

    group('min constraint handling', () {
      late WidgetTester tester;

      setUp(() {
        tester = WidgetTester(maxWidth: 40, maxHeight: 20);
      });

      tearDown(() {
        tester.dispose();
      });

      test('vertical Column with MainAxisSize.min respects minHeight', () {
        // This test verifies that vertical flex uses minHeight, not minWidth
        // for the min main axis constraint
        const widget = ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 40,
            minHeight: 10,
            maxHeight: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [Text('A'), Text('B')],
          ),
        );

        tester.pumpWidget(widget);

        // The Column should respect the minHeight of 10, not collapse to content height
        expect(
          tester.height,
          greaterThanOrEqualTo(10),
          reason: 'Column should respect minHeight constraint from parent',
        );
      });

      test('horizontal Row with MainAxisSize.min respects minWidth', () {
        // Control test - horizontal should use minWidth correctly
        const widget = ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 20,
            maxWidth: 40,
            maxHeight: 20,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text('A'), Text('B')],
          ),
        );

        tester.pumpWidget(widget);

        // The Row should respect the minWidth of 20
        expect(
          tester.width,
          greaterThanOrEqualTo(20),
          reason: 'Row should respect minWidth constraint from parent',
        );
      });
    });

    group('spacing calculation', () {
      late BufferCapture capture;

      setUp(() {
        // Keep the buffer small so spacing/available-space bugs are observable.
        capture = BufferCapture(width: 10, height: 5);
      });

      tearDown(() {
        capture.dispose();
      });

      test('Row spacing does not double-count total spacing', () {
        // This test verifies that spacing is not subtracted twice when
        // calculating available space for non-flexible children.
        // With double-counting, the second child would be constrained too tightly
        // and its text would wrap/truncate.
        const widget = Row(
          spacing: 2,
          children: [
            Text('AAAA'), // 4 chars
            Text('BBBB'), // 4 chars
          ],
        );

        final result = capture.capture(widget);
        final lines = result.toLines();

        // With 2-char spacing between 3 items, we expect:
        // AAAA__BBBB (where __ is 2 spaces) -> exactly 10 chars.
        expect(lines[0], equals('AAAA  BBBB'));
      });

      test('Column spacing does not double-count total spacing', () {
        // Same test for vertical direction
        const widget = Column(
          spacing: 1,
          children: [Text('Line 1'), Text('Line 2'), Text('Line 3')],
        );

        final result = capture.capture(widget);
        final lines = result.toLines();

        // Expect:
        // 0: Line 1
        // 1:
        // 2: Line 2
        // 3:
        // 4: Line 3
        expect(lines[0], equals('Line 1'));
        expect(lines[1], equals(''));
        expect(lines[2], equals('Line 2'));
        expect(lines[3], equals(''));
        expect(lines[4], equals('Line 3'));
      });
    });

    group('non-flex child sizing', () {
      late BufferCapture capture;

      setUp(() {
        capture = BufferCapture(width: 40, height: 12);
      });

      tearDown(() {
        capture.dispose();
      });

      test(
        'Column shrink-wraps decorated non-flex children on the main axis',
        () {
          final result = capture.capture(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldBox(label: 'Name', value: 'Ada Lovelace'),
                const _FieldBox(label: 'Email', value: 'ada@example.dev'),
                Container(
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    border: Border.all(color: Color.white),
                  ),
                  child: const Text('Saved'),
                ),
              ],
            ),
          );

          expect(result, BufferMatchers.containsText('Name'));
          expect(result, BufferMatchers.containsText('Email'));
          expect(result, BufferMatchers.containsText('Saved'));
        },
      );

      test(
        'empty decorated Container keeps explicit extent inside centered Column',
        () {
          final result = capture.capture(
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.all(1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Pulse'),
                  Container(
                    width: 12,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Color(0.2, 0.3, 0.6),
                      border: Border.all(color: Color.white),
                    ),
                  ),
                  const Text('value: 0.50'),
                ],
              ),
            ),
          );

          final topLeft = _findChar(result, '┌');
          expect(topLeft, isNotNull, reason: result.toText());
          expect(
            result.getChar(topLeft!.x + 11, topLeft.y),
            '┐',
            reason: result.toText(),
          );
          expect(
            result.getChar(topLeft.x, topLeft.y + 3),
            '└',
            reason: result.toText(),
          );
          expect(
            result.getChar(topLeft.x + 11, topLeft.y + 3),
            '┘',
            reason: result.toText(),
          );
          expect(result, BufferMatchers.containsText('value: 0.50'));
        },
      );

      test('overflowing Column clips its children to its own bounds', () {
        // The inner Column has room for two rows but three rows of content.
        // Without a clip its third row would paint into the sibling's row and
        // interleave with the later-painted 'ZZZ' ('ZZZCC'), which is the
        // small-terminal corruption observed in example/counter.dart at 24x8.
        final result = capture.capture(
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 10,
                  maxWidth: 10,
                  minHeight: 2,
                  maxHeight: 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text('AAAAA'), Text('BBBBB'), Text('CCCCC')],
                ),
              ),
              Text('ZZZ'),
            ],
          ),
        );

        final lines = result.toLines();
        expect(lines[0], 'AAAAA');
        expect(lines[1], 'BBBBB');
        expect(
          lines[2],
          'ZZZ',
          reason:
              'the clipped third row must not interleave with the sibling: '
              '${result.toText()}',
        );
        expect(result.findText('CCCCC'), isEmpty);
      });

      test('overflowing Row clips its children to its own bounds', () {
        final result = capture.capture(
          const Row(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 4,
                  maxWidth: 4,
                  minHeight: 1,
                  maxHeight: 1,
                ),
                child: Row(children: [Text('ABCDEFG')]),
              ),
              Text('XY'),
            ],
          ),
        );

        expect(
          result.toLines().first,
          'ABCDXY',
          reason:
              'the overflowing text must stop at its Row, not resume past '
              'the sibling: ${result.toText()}',
        );
      });

      test('a Column that fits paints without any clip taking effect', () {
        final result = capture.capture(
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text('one'), Text('two')],
          ),
        );

        expect(result.toLines()[0], 'one');
        expect(result.toLines()[1], 'two');
      });

      test('Align shrink-wraps unbounded Column height to avoid overlap', () {
        final result = capture.capture(
          const Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Text('Single Child')],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Nested Align'),
                ),
              ),
              Text('After Align'),
            ],
          ),
        );

        final single = result.findText('Single Child').single;
        final nested = result.findText('Nested Align').single;
        final after = result.findText('After Align').single;
        expect(nested.y, greaterThan(single.y));
        expect(after.y, greaterThan(nested.y));
      });
    });
  });
}

class _ThrowingPaintBox extends RenderBox {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(constraints.constrainWidth(1), constraints.constrainHeight(1));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    throw StateError('child paint failed');
  }
}

class _FlexRemovalProbeBox extends RenderBox {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(constraints.constrainWidth(1), constraints.constrainHeight(1));
  }
}

class _FieldBox extends StatelessWidget {
  const _FieldBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(1),
    decoration: BoxDecoration(border: Border.all(color: Color.white)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(label), Text(value)],
    ),
  );
}

BufferPosition? _findChar(CapturedBuffer buffer, String char) {
  for (var y = 0; y < buffer.height; y++) {
    for (var x = 0; x < buffer.width; x++) {
      if (buffer.getChar(x, y) == char) {
        return BufferPosition(x, y);
      }
    }
  }
  return null;
}
