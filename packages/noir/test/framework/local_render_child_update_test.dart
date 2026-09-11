import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';

void main() {
  for (final kind in ['Row', 'Column', 'Stack', 'Wrap']) {
    for (var slot = 0; slot < 3; slot++) {
      test('$kind reconnects a local replacement in slot $slot', () {
        final switchKey = GlobalKey<_SwitchState>();
        final parentKey = GlobalKey();
        final siblingKeys = List.generate(3, (_) => GlobalKey<_ProbeState>());
        var parentBuilds = 0;
        final children = [
          for (var index = 0; index < 3; index++)
            if (index == slot)
              _Switch(key: switchKey, builder: _content)
            else
              _Probe(key: siblingKeys[index], label: '$index'),
        ];
        final app = createTuiTestApp(
          _Build(
            builder: (_) {
              parentBuilds++;
              return _parent(kind, children, parentKey);
            },
          ),
          width: 20,
          height: 4,
        );
        addTearDown(app.dispose);
        app.pumpFrame();

        final initialBuilds = parentBuilds;
        final parentRender = parentKey.currentContext!.findRenderObject()!;
        final previousChildren = parentRender.children.toList();
        final states = [for (final key in siblingKeys) key.currentState];
        final initialPosition = _position(kind, slot);
        expect(
          app.captureFrame(),
          BufferMatchers.hasCharAt(initialPosition.dx, initialPosition.dy, 'B'),
        );

        for (final alternate in [true, false, true]) {
          switchKey.currentState!.toggle();
          app.pumpFrame();

          expect(parentBuilds, initialBuilds);
          expect(parentRender.children, hasLength(3));
          final childRender = switchKey.currentContext!.findRenderObject()!;
          expect(childRender.parent, same(parentRender));
          expect(parentRender.children[slot], same(childRender));
          expect(
            app.captureFrame(),
            BufferMatchers.hasCharAt(
              initialPosition.dx + (alternate ? 1 : 0),
              initialPosition.dy,
              alternate ? 'N' : 'B',
            ),
          );
          for (var index = 0; index < 3; index++) {
            if (index == slot) continue;
            expect(siblingKeys[index].currentState, same(states[index]));
            expect(parentRender.children[index], same(previousChildren[index]));
            expect(states[index]!.builds, 1);
          }
        }
      });
    }
  }

  for (final wrapper in ['stateless', 'inherited', 'layout', 'single child']) {
    test('local replacement through $wrapper keeps its painted output', () {
      final key = GlobalKey<_SwitchState>();
      final app = createTuiTestApp(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Switch(
              key: key,
              builder: ({required alternate}) => switch (wrapper) {
                'stateless' => _Build(
                  builder: (_) => _content(alternate: alternate),
                ),
                'inherited' => _Flag(
                  value: alternate,
                  child: const _Dependent(),
                ),
                'layout' => LayoutBuilder(
                  builder: (_, _) => _content(alternate: alternate),
                ),
                _ => Padding(
                  padding: EdgeInsets.zero,
                  child: _content(alternate: alternate),
                ),
              },
            ),
          ],
        ),
        width: 20,
        height: 4,
      );
      addTearDown(app.dispose);
      app.pumpFrame();
      expect(app.captureFrame(), BufferMatchers.hasCharAt(0, 0, 'B'));
      key.currentState!.toggle();
      app.pumpFrame();
      expect(app.captureFrame(), BufferMatchers.hasCharAt(1, 0, 'N'));
    });
  }

  test('local replacement retains its Expanded allocation', () {
    final key = GlobalKey<_SwitchState>();
    final app = createTuiTestApp(
      Row(
        children: [
          Expanded(
            flex: 3,
            child: _Switch(key: key, builder: _content),
          ),
          const Expanded(child: Text('R')),
        ],
      ),
      width: 20,
      height: 1,
    );
    addTearDown(app.dispose);
    app.pumpFrame();
    expect(key.currentContext!.findRenderObject()!.width, 15);
    key.currentState!.toggle();
    app.pumpFrame();
    expect(key.currentContext!.findRenderObject()!.width, 15);
    expect(app.captureFrame(), BufferMatchers.hasCharAt(1, 0, 'N'));
    expect(app.captureFrame(), BufferMatchers.hasCharAt(15, 0, 'R'));
  });

  test('a keyed reorder moves the slot used by the next local replacement', () {
    final parentKey = GlobalKey();
    final switchKey = GlobalKey<_SwitchState>();
    final siblingKey = GlobalKey<_ProbeState>();
    final switchWidget = _Switch(key: switchKey, builder: _content);
    final sibling = _Probe(key: siblingKey, label: 'S');
    final app = createTuiTestApp(
      Row(key: parentKey, children: [switchWidget, sibling]),
      width: 20,
      height: 1,
    );
    addTearDown(app.dispose);
    app.pumpFrame();
    final switchState = switchKey.currentState;
    final siblingState = siblingKey.currentState;
    final siblingRender = siblingKey.currentContext!.findRenderObject();
    parentKey.currentContext!.element.update(
      Row(key: parentKey, children: [sibling, switchWidget]),
    );
    app.pumpFrame();
    switchKey.currentState!.toggle();
    app.pumpFrame();
    expect(switchKey.currentState, same(switchState));
    expect(siblingKey.currentState, same(siblingState));
    expect(siblingKey.currentContext!.findRenderObject(), same(siblingRender));
    expect(app.captureFrame(), BufferMatchers.hasCharAt(0, 0, 'S'));
    expect(app.captureFrame(), BufferMatchers.hasCharAt(2, 0, 'N'));
  });

  test('a local replacement updates pointer routing and local coordinates', () {
    final key = GlobalKey<_SwitchState>();
    final hits = <(String, Offset)>[];
    final app = createTuiTestApp(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('L'),
          _Switch(
            key: key,
            builder: ({required alternate}) {
              final listener = PointerListener(
                onPointerDown: (event) {
                  hits.add((alternate ? 'new' : 'old', event.localPosition));
                },
                child: Text(alternate ? 'N' : 'B'),
              );
              return alternate
                  ? Padding(
                      padding: const EdgeInsets.only(left: 1),
                      child: listener,
                    )
                  : listener;
            },
          ),
          const Text('R'),
        ],
      ),
      width: 20,
      height: 4,
    );
    addTearDown(app.dispose);
    app.pumpFrame();
    app.mockMouse.click(1, 0);
    key.currentState!.toggle();
    app.pumpFrame();
    app.mockMouse.click(2, 0);
    expect(hits, [('old', Offset.zero), ('new', Offset.zero)]);
    expect(app.captureFrame(), BufferMatchers.hasCharAt(2, 0, 'N'));
    expect(app.captureFrame(), BufferMatchers.hasCharAt(3, 0, 'R'));
  });

  test('replacement removes one render edge and finalizes old State once', () {
    final key = GlobalKey<_SwitchState>();
    final states = <_OwnedState>[];
    final app = createTuiTestApp(
      Row(
        children: [
          _Switch(
            key: key,
            builder: ({required alternate}) => alternate
                ? Padding(padding: EdgeInsets.zero, child: _Owned(states))
                : _Owned(states),
          ),
        ],
      ),
    );
    addTearDown(app.dispose);
    app.pumpFrame();
    final oldState = states.single;
    key.currentState!.toggle();
    app.pumpFrame();

    expect(states, hasLength(2));
    expect(oldState.disposals, 1);
    expect(oldState.render.detachments, 1);
    expect(oldState.render.parent, isNull);
    expect(oldState.mounted, isFalse);
    expect(states.last.mounted, isTrue);
    expect(key.currentContext!.findRenderObject()!.parent, isNotNull);
    app.dispose();
    expect(states.map((state) => state.disposals), everyElement(1));
    expect(states.map((state) => state.render.detachments), everyElement(1));
  });
}

