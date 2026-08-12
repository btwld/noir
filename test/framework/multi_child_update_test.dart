// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart';
import 'package:noir/src/rendering/object.dart' show PipelineOwner;
import 'package:test/test.dart';

void main() {
  group('MultiChildRenderObjectElement diffing', () {
    test(
      'reuses existing children when widget configuration is compatible',
      () {
        final log = <String>[];
        final owner = BuildOwner();
        final element = Row(
          children: [_LoggingWidget('A', log), _LoggingWidget('B', log)],
        ).createElement();

        element.mount(null, owner);
        owner.buildScope();
        log.clear();

        element.update(
          Row(children: [_LoggingWidget('A', log), _LoggingWidget('B', log)]),
        );
        owner.buildScope();

        expect(log.where((entry) => entry.startsWith('init')).isEmpty, isTrue);
        expect(
          log.where((entry) => entry.startsWith('dispose')).isEmpty,
          isTrue,
        );
        expect(
          log.where((entry) => entry.startsWith('build')).toList(),
          equals(['build:A', 'build:B']),
        );
      },
    );

    test('disposes removed children', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = Row(
        children: [_LoggingWidget('A', log), _LoggingWidget('B', log)],
      ).createElement();

      element.mount(null, owner);
      owner.buildScope();
      log.clear();

      element.update(Row(children: [_LoggingWidget('A', log)]));
      owner.buildScope();

      expect(log, contains('dispose:B'));
      expect(log.where((entry) => entry == 'dispose:A').isEmpty, isTrue);
    });

    test('same-parent GlobalKey reorder preserves Element, State, and '
        'RenderObject identity', () {
      final log = <String>[];
      final owner = BuildOwner();
      final keyA = GlobalKey<_LoggingWidgetState>();
      final keyB = GlobalKey<_LoggingWidgetState>();

      final element = Row(
        children: [
          _LoggingWidget('A', log, key: keyA),
          _LoggingWidget('B', log, key: keyB),
        ],
      ).createElement();

      element.mount(null, owner);
      owner.buildScope();

      final stateA = keyA.currentState;
      final stateB = keyB.currentState;
      final elementA = keyA.currentContext!.element;
      final elementB = keyB.currentContext!.element;
      final renderA = Element.findDescendantRenderObject(elementA);
      final renderB = Element.findDescendantRenderObject(elementB);
      final parentRender = (element as RenderObjectElement).renderObject!;
      log.clear();

      element.update(
        Row(
          children: [
            _LoggingWidget('B', log, key: keyB),
            _LoggingWidget('A', log, key: keyA),
          ],
        ),
      );
      owner.buildScope();

      expect(keyA.currentState, same(stateA));
      expect(keyB.currentState, same(stateB));
      expect(keyA.currentContext!.element, same(elementA));
      expect(keyB.currentContext!.element, same(elementB));
      expect(Element.findDescendantRenderObject(elementA), same(renderA));
      expect(Element.findDescendantRenderObject(elementB), same(renderB));
      expect(parentRender.children, [same(renderB), same(renderA)]);
      expect(log.where((entry) => entry.startsWith('dispose')).isEmpty, isTrue);
    });

    test('compatible updates retain render attachment identity', () {
      final owner = BuildOwner();
      final element = Row(
        children: const [_LifecycleWidget('A', key: ValueKey<String>('a'))],
      ).createElement();
      element.mount(null, owner);

      final parentRender = (element as RenderObjectElement).renderObject!;
      final childRender = _lifecycleRender(element.children.single);

      element.update(
        const Row(
          children: [_LifecycleWidget('A2', key: ValueKey<String>('a'))],
        ),
      );
      owner.buildScope();

      expect(_lifecycleRender(element.children.single), same(childRender));
      expect(parentRender.children, [same(childRender)]);
      expect(childRender.attachCount, 1);
      expect(childRender.detachCount, 0);

      element.unmount();
    });

    test('keyed reorder moves render children without attachment churn', () {
      final owner = BuildOwner();
      final element = Row(
        children: const [
          _LifecycleWidget('A', key: ValueKey<String>('a')),
          _LifecycleWidget('B', key: ValueKey<String>('b')),
        ],
      ).createElement();
      element.mount(null, owner);

      final parentRender = (element as RenderObjectElement).renderObject!;
      final firstRender = _lifecycleRender(element.children[0]);
      final secondRender = _lifecycleRender(element.children[1]);

      element.update(
        const Row(
          children: [
            _LifecycleWidget('B2', key: ValueKey<String>('b')),
            _LifecycleWidget('A2', key: ValueKey<String>('a')),
          ],
        ),
      );
      owner.buildScope();

      expect(parentRender.children, [same(secondRender), same(firstRender)]);
      expect([
        firstRender.attachCount,
        secondRender.attachCount,
      ], everyElement(1));
      expect([
        firstRender.detachCount,
        secondRender.detachCount,
      ], everyElement(0));

      element.unmount();
    });

    test('unkeyed cross-type swap replaces both positional identities', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = Row(
        children: [_TypeA('A', log), _TypeB('B', log)],
      ).createElement();
      element.mount(null, owner);
      owner.buildScope();

      final parentRender = (element as RenderObjectElement).renderObject!;
      final oldNodes = element.children.map(_lifecycleIdentity).toList();

      element.update(Row(children: [_TypeB('B2', log), _TypeA('A2', log)]));
      owner.buildScope();
      owner.finalizeTree();

      final newNodes = element.children.map(_lifecycleIdentity).toList();
      for (final current in newNodes) {
        for (final previous in oldNodes) {
          expect(current.element, isNot(same(previous.element)));
          expect(current.state, isNot(same(previous.state)));
          expect(current.render, isNot(same(previous.render)));
        }
      }
      expect(parentRender.children, [
        same(newNodes[0].render),
        same(newNodes[1].render),
      ]);
      expect(log.where((entry) => entry == 'dispose:A'), hasLength(1));
      expect(log.where((entry) => entry == 'dispose:B'), hasLength(1));
      for (final old in oldNodes) {
        expect(old.element.mounted, isFalse);
        expect(old.render.detachCount, 1);
        expect(old.render.parent, isNull);
      }

      element.unmount();
    });

    test('duplicate local keys reject before mount mutation', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = Row(
        children: [
          _TypeA('A', log, key: const ValueKey<String>('duplicate')),
          _TypeB('B', log, key: const ValueKey<String>('duplicate')),
        ],
      ).createElement();

      expect(
        () => element.mount(null, owner),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Duplicate key'),
          ),
        ),
      );

      expect(element.mounted, isFalse);
      expect(element.parent, isNull);
      expect(element.children, isEmpty);
      expect((element as RenderObjectElement).renderObject, isNull);
      expect(log, isEmpty);
    });

    test('duplicate local keys reject before update mutation', () {
      final log = <String>[];
      final owner = BuildOwner();
      final validWidget = Row(
        children: [
          _TypeA('A', log, key: const ValueKey<String>('a')),
          _TypeB('B', log, key: const ValueKey<String>('b')),
        ],
      );
      final element = validWidget.createElement();
      element.mount(null, owner);
      owner.buildScope();

      final parentRender = (element as RenderObjectElement).renderObject!;
      final oldNodes = element.children.map(_lifecycleIdentity).toList();
      final oldRenderOrder = List<RenderObject>.from(parentRender.children);
      final oldLog = List<String>.from(log);

      expect(
        () => element.update(
          Row(
            children: [
              _TypeA('A2', log, key: const ValueKey<String>('duplicate')),
              _TypeB('B2', log, key: const ValueKey<String>('duplicate')),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Duplicate key'),
          ),
        ),
      );

      expect(element.widget, same(validWidget));
      expect(element.children, oldNodes.map((node) => same(node.element)));
      expect(parentRender.children, oldRenderOrder.map(same));
      expect(log, oldLog);
      for (var i = 0; i < oldNodes.length; i++) {
        final current = _lifecycleIdentity(element.children[i]);
        expect(current.element, same(oldNodes[i].element));
        expect(current.state, same(oldNodes[i].state));
        expect(current.render, same(oldNodes[i].render));
        expect(current.render.attachCount, 1);
        expect(current.render.detachCount, 0);
      }

      element.unmount();
    });

    test('keyed cross-type swap retains all three identity layers', () {
      final log = <String>[];
      final owner = BuildOwner();
      final keyA = const ValueKey<String>('a');
      final keyB = const ValueKey<String>('b');
      final element = Row(
        children: [
          _TypeA('A', log, key: keyA),
          _TypeB('B', log, key: keyB),
        ],
      ).createElement();
      element.mount(null, owner);
      owner.buildScope();

      final parentRender = (element as RenderObjectElement).renderObject!;
      final oldNodes = element.children.map(_lifecycleIdentity).toList();

      element.update(
        Row(
          children: [
            _TypeB('B2', log, key: keyB),
            _TypeA('A2', log, key: keyA),
          ],
        ),
      );
      owner.buildScope();

      final newNodes = element.children.map(_lifecycleIdentity).toList();
      expect(newNodes[0].element, same(oldNodes[1].element));
      expect(newNodes[0].state, same(oldNodes[1].state));
      expect(newNodes[0].render, same(oldNodes[1].render));
      expect(newNodes[1].element, same(oldNodes[0].element));
      expect(newNodes[1].state, same(oldNodes[0].state));
      expect(newNodes[1].render, same(oldNodes[0].render));
      expect(parentRender.children, [
        same(oldNodes[1].render),
        same(oldNodes[0].render),
      ]);
      for (final node in oldNodes) {
        expect(node.render.attachCount, 1);
        expect(node.render.detachCount, 0);
      }
      expect(log.where((entry) => entry.startsWith('dispose:')), isEmpty);

      element.unmount();
    });

    test('unkeyed insertion retains compatible prefix and suffix', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = Row(
        children: [_TypeA('A', log), _TypeC('C', log)],
      ).createElement();
      element.mount(null, owner);
      owner.buildScope();

      final oldNodes = element.children.map(_lifecycleIdentity).toList();

      element.update(
        Row(children: [_TypeA('A2', log), _TypeB('B', log), _TypeC('C2', log)]),
      );
      owner.buildScope();

      final newNodes = element.children.map(_lifecycleIdentity).toList();
      expect(newNodes[0].element, same(oldNodes[0].element));
      expect(newNodes[0].state, same(oldNodes[0].state));
      expect(newNodes[0].render, same(oldNodes[0].render));
      expect(newNodes[2].element, same(oldNodes[1].element));
      expect(newNodes[2].state, same(oldNodes[1].state));
      expect(newNodes[2].render, same(oldNodes[1].render));
      expect(newNodes[1].render.attachCount, 1);
      for (final retained in oldNodes) {
        expect(retained.render.attachCount, 1);
        expect(retained.render.detachCount, 0);
      }

      element.unmount();
    });

    test('unkeyed removal retains compatible prefix and suffix', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = Row(
        children: [_TypeA('A', log), _TypeB('B', log), _TypeC('C', log)],
      ).createElement();
      element.mount(null, owner);
      owner.buildScope();

      final oldNodes = element.children.map(_lifecycleIdentity).toList();

      element.update(Row(children: [_TypeA('A2', log), _TypeC('C2', log)]));
      owner.buildScope();
      owner.finalizeTree();

      final newNodes = element.children.map(_lifecycleIdentity).toList();
      expect(newNodes[0].element, same(oldNodes[0].element));
      expect(newNodes[0].state, same(oldNodes[0].state));
      expect(newNodes[0].render, same(oldNodes[0].render));
      expect(newNodes[1].element, same(oldNodes[2].element));
      expect(newNodes[1].state, same(oldNodes[2].state));
      expect(newNodes[1].render, same(oldNodes[2].render));
      expect(oldNodes[1].element.mounted, isFalse);
      expect(oldNodes[1].render.detachCount, 1);
      expect(oldNodes[1].render.parent, isNull);
      for (final retained in [oldNodes[0], oldNodes[2]]) {
        expect(retained.render.attachCount, 1);
        expect(retained.render.detachCount, 0);
      }

      element.unmount();
    });

    test('mixed update churns only genuinely removed and added children', () {
      final owner = BuildOwner();
      final element = Row(
        children: const [
          _LifecycleWidget('A', key: ValueKey<String>('a')),
          _LifecycleWidget('B', key: ValueKey<String>('b')),
        ],
      ).createElement();
      element.mount(null, owner);

      final parentRender = (element as RenderObjectElement).renderObject!;
      final removedRender = _lifecycleRender(element.children[0]);
      final retainedRender = _lifecycleRender(element.children[1]);

      element.update(
        const Row(
          children: [
            _LifecycleWidget('B2', key: ValueKey<String>('b')),
            _LifecycleWidget('C', key: ValueKey<String>('c')),
          ],
        ),
      );
      owner.buildScope();
      final addedRender = _lifecycleRender(element.children[1]);

      expect(parentRender.children, [same(retainedRender), same(addedRender)]);
      expect(removedRender.detachCount, 1);
      expect(removedRender.parent, isNull);
      expect(retainedRender.attachCount, 1);
      expect(retainedRender.detachCount, 0);
      expect(addedRender.attachCount, 1);
      expect(addedRender.detachCount, 0);

      element.unmount();
    });

    test('retained Flexible children refresh metadata without churn', () {
      final owner = BuildOwner();
      final element = Row(
        children: const [
          Expanded(key: ValueKey<String>('a'), child: _LifecycleWidget('A')),
          Expanded(key: ValueKey<String>('b'), child: _LifecycleWidget('B')),
        ],
      ).createElement();
      element.mount(null, owner);

      final renderFlex =
          (element as RenderObjectElement).renderObject! as RenderFlex;
      final firstRender = _lifecycleRender(element.children[0]);
      final secondRender = _lifecycleRender(element.children[1]);
      renderFlex.layout(const BoxConstraints.tight(width: 6, height: 1));
      expect([firstRender.width, secondRender.width], [3, 3]);

      element.update(
        const Row(
          children: [
            Expanded(
              key: ValueKey<String>('a'),
              flex: 2,
              child: _LifecycleWidget('A2'),
            ),
            Expanded(key: ValueKey<String>('b'), child: _LifecycleWidget('B2')),
          ],
        ),
      );
      owner.buildScope();
      renderFlex.layout(const BoxConstraints.tight(width: 6, height: 1));

      expect(renderFlex.children, [same(firstRender), same(secondRender)]);
      expect([firstRender.width, secondRender.width], [4, 2]);
      expect([
        firstRender.attachCount,
        secondRender.attachCount,
      ], everyElement(1));
      expect([
        firstRender.detachCount,
        secondRender.detachCount,
      ], everyElement(0));

      element.unmount();
    });

    test('visitChildren exposes multi-child children', () {
      final owner = BuildOwner();
      final element = Row(
        children: const [Text('A'), Text('B')],
      ).createElement();

      element.mount(null, owner);
      owner.buildScope();

      final visited = <Element>[];
      element.visitChildren(visited.add);

      expect(visited, hasLength(2));
      expect(visited.map((e) => e.widget), everyElement(isA<Text>()));

      element.unmount();
    });

    test('updates children through Flexible wrappers', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = Column(
        children: [_LoggingWidget('A', log)],
      ).createElement();

      element.mount(null, owner);
      owner.buildScope();
      log.clear();

      element.update(
        Column(children: [Expanded(child: _LoggingWidget('B', log))]),
      );
      owner.buildScope();

      expect(log, contains('build:B'));
      expect(log, isNot(contains('build:A')));

      element.unmount();
    });

    test(
      'multi-child direct unmount drops render edge before one detach hook',
      () {
        final owner = BuildOwner();
        final element = Row(
          children: const [_DetachCountingWidget()],
        ).createElement();
        element.mount(null, owner);
        final parentRender =
            (element as RenderObjectElement).renderObject! as RenderBox;
        final childElement = element.children.single;
        final childRender =
            Element.findRenderObjectElement(childElement)!.renderObject!
                as _DetachCountingRenderBox;

        element.unmount();

        expect(childRender.detachCount, 1);
        expect(parentRender.children, isEmpty);
        expect(childRender.parent, isNull);
        expect(parentRender.pipelineOwner, isNull);
        expect(childRender.pipelineOwner, isNull);
      },
    );

    test(
      'multi-child deactivate then finalize does not detach the leaf twice',
      () {
        final owner = BuildOwner();
        final element = Row(
          children: const [_DetachCountingWidget()],
        ).createElement();
        element.mount(null, owner);
        final parentRender =
            (element as RenderObjectElement).renderObject! as RenderBox;
        final childElement = element.children.single;
        final childRender =
            Element.findRenderObjectElement(childElement)!.renderObject!
                as _DetachCountingRenderBox;

        element.update(const Row());
        owner.finalizeTree();

        expect(childRender.detachCount, 1);
        expect(parentRender.children, isEmpty);
        expect(childRender.parent, isNull);
        expect(childRender.pipelineOwner, isNull);
        element.unmount();
      },
    );
  });
}

