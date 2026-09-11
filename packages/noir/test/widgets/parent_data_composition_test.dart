import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';
import '../helpers/widget_tester.dart';

void main() {
  for (final wrapper in ['direct', 'stateless', 'stateful', 'proxy']) {
    test('Expanded preserves allocation through $wrapper components', () {
      final leafKey = GlobalKey();
      final tester = WidgetTester(maxWidth: 20, maxHeight: 4);
      addTearDown(tester.dispose);
      tester.pumpWidget(
        Row(
          children: [
            _wrap(
              wrapper,
              Expanded(child: SizedBox(key: leafKey, width: 1, height: 1)),
            ),
          ],
        ),
      );
      final render = leafKey.currentContext!.findRenderObject()! as RenderBox;
      expect(render.size.width, 20);
    });

    test('Positioned preserves offsets through $wrapper components', () {
      final leafKey = GlobalKey();
      final tester = WidgetTester(maxWidth: 20, maxHeight: 6);
      addTearDown(tester.dispose);
      tester.pumpWidget(
        Stack(
          children: [
            _wrap(
              wrapper,
              Positioned(
                left: 7,
                top: 2,
                child: SizedBox(key: leafKey, width: 1, height: 1),
              ),
            ),
          ],
        ),
      );
      final render = leafKey.currentContext!.findRenderObject()!;
      expect(Offset(render.x, render.y), const Offset(7, 2));
    });
  }

  test(
    'local flex and fit changes retain the render child and update layout',
    () {
      final key = GlobalKey<_FlexState>();
      final parentKey = GlobalKey();
      var parentBuilds = 0;
      final app = createTuiTestApp(
        _Builder(() {
          parentBuilds++;
          return Row(
            key: parentKey,
            children: [
              _FlexConfiguration(key: key),
              const Expanded(child: Text('R')),
            ],
          );
        }),
        width: 20,
        height: 1,
      );
      addTearDown(app.dispose);
      app.pumpFrame();
      final initialBuilds = parentBuilds;
      final render = key.currentContext!.findRenderObject()! as RenderBox;
      final parent = parentKey.currentContext!.findRenderObject()!;
      expect(render.size.width, 10);
      expect(app.captureFrame(), BufferMatchers.hasCharAt(10, 0, 'R'));

      key.currentState!.change(3, FlexFit.tight);
      app.pumpFrame();
      expect(key.currentContext!.findRenderObject(), same(render));
      expect(render.size.width, 15);
      expect(app.captureFrame(), BufferMatchers.hasCharAt(15, 0, 'R'));

      key.currentState!.change(3, FlexFit.loose);
      app.pumpFrame();
      expect(key.currentContext!.findRenderObject(), same(render));
      expect(render.size.width, 1);
      expect(app.captureFrame(), BufferMatchers.hasCharAt(1, 0, 'R'));
      expect(parentBuilds, initialBuilds);
      expect(parent.children.first, same(render));
    },
  );

  test(
    'local Positioned offset and size changes update paint and hit testing',
    () {
      final key = GlobalKey<_PositionState>();
      final hits = <Offset>[];
      var parentBuilds = 0;
      final app = createTuiTestApp(
        _Builder(() {
          parentBuilds++;
          return Stack(
            children: [_PositionConfiguration(key: key, onPointer: hits.add)],
          );
        }),
        width: 20,
        height: 6,
      );
      addTearDown(app.dispose);
      app.pumpFrame();
      final initialBuilds = parentBuilds;
      final render = key.currentContext!.findRenderObject()! as RenderBox;
      expect(Offset(render.x, render.y), const Offset(2, 1));
      expect(app.captureFrame(), BufferMatchers.hasCharAt(2, 1, 'P'));

      key.currentState!.move();
      app.pumpFrame();
      expect(key.currentContext!.findRenderObject(), same(render));
      expect(Offset(render.x, render.y), const Offset(7, 2));
      expect(render.size, const Size(4, 2));
      expect(app.captureFrame(), BufferMatchers.hasCharAt(7, 2, 'P'));
      app.mockMouse.click(8, 2);
      expect(hits, [const Offset(1, 0)]);
      expect(parentBuilds, initialBuilds);
    },
  );

  final invalid = <String, Widget>{
    'Flexible without a Flex': const Expanded(child: Text('x')),
    'Positioned without a Stack': const Positioned(left: 1, child: Text('x')),
    'Flexible behind a render boundary': const Row(
      children: [
        Padding(
          padding: EdgeInsets.zero,
          child: Expanded(child: Text('x')),
        ),
      ],
    ),
    'Positioned behind a render boundary': const Stack(
      children: [
        Padding(
          padding: EdgeInsets.zero,
          child: Positioned(left: 1, child: Text('x')),
        ),
      ],
    ),
    'duplicate Flexible data': const Row(
      children: [Expanded(child: Expanded(child: Text('x')))],
    ),
    'duplicate Positioned data': const Stack(
      children: [
        Positioned(left: 1, child: Positioned(top: 1, child: Text('x'))),
      ],
    ),
    'Positioned under Flex': const Row(
      children: [Positioned(left: 1, child: Text('x'))],
    ),
    'Flexible under Stack': const Stack(children: [Expanded(child: Text('x'))]),
  };
  for (final MapEntry(key: label, value: widget) in invalid.entries) {
    test('$label rejects instead of ignoring metadata', () {
      final owner = BuildOwner();
      final element = widget.createElement();
      try {
        expect(() => element.mount(null, owner), throwsStateError);
      } finally {
        element.unmount();
        owner.dispose();
      }
    });
  }
}

Widget _wrap(String kind, Widget child) => switch (kind) {
  'stateless' => _Builder(() => child),
  'stateful' => _StatefulProxy(child),
  'proxy' => _Proxy(child: child),
  _ => child,
};

class _Builder extends StatelessWidget {
  const _Builder(this.builder);
  final Widget Function() builder;
  @override
  Widget build(BuildContext context) => builder();
}

class _Proxy extends ProxyWidget {
  const _Proxy({required super.child});
}

class _StatefulProxy extends StatefulWidget {
  const _StatefulProxy(this.child);
  final Widget child;
  @override
  State<_StatefulProxy> createState() => _StatefulProxyState();
}

class _StatefulProxyState extends State<_StatefulProxy> {
  @override
  Widget build(BuildContext context) => widget.child;
}

class _FlexConfiguration extends StatefulWidget {
  const _FlexConfiguration({super.key});
  @override
  State<_FlexConfiguration> createState() => _FlexState();
}

class _FlexState extends State<_FlexConfiguration> {
  int flex = 1;
  FlexFit fit = FlexFit.tight;
  void change(int nextFlex, FlexFit nextFit) => setState(() {
    flex = nextFlex;
    fit = nextFit;
  });
  @override
  Widget build(BuildContext context) => _Proxy(
    child: Flexible(flex: flex, fit: fit, child: const Text('L')),
  );
}

class _PositionConfiguration extends StatefulWidget {
  const _PositionConfiguration({required this.onPointer, super.key});
  final void Function(Offset) onPointer;
  @override
  State<_PositionConfiguration> createState() => _PositionState();
}

class _PositionState extends State<_PositionConfiguration> {
  bool moved = false;
  void move() => setState(() => moved = true);
  @override
  Widget build(BuildContext context) => _Proxy(
    child: Positioned(
      left: moved ? 7 : 2,
      top: moved ? 2 : 1,
      width: moved ? 4 : 2,
      height: moved ? 2 : 1,
      child: PointerListener(
        onPointerDown: (event) => widget.onPointer(event.localPosition),
        child: const Text('P'),
      ),
    ),
  );
}