Widget _content({required bool alternate}) => alternate
    ? const Padding(padding: EdgeInsets.only(left: 1), child: Text('N'))
    : const Text('B');

Widget _parent(String kind, List<Widget> children, Key key) => switch (kind) {
  'Row' => Row(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  ),
  'Column' => Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  ),
  'Stack' => Stack(
    key: key,
    children: [
      for (var index = 0; index < children.length; index++)
        Positioned(left: index * 4, top: 0, child: children[index]),
    ],
  ),
  _ => Wrap(key: key, children: children),
};

Offset _position(String kind, int slot) => switch (kind) {
  'Column' => Offset(0, slot),
  'Stack' => Offset(slot * 4, 0),
  _ => Offset(slot, 0),
};

class _Switch extends StatefulWidget {
  const _Switch({required this.builder, super.key});
  final Widget Function({required bool alternate}) builder;
  @override
  State<_Switch> createState() => _SwitchState();
}

class _SwitchState extends State<_Switch> {
  bool alternate = false;
  void toggle() => setState(() => alternate = !alternate);
  @override
  Widget build(BuildContext context) => widget.builder(alternate: alternate);
}

class _Build extends StatelessWidget {
  const _Build({required this.builder});
  final Widget Function(BuildContext) builder;
  @override
  Widget build(BuildContext context) => builder(context);
}

class _Probe extends StatefulWidget {
  const _Probe({required this.label, super.key});
  final String label;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int builds = 0;
  @override
  Widget build(BuildContext context) {
    builds++;
    return Text(widget.label);
  }
}

class _Flag extends InheritedWidget {
  const _Flag({required this.value, required super.child});
  final bool value;
  @override
  bool updateShouldNotify(_Flag oldWidget) => oldWidget.value != value;
}

class _Dependent extends StatelessWidget {
  const _Dependent();
  @override
  Widget build(BuildContext context) => _content(
    alternate: context.dependOnInheritedWidgetOfExactType<_Flag>()!.value,
  );
}

class _Owned extends StatefulWidget {
  const _Owned(this.states);
  final List<_OwnedState> states;
  @override
  State<_Owned> createState() => _OwnedState();
}

class _OwnedState extends State<_Owned> {
  final render = _LifecycleBox();
  int disposals = 0;
  @override
  void initState() {
    super.initState();
    widget.states.add(this);
  }

  @override
  Widget build(BuildContext context) => _RenderLeaf(render);
  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

class _RenderLeaf extends RenderObjectWidget {
  const _RenderLeaf(this.render);
  final _LifecycleBox render;
  @override
  RenderObject createRenderObject(BuildContext context) => render;
}

class _LifecycleBox extends RenderBox {
  int detachments = 0;
  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(constraints.constrainWidth(1), constraints.constrainHeight(1));
  }

  @override
  void detach() {
    detachments++;
    super.detach();
  }
}