class _LoggingWidget extends StatefulWidget {
  const _LoggingWidget(this.label, this.log, {super.key});

  final String label;
  final List<String> log;

  @override
  State<_LoggingWidget> createState() => _LoggingWidgetState();
}

class _LoggingWidgetState extends State<_LoggingWidget> {
  @override
  void initState() {
    super.initState();
    widget.log.add('init:${widget.label}');
  }

  @override
  void dispose() {
    widget.log.add('dispose:${widget.label}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.log.add('build:${widget.label}');
    return Container(width: 1, height: 1);
  }
}

abstract class _TypedLifecycleWidget extends StatefulWidget {
  const _TypedLifecycleWidget(this.label, this.log, {super.key});

  final String label;
  final List<String> log;
}

class _TypeA extends _TypedLifecycleWidget {
  const _TypeA(super.label, super.log, {super.key});

  @override
  State<_TypeA> createState() => _TypedLifecycleState<_TypeA>();
}

class _TypeB extends _TypedLifecycleWidget {
  const _TypeB(super.label, super.log, {super.key});

  @override
  State<_TypeB> createState() => _TypedLifecycleState<_TypeB>();
}

class _TypeC extends _TypedLifecycleWidget {
  const _TypeC(super.label, super.log);

  @override
  State<_TypeC> createState() => _TypedLifecycleState<_TypeC>();
}

class _TypedLifecycleState<T extends _TypedLifecycleWidget> extends State<T> {
  @override
  Widget build(BuildContext context) => _LifecycleWidget(widget.label);

