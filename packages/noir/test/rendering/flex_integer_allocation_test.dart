import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/rendering/object.dart' show PipelineOwner;
import 'package:test/test.dart';

void main() {
  group('bounded integer flex allocation', () {
    test('odd cells are assigned exactly in document order', () {
      final first = _ProbeBox();
      final second = _ProbeBox();
      final flex = RenderFlex(direction: Axis.horizontal)
        ..add(first, flex: 1, fit: FlexFit.tight)
        ..add(second, flex: 1, fit: FlexFit.tight);

      flex.layout(const BoxConstraints.tight(width: 5, height: 1));

      expect([first.width, second.width], [3, 2]);
      expect([first.x, second.x], [0, 3]);
      expect(flex.size, const Size(5, 1));
    });

    test('weighted remainder uses residue then document order', () {
      final children = List<_ProbeBox>.generate(3, (_) => _ProbeBox());
      final flex = RenderFlex(direction: Axis.horizontal)
        ..add(children[0], flex: 1, fit: FlexFit.tight)
        ..add(children[1], flex: 2, fit: FlexFit.tight)
        ..add(children[2], flex: 3, fit: FlexFit.tight);

      flex.layout(const BoxConstraints.tight(width: 11, height: 1));

      expect(children.map((child) => child.width), [2, 4, 5]);
      expect(children.map((child) => child.x), [0, 2, 6]);
    });

    test('weight sums and products do not overflow native int', () {
      final first = _ProbeBox();
      final second = _ProbeBox();
      final hugeWeight = 1 << 62;
      final flex = RenderFlex(direction: Axis.horizontal)
        ..add(first, flex: hugeWeight, fit: FlexFit.tight)
        ..add(second, flex: hugeWeight, fit: FlexFit.tight);

      flex.layout(const BoxConstraints.tight(width: 7, height: 1));

      expect([first.width, second.width], [4, 3]);
      expect([first.x, second.x], [0, 4]);
    });

    test('spacing is reserved once before weighted allocation', () {
      final fixed = _ProbeBox(naturalWidth: 2);
      final loose = _ProbeBox(naturalWidth: 1);
      final tight = _ProbeBox();
      final flex =
          RenderFlex(
              direction: Axis.horizontal,
              spacing: 1,
              mainAxisAlignment: MainAxisAlignment.end,
            )
            ..add(fixed)
            ..add(loose, flex: 1, fit: FlexFit.loose)
            ..add(tight, flex: 2, fit: FlexFit.tight);

      flex.layout(const BoxConstraints.tight(width: 13, height: 1));

      expect([fixed.width, loose.width, tight.width], [2, 1, 6]);
      expect([fixed.x, loose.x, tight.x], [2, 5, 7]);
    });

    test('zero remainder gives every tight child tight zero', () {
      final first = _ProbeBox();
      final second = _ProbeBox();
      final flex = RenderFlex(direction: Axis.horizontal, spacing: 2)
        ..add(_ProbeBox(naturalWidth: 4))
        ..add(first, flex: 1, fit: FlexFit.tight)
        ..add(second, flex: 1, fit: FlexFit.tight);

      flex.layout(const BoxConstraints.tight(width: 4, height: 1));

      expect(first.lastConstraints?.minWidth, 0);
      expect(first.lastConstraints?.maxWidth, 0);
      expect(second.lastConstraints?.minWidth, 0);
      expect(second.lastConstraints?.maxWidth, 0);
      expect(flex.width, 4);
    });

    test('MainAxisSize.min reports a constrained size under overflow', () {
      final first = _ProbeBox(naturalWidth: 8);
      final second = _ProbeBox(naturalWidth: 8);
      final flex =
          RenderFlex(
              direction: Axis.horizontal,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
            )
            ..add(first)
            ..add(second);

      flex.layout(const BoxConstraints(maxWidth: 10, maxHeight: 1));

      expect(flex.width, 10);
      expect([first.x, second.x], [0, 8]);
    });

    test('integer center gives the odd leading cell to the first slot', () {
      final child = _ProbeBox(naturalWidth: 2);
      final flex = RenderFlex(
        direction: Axis.horizontal,
        mainAxisAlignment: MainAxisAlignment.center,
      )..add(child);

      flex.layout(const BoxConstraints.tight(width: 5, height: 1));

      expect(child.x, 2);
    });

    test('spaceAround accounts for every odd slack cell', () {
      final children = List<_ProbeBox>.generate(
        3,
        (_) => _ProbeBox(naturalWidth: 1),
      );
      final flex = RenderFlex(
        direction: Axis.horizontal,
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        spacing: 1,
      )..addAll(children);

      flex.layout(const BoxConstraints.tight(width: 10, height: 1));

      expect(children.map((child) => child.x), [1, 5, 8]);
      expect(flex.width, 10);
    });

    test('all alignments own exact leading and internal cells', () {
      final expected = <MainAxisAlignment, List<int>>{
        MainAxisAlignment.start: [0, 1, 2],
        MainAxisAlignment.end: [7, 8, 9],
        MainAxisAlignment.center: [4, 5, 6],
        MainAxisAlignment.spaceBetween: [0, 5, 9],
        MainAxisAlignment.spaceAround: [1, 5, 8],
        MainAxisAlignment.spaceEvenly: [2, 5, 8],
      };

      for (final MapEntry(key: alignment, value: positions)
          in expected.entries) {
        final children = List<_ProbeBox>.generate(
          3,
          (_) => _ProbeBox(naturalWidth: 1),
        );
        final flex = RenderFlex(
          direction: Axis.horizontal,
          mainAxisAlignment: alignment,
        )..addAll(children);

        flex.layout(const BoxConstraints.tight(width: 10, height: 1));

        expect(
          children.map((child) => child.x),
          positions,
          reason: '$alignment',
        );
      }
    });

    test('zero, one, and two child alignment slots are explicit', () {
      final oneExpected = <MainAxisAlignment, int>{
        MainAxisAlignment.start: 0,
        MainAxisAlignment.end: 6,
        MainAxisAlignment.center: 3,
        MainAxisAlignment.spaceBetween: 0,
        MainAxisAlignment.spaceAround: 3,
        MainAxisAlignment.spaceEvenly: 3,
      };
      final twoExpected = <MainAxisAlignment, List<int>>{
        MainAxisAlignment.start: [0, 2],
        MainAxisAlignment.end: [4, 6],
        MainAxisAlignment.center: [2, 4],
        MainAxisAlignment.spaceBetween: [0, 6],
        MainAxisAlignment.spaceAround: [1, 5],
        MainAxisAlignment.spaceEvenly: [2, 5],
      };
      for (final alignment in MainAxisAlignment.values) {
        final empty = RenderFlex(
          direction: Axis.horizontal,
          mainAxisAlignment: alignment,
        );
        empty.layout(const BoxConstraints.tight(width: 7, height: 1));
        expect(empty.width, 7, reason: 'empty $alignment');

        final only = _ProbeBox(naturalWidth: 1);
        final one = RenderFlex(
          direction: Axis.horizontal,
          mainAxisAlignment: alignment,
        )..add(only);
        one.layout(const BoxConstraints.tight(width: 7, height: 1));
        expect(only.x, oneExpected[alignment], reason: 'one $alignment');

        final children = [
          _ProbeBox(naturalWidth: 1),
          _ProbeBox(naturalWidth: 1),
        ];
        final two = RenderFlex(
          direction: Axis.horizontal,
          mainAxisAlignment: alignment,
          spacing: 1,
        )..addAll(children);
        two.layout(const BoxConstraints.tight(width: 7, height: 1));
        expect(
          children.map((child) => child.x),
          twoExpected[alignment],
          reason: 'two $alignment',
        );
      }
    });

    test('vertical alignment uses the same exact slot allocation', () {
      final children = List<_VerticalProbeBox>.generate(
        3,
        (_) => _VerticalProbeBox(naturalHeight: 1),
      );
      final flex = RenderFlex(
        direction: Axis.vertical,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
      )..addAll(children);

      flex.layout(const BoxConstraints.tight(width: 1, height: 10));

      expect(children.map((child) => child.y), [0, 5, 9]);
    });

    test('odd cross-axis center gives the extra cell to leading', () {
      final child = _ProbeBox(naturalWidth: 1);
      final flex = RenderFlex(direction: Axis.horizontal)..add(child);

      flex.layout(const BoxConstraints.tight(width: 1, height: 4));

      expect(child.y, 2);
    });

    test('MainAxisSize.min clamps below, within, and above bounds', () {
      for (final (natural, expected) in [(2, 5), (7, 7), (12, 10)]) {
        final child = _ProbeBox(naturalWidth: natural);
        final flex = RenderFlex(
          direction: Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
        )..add(child);

        flex.layout(
          const BoxConstraints(minWidth: 5, maxWidth: 10, maxHeight: 1),
        );

        expect(flex.width, expected, reason: 'natural=$natural');
      }
    });

    test('fixed gaps may overflow while parent remains constrained', () {
      final children = List<_ProbeBox>.generate(3, (_) => _ProbeBox());
      final flex = RenderFlex(
        direction: Axis.horizontal,
        spacing: 3,
        mainAxisSize: MainAxisSize.min,
      )..addAll(children);

      flex.layout(const BoxConstraints.tight(width: 4, height: 1));

      expect(flex.width, 4);
      expect(children.map((child) => child.x), [0, 3, 6]);
    });

    test('loose unused quota becomes alignment slack for every mode', () {
      for (final alignment in MainAxisAlignment.values) {
        final child = _ProbeBox(naturalWidth: 1);
        final flex = RenderFlex(
          direction: Axis.horizontal,
          mainAxisAlignment: alignment,
        )..add(child, flex: 1, fit: FlexFit.loose);

        flex.layout(const BoxConstraints.tight(width: 9, height: 1));

        expect(child.width, 1, reason: '$alignment');
        expect(child.x, inInclusiveRange(0, 8), reason: '$alignment');
      }
    });

    test('small allocation table always sums to the requested total', () {
      const vectors = <List<int>>[
        [1],
        [1, 1],
        [1, 2, 3],
        [3, 1, 2, 4],
      ];
      for (var total = 0; total <= 13; total++) {
        for (final weights in vectors) {
          final children = List<_ProbeBox>.generate(
            weights.length,
            (_) => _ProbeBox(),
          );
          final flex = RenderFlex(direction: Axis.horizontal);
          for (var index = 0; index < children.length; index++) {
            flex.add(children[index], flex: weights[index], fit: FlexFit.tight);
          }

          flex.layout(BoxConstraints.tight(width: total, height: 1));

          expect(
            children.fold<int>(0, (sum, child) => sum + child.width),
            total,
            reason: 'total=$total weights=$weights',
          );
          expect(
            children.map((child) => child.width),
            everyElement(isNonNegative),
          );
        }
      }
    });
  });

  group('validation and failure atomicity', () {
    test('negative render spacing rejects before mutation or dirty work', () {
      expect(
        () => RenderFlex(direction: Axis.horizontal, spacing: -1),
        throwsArgumentError,
      );

      final flex = RenderFlex(direction: Axis.horizontal, spacing: 1);
      final owner = PipelineOwner();
      flex.attach(owner);
      owner
        ..flushLayout(flex, const BoxConstraints.tight(width: 4, height: 1))
        ..flushPaint(flex, (_) {});

      expect(() => flex.spacing = -1, throwsArgumentError);
      expect(flex.spacing, 1);
      expect(flex.debugNeedsLayout, isFalse);
      expect(owner.debugNeedsLayout, isFalse);
    });

    test('negative flex rejects before adoption and metadata mutation', () {
      final flex = RenderFlex(direction: Axis.horizontal);
      final child = _ProbeBox();

      expect(() => flex.add(child, flex: -1), throwsArgumentError);
      expect(child.parent, isNull);
      expect(flex.childrenBoxes, isEmpty);

      flex.add(child, flex: 1, fit: FlexFit.tight);
      flex.layout(const BoxConstraints.tight(width: 4, height: 1));
      expect(() => flex.add(child, flex: -1), throwsArgumentError);
      flex.layout(const BoxConstraints.tight(width: 5, height: 1));
      expect(child.width, 5);
    });

    test('zero is non-flex and positive absent fit remains loose', () {
      final zero = _ProbeBox(naturalWidth: 2);
      final loose = _ProbeBox(naturalWidth: 1);
      final flex = RenderFlex(direction: Axis.horizontal)
        ..add(zero, flex: 0, fit: FlexFit.tight)
        ..add(loose, flex: 1);

      flex.layout(const BoxConstraints.tight(width: 8, height: 1));

      expect(zero.width, 2);
      expect(loose.width, 1);
      expect(loose.lastConstraints?.minWidth, 0);
      expect(loose.lastConstraints?.maxWidth, 6);
    });

    test('public spacing and flex constructors diagnose invalid values', () {
      expect(() => Row(spacing: -1), throwsA(isA<AssertionError>()));
      expect(
        () => Flexible(child: const SizedBox(), flex: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Expanded(child: const SizedBox(), flex: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('fixed-gap overflow fails before child layout', () {
      final children = List<_ProbeBox>.generate(3, (_) => _ProbeBox());
      final flex = RenderFlex(
        direction: Axis.horizontal,
        spacing: (1 << 63) - 1,
      )..addAll(children);

      expect(
        () => flex.layout(const BoxConstraints.tight(width: 5, height: 1)),
        throwsStateError,
      );
      expect(children.map((child) => child.layoutCount), everyElement(0));
    });

    test('measured-position overflow stops before position assignment', () {
      final huge = 1 << 62;
      final first = _ProbeBox(naturalWidth: huge)..x = 7;
      final second = _ProbeBox(naturalWidth: huge)..x = 9;
      final flex = RenderFlex(direction: Axis.horizontal)
        ..add(first)
        ..add(second);

      expect(
        () => flex.layout(const BoxConstraints(maxHeight: 1)),
        throwsStateError,
      );
      expect([first.layoutCount, second.layoutCount], [1, 1]);
      expect([first.x, second.x], [7, 9]);
    });
  });

  group('unbounded main-axis semantics', () {
    test('Expanded Row fails before any child layout', () {
      final fixed = _ProbeBox(naturalWidth: 2);
      final expanded = _ProbeBox(naturalWidth: 3);
      final flex = RenderFlex(direction: Axis.horizontal)
        ..add(fixed)
        ..add(expanded, flex: 1, fit: FlexFit.tight);

      expect(
        () => flex.layout(const BoxConstraints(maxHeight: 1)),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'message',
                contains('RenderFlex children have non-zero flex'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('width constraints are unbounded'),
              )
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains('MainAxisSize.min'),
                  contains('FlexFit.loose'),
                  contains('Expanded'),
                ),
              ),
        ),
      );
      expect([fixed.layoutCount, expanded.layoutCount], [0, 0]);
    });

    test('loose min flex shrink-wraps natural sizes and spacing', () {
      final first = _ProbeBox(naturalWidth: 2);
      final second = _ProbeBox(naturalWidth: 3);
      final flex =
          RenderFlex(
              direction: Axis.horizontal,
              mainAxisSize: MainAxisSize.min,
              spacing: 1,
            )
            ..add(first, flex: 99, fit: FlexFit.loose)
            ..add(second, flex: 1, fit: FlexFit.loose);

      flex.layout(const BoxConstraints(maxHeight: 1));

      expect(flex.width, 6);
      expect([first.width, second.width], [2, 3]);
      expect([first.x, second.x], [0, 3]);
    });

    test('default max with loose flex still rejects before layout', () {
      final child = _ProbeBox(naturalWidth: 2);
      final flex = RenderFlex(direction: Axis.horizontal)
        ..add(child, flex: 1, fit: FlexFit.loose);

      expect(
        () => flex.layout(const BoxConstraints(maxHeight: 1)),
        throwsStateError,
      );
      expect(child.layoutCount, 0);
    });

    test('min with a mixed loose and tight set rejects before layout', () {
      final loose = _ProbeBox();
      final tight = _ProbeBox();
      final flex =
          RenderFlex(direction: Axis.horizontal, mainAxisSize: MainAxisSize.min)
            ..add(loose, flex: 1, fit: FlexFit.loose)
            ..add(tight, flex: 1, fit: FlexFit.tight);

      expect(
        () => flex.layout(const BoxConstraints(maxHeight: 1)),
        throwsStateError,
      );
      expect([loose.layoutCount, tight.layoutCount], [0, 0]);
    });

    test('without positive flex both main sizes shrink-wrap', () {
      for (final mainAxisSize in MainAxisSize.values) {
        final first = _ProbeBox(naturalWidth: 2);
        final second = _ProbeBox(naturalWidth: 3);
        final flex =
            RenderFlex(
                direction: Axis.horizontal,
                mainAxisSize: mainAxisSize,
                spacing: 1,
              )
              ..add(first)
              ..add(second, flex: 0, fit: FlexFit.tight);

        flex.layout(const BoxConstraints(maxHeight: 1));

        expect(flex.width, 6, reason: '$mainAxisSize');
        expect([first.x, second.x], [0, 3], reason: '$mainAxisSize');
      }
    });

    test('previous bounded geometry survives rejected unbounded layout', () {
      final child = _ProbeBox();
      final flex = RenderFlex(direction: Axis.vertical)
        ..add(child, flex: 1, fit: FlexFit.tight);
      flex.layout(const BoxConstraints.tight(width: 2, height: 5));
      final oldSize = flex.size;
      final oldChildSize = child.size;
      final oldPosition = (child.x, child.y);
      final oldLayouts = child.layoutCount;

      expect(
        () => flex.layout(const BoxConstraints(maxWidth: 2)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('height constraints are unbounded'),
          ),
        ),
      );

      expect(flex.size, oldSize);
      expect(child.size, oldChildSize);
      expect((child.x, child.y), oldPosition);
      expect(child.layoutCount, oldLayouts);
    });
  });
}

class _ProbeBox extends RenderBox {
  _ProbeBox({this.naturalWidth = 0});

  final int naturalWidth;
  int layoutCount = 0;
  BoxConstraints? lastConstraints;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    layoutCount++;
    lastConstraints = constraints;
    size = Size(
      constraints.constrainWidth(naturalWidth),
      constraints.constrainHeight(1),
    );
  }
}

class _VerticalProbeBox extends RenderBox {
  _VerticalProbeBox({required this.naturalHeight});

  final int naturalHeight;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(
      constraints.constrainWidth(1),
      constraints.constrainHeight(naturalHeight),
    );
  }
}
