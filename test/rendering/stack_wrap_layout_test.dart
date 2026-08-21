import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/rendering/stack.dart';
import 'package:noir/src/rendering/wrap.dart';
import 'package:test/test.dart';

import '../helpers/test_element_host.dart';

void main() {
  test('Stack lays out loose children and resolves opposing offsets', () {
    final natural = _FixedBox(3, 2);
    final positioned = _FixedBox(1, 1);
    final stack = RenderStack(children: <RenderBox>[natural])
      ..add(
        positioned,
        data: const StackChildData(left: 2, right: 1, top: 1, height: 2),
      );

    stack.layout(const BoxConstraints.tight(width: 10, height: 5));

    expect(stack.size, const Size(10, 5));
    expect(natural.size, const Size(3, 2));
    expect(positioned.size, const Size(7, 2));
    expect(Offset(positioned.x, positioned.y), const Offset(2, 1));
  });

  test('StackFit.expand gives non-positioned children the stack size', () {
    final child = _FixedBox(2, 1);
    final stack = RenderStack(
      children: <RenderBox>[child],
      fit: StackFit.expand,
    );

    stack.layout(const BoxConstraints.tight(width: 8, height: 4));

    expect(child.size, const Size(8, 4));
  });

  test('StackFit.loose shrink-wraps within loose maximum constraints', () {
    final child = _FixedBox(3, 2);
    final stack = RenderStack(children: <RenderBox>[child]);

    stack.layout(const BoxConstraints(maxWidth: 10, maxHeight: 6));

    expect(stack.size, const Size(3, 2));
    expect(child.size, const Size(3, 2));
  });

  test('StackFit.expand tightens each bounded axis independently', () {
    final child = _FixedBox(2, 1);
    final stack = RenderStack(
      children: <RenderBox>[child],
      fit: StackFit.expand,
    );

    stack.layout(const BoxConstraints(maxWidth: 8));

    expect(stack.size, const Size(8, 1));
    expect(child.size, const Size(8, 1));
  });

  test('horizontal Wrap creates runs and applies spacing', () {
    final children = <RenderBox>[
      _FixedBox(3, 1),
      _FixedBox(3, 1),
      _FixedBox(2, 1),
    ];
    final wrap = RenderWrap(spacing: 1, runSpacing: 1, children: children);

    wrap.layout(const BoxConstraints(maxWidth: 7));

    expect(wrap.size, const Size(7, 3));
    expect(
      children.map((child) => Offset(child.x, child.y)).toList(),
      const <Offset>[Offset.zero, Offset(4, 0), Offset(0, 2)],
    );
  });

  test('Wrap shrink-wraps runs within loose maximum constraints', () {
    final children = <RenderBox>[_FixedBox(2, 1), _FixedBox(2, 1)];
    final wrap = RenderWrap(spacing: 1, children: children);

    wrap.layout(const BoxConstraints(maxWidth: 10, maxHeight: 4));

    expect(wrap.size, const Size(5, 1));
  });

  test('vertical Wrap aligns completed columns along the run axis', () {
    final children = <RenderBox>[
      _FixedBox(1, 2),
      _FixedBox(1, 2),
      _FixedBox(1, 1),
    ];
    final wrap = RenderWrap(
      direction: Axis.vertical,
      runSpacing: 1,
      runAlignment: WrapAlignment.end,
      children: children,
    );

    wrap.layout(const BoxConstraints.tight(width: 6, height: 4));

    expect(
      children.map((child) => Offset(child.x, child.y)).toList(),
      const <Offset>[Offset(3, 0), Offset(3, 2), Offset(5, 0)],
    );
  });

  test('Wrap alignments account for every whole slack cell', () {
    const expected = <WrapAlignment, List<int>>{
      WrapAlignment.center: <int>[3, 4, 5],
      WrapAlignment.spaceAround: <int>[1, 4, 6],
      WrapAlignment.spaceEvenly: <int>[2, 4, 6],
    };

    for (final MapEntry(key: alignment, value: positions) in expected.entries) {
      final mainChildren = List<_FixedBox>.generate(3, (_) => _FixedBox(1, 1));
      final main = RenderWrap(alignment: alignment, children: mainChildren);

      main.layout(const BoxConstraints.tight(width: 8, height: 1));

      expect(
        mainChildren.map((child) => child.x),
        positions,
        reason: 'main $alignment',
      );

      final runChildren = List<_FixedBox>.generate(3, (_) => _FixedBox(1, 1));
      final runs = RenderWrap(runAlignment: alignment, children: runChildren);

      runs.layout(const BoxConstraints.tight(width: 1, height: 8));

      expect(
        runChildren.map((child) => child.y),
        positions,
        reason: 'runs $alignment',
      );
    }
  });

  test('Wrap cross-axis center awards odd slack to the leading slot', () {
    final horizontalChildren = <RenderBox>[_FixedBox(1, 4), _FixedBox(1, 1)];
    final horizontal = RenderWrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: horizontalChildren,
    );

    horizontal.layout(const BoxConstraints.tight(width: 2, height: 4));

    expect(horizontalChildren[1].y, 2);

    final verticalChildren = <RenderBox>[_FixedBox(4, 1), _FixedBox(1, 1)];
    final vertical = RenderWrap(
      direction: Axis.vertical,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: verticalChildren,
    );

    vertical.layout(const BoxConstraints.tight(width: 4, height: 2));

    expect(verticalChildren[1].x, 2);
  });

  test('Stack clips paint and hit-tests positioned children locally', () {
    final child = _HitBox();
    final stack = RenderStack()
      ..add(
        child,
        data: const StackChildData(left: 2, top: 1, width: 3, height: 2),
      )
      ..layout(const BoxConstraints.tight(width: 6, height: 4));
    final canvas = _RecordingCanvas();

    stack.paint(PaintingContext(canvas), Offset.zero);
    final result = HitTestResult();

    expect(canvas.clip, const Rect.fromLTWH(0, 0, 6, 4));
    expect(stack.hitTest(result, const Offset(3, 2)), isTrue);
    expect(result.path.single.localPosition, const Offset(1, 1));
  });

  test('Positioned permits negative edge offsets for clipped overflow', () {
    final child = _FixedBox(1, 1);
    final stack = RenderStack()
      ..add(child, data: StackChildData(left: -2, top: -1, width: 3, height: 2))
      ..layout(const BoxConstraints.tight(width: 6, height: 4));
    final canvas = _RecordingCanvas();

    stack.paint(PaintingContext(canvas), Offset.zero);

    expect(child.size, const Size(3, 2));
    expect(Offset(child.x, child.y), const Offset(-2, -1));
    expect(canvas.clip, const Rect.fromLTWH(0, 0, 6, 4));
  });

  test('Positioned updates preserve the child render identity', () {
    final key = GlobalKey<_StackHostState>();
    final host = TestElementHost()..mount(_StackHost(key: key));
    host.pumpFrame(
      constraints: const BoxConstraints.tight(width: 8, height: 3),
    );
    final stack = host.renderObject! as RenderStack;
    final child = stack.children.single;

    key.currentState!.move();
    host.pumpFrame(
      constraints: const BoxConstraints.tight(width: 8, height: 3),
    );

    expect(stack.children.single, same(child));
    expect(child.x, 3);
    host.dispose();
  });
}

final class _FixedBox extends RenderBox {
  _FixedBox(this.naturalWidth, this.naturalHeight);

  final int naturalWidth;
  final int naturalHeight;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(
      constraints.constrainWidth(naturalWidth),
      constraints.constrainHeight(naturalHeight),
    );
  }
}

final class _HitBox extends RenderBox implements HitTestTarget {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(constraints.minWidth, constraints.minHeight);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(MouseEvent event, HitTestEntry entry) {}
}

final class _RecordingCanvas implements TuiCanvas {
  Rect? clip;

  @override
  void clipRect(Rect rect) => clip = rect;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final class _StackHost extends StatefulWidget {
  const _StackHost({super.key});

  @override
  State<_StackHost> createState() => _StackHostState();
}

final class _StackHostState extends State<_StackHost> {
  int left = 1;

  void move() => setState(() => left = 3);

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      Positioned(
        left: left,
        top: 0,
        width: 1,
        height: 1,
        child: const SizedBox(width: 1, height: 1),
      ),
    ],
  );
}