  @override
  void dispose() {
    widget.log.add('dispose:${widget.label}');
    super.dispose();
  }
}

class _DetachCountingWidget extends RenderObjectWidget {
  const _DetachCountingWidget();

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _DetachCountingRenderBox();
}

class _DetachCountingRenderBox extends RenderBox {
  int detachCount = 0;

  @override
  void detach() {
    detachCount++;
    super.detach();
  }
}

class _LifecycleWidget extends RenderObjectWidget {
  const _LifecycleWidget(this.label, {super.key});

  final String label;

  @override
  _LifecycleRenderBox createRenderObject(BuildContext context) =>
      _LifecycleRenderBox(label);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _LifecycleRenderBox renderObject,
  ) {
    renderObject.label = label;
  }
}

class _LifecycleRenderBox extends RenderBox {
  _LifecycleRenderBox(this.label);

  String label;
  int attachCount = 0;
  int detachCount = 0;

  @override
  void didAttach(PipelineOwner owner) {
    attachCount++;
  }

  @override
  void detach() {
    detachCount++;
    super.detach();
  }
}

_LifecycleRenderBox _lifecycleRender(Element element) =>
    Element.findRenderObjectElement(element)!.renderObject!
        as _LifecycleRenderBox;

({Element element, Object state, _LifecycleRenderBox render})
_lifecycleIdentity(Element element) => (
  element: element,
  state: (element as StatefulElement).state,
  render: _lifecycleRender(element),
);
