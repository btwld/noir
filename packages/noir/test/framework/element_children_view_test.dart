import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart';
import 'package:noir/src/widgets/flexible.dart' show FlexibleElement;
import 'package:test/test.dart';

void main() {
  group('Element children inspection', () {
    test('default leaf view is stable, empty, and unmodifiable', () {
      final owner = BuildOwner();
      final element = const _RenderLeafA().createElement()..mount(null, owner);
      final view = element.children;

      expect(element.children, same(view));
      expect(view, isEmpty);
      expect(() => view.add(element), throwsUnsupportedError);
      expect(view, isEmpty);

      element.unmount();
      owner.dispose();
    });

    test('component view is stable, live, ordered, and unmodifiable', () {
      final owner = BuildOwner();
      final element = const _SwitchingComponent(
        useSecondLeaf: false,
      ).createElement()..mount(null, owner);
      final view = element.children;
      final first = view.single;

      expect(element.children, same(view));
      _expectAllMutationRoutesRejected(element, view);

      element.update(const _SwitchingComponent(useSecondLeaf: true));

      expect(element.children, same(view));
      expect(view, hasLength(1));
      expect(view.single, isNot(same(first)));
      expect(view.single.widget, isA<_RenderLeafB>());

      element.unmount();
      owner.dispose();
    });

    test('single-render view is stable, live, ordered, and unmodifiable', () {
      final owner = BuildOwner();
      final element = const ConstrainedBox(
        constraints: BoxConstraints(),
        child: _RenderLeafA(),
      ).createElement()..mount(null, owner);
      final view = element.children;
      final first = view.single;

      expect(element.children, same(view));
      _expectAllMutationRoutesRejected(element, view);

      element.update(
        const ConstrainedBox(
          constraints: BoxConstraints(),
          child: _RenderLeafB(),
        ),
      );

      expect(element.children, same(view));
      expect(view, hasLength(1));
      expect(view.single, isNot(same(first)));
      expect(view.single.widget, isA<_RenderLeafB>());

      element.unmount();
      owner.dispose();
    });

    test('multi-render view follows keyed reorder, insert, and removal', () {
      final owner = BuildOwner();
      final element = Row(
        children: const [
          _StatefulLeaf('a', key: ValueKey<String>('a')),
          _StatefulLeaf('b', key: ValueKey<String>('b')),
        ],
      ).createElement()..mount(null, owner);
      final view = element.children;
      final elementA = view[0];
      final elementB = view[1];
      final stateA = (elementA as StatefulElement).state;
      final stateB = (elementB as StatefulElement).state;
      final renderA = Element.findDescendantRenderObject(elementA);
      final renderB = Element.findDescendantRenderObject(elementB);

      expect(element.children, same(view));
      _expectAllMutationRoutesRejected(element, view);

      element.update(
        Row(
          children: const [
            _StatefulLeaf('b2', key: ValueKey<String>('b')),
            _StatefulLeaf('a2', key: ValueKey<String>('a')),
            _StatefulLeaf('c', key: ValueKey<String>('c')),
          ],
        ),
      );
      final elementC = view[2];
      final stateC = (elementC as StatefulElement).state;
      final renderC = Element.findDescendantRenderObject(elementC);

      expect(element.children, same(view));
      _expectIdentityOrder(view, <Element>[elementB, elementA, elementC]);
      expect((view[0] as StatefulElement).state, same(stateB));
      expect((view[1] as StatefulElement).state, same(stateA));
      expect(Element.findDescendantRenderObject(view[0]), same(renderB));
      expect(Element.findDescendantRenderObject(view[1]), same(renderA));

      element.update(
        Row(
          children: const [
            _StatefulLeaf('b3', key: ValueKey<String>('b')),
            _StatefulLeaf('c2', key: ValueKey<String>('c')),
          ],
        ),
      );

      expect(element.children, same(view));
      _expectIdentityOrder(view, <Element>[elementB, elementC]);
      expect((view[0] as StatefulElement).state, same(stateB));
      expect((view[1] as StatefulElement).state, same(stateC));
      expect(Element.findDescendantRenderObject(view[0]), same(renderB));
      expect(Element.findDescendantRenderObject(view[1]), same(renderC));

      owner.finalizeTree();
      element.unmount();
      owner.dispose();
    });

    test('Flexible view is stable, live, ordered, and unmodifiable', () {
      final owner = BuildOwner();
      final element = Row(
        children: const [Flexible(child: _RenderLeafA())],
      ).createElement()..mount(null, owner);
      final flexibleWidgetElement = element.children.single;
      final flexibleElement = flexibleWidgetElement.children.single;
      expect(flexibleElement, isA<FlexibleElement>());
      final view = flexibleElement.children;
      final first = view.single;

      expect(flexibleElement.children, same(view));
      _expectAllMutationRoutesRejected(flexibleElement, view);

      element.update(Row(children: const [Flexible(child: _RenderLeafB())]));

      expect(flexibleElement.children, same(view));
      expect(view, hasLength(1));
      expect(view.single, isNot(same(first)));
      expect(view.single.widget, isA<_RenderLeafB>());

      element.unmount();
      owner.dispose();
    });

    test(
      'ordinary and throwing teardown empty every retained built-in view',
      () {
        final owner = BuildOwner();
        final states = <_DisposingLeafState>[];
        final failure = StateError('dispose failed');
        final element = _TeardownTree(
          states: states,
          failure: failure,
        ).createElement()..mount(null, owner);
        final componentView = element.children;
        final single = componentView.single;
        final singleView = single.children;
        final multi = singleView.single;
        final multiView = multi.children;
        final flexibleWidgetElement = multiView.first;
        final flexible = flexibleWidgetElement.children.single;
        expect(flexible, isA<FlexibleElement>());
        final flexibleView = flexible.children;

        final caught = _catchSync(element.unmount);

        expect(caught, same(failure));
        expect(componentView, isEmpty);
        expect(singleView, isEmpty);
        expect(multiView, isEmpty);
        expect(flexibleView, isEmpty);
        expect(states, hasLength(2));
        expect(states.map((state) => state.disposeCount), everyElement(1));
        expect(states.map((state) => state.mounted), everyElement(isFalse));

        expect(element.unmount, returnsNormally);
        expect(states.map((state) => state.disposeCount), everyElement(1));
        owner.dispose();
      },
    );
  });
}

void _expectAllMutationRoutesRejected(Element owner, List<Element> view) {
  final expected = List<Element>.from(view);
  final snapshots = expected.map(_ElementSnapshot.new).toList();
  final first = view.first;
  final routes = <String, void Function()>{
    'operator []=': () => view[0] = first,
    'length=': () => view.length = view.length,
    'add': () => view.add(first),
    'addAll': () => view.addAll(<Element>[first]),
    'insert': () => view.insert(0, first),
    'insertAll': () => view.insertAll(0, <Element>[first]),
    'remove': () => view.remove(first),
    'removeAt': () => view.removeAt(0),
    'removeLast': view.removeLast,
    'removeRange': () => view.removeRange(0, 1),
    'clear': view.clear,
    'setAll': () => view.setAll(0, <Element>[first]),
    'setRange': () => view.setRange(0, 1, <Element>[first]),
    'fillRange': () => view.fillRange(0, 1, first),
    'replaceRange': () => view.replaceRange(0, 1, <Element>[first]),
    'removeWhere': () => view.removeWhere((_) => true),
    'retainWhere': () => view.retainWhere((_) => true),
    'sort': () => view.sort((_, _) => 0),
    'shuffle': view.shuffle,
  };

  for (final MapEntry(key: name, value: mutate) in routes.entries) {
    expect(
      mutate,
      throwsUnsupportedError,
      reason: '$name must not mutate ${owner.runtimeType}.children',
    );
    expect(owner.children, same(view));
    _expectIdentityOrder(view, expected);
    for (final snapshot in snapshots) {
      snapshot.expectUnchanged();
    }
  }
}

void _expectIdentityOrder(List<Element> actual, List<Element> expected) {
  expect(actual, hasLength(expected.length));
  for (var index = 0; index < expected.length; index++) {
    expect(actual[index], same(expected[index]), reason: 'child $index');
  }
}

final class _ElementSnapshot {
  _ElementSnapshot(this.element)
    : parent = element.parent,
      depth = element.depth,
      active = element.active,
      renderObject = Element.findDescendantRenderObject(element),
      renderParent = Element.findDescendantRenderObject(element)?.parent;

  final Element element;
  final Element? parent;
  final int depth;
  final bool active;
  final RenderObject? renderObject;
  final RenderObject? renderParent;

  void expectUnchanged() {
    expect(element.parent, same(parent));
    expect(element.depth, depth);
    expect(element.active, active);
    expect(Element.findDescendantRenderObject(element), same(renderObject));
    expect(renderObject?.parent, same(renderParent));
  }
}

Object? _catchSync(void Function() action) {
  try {
    action();
    return null;
  } on Object catch (error) {
    return error;
  }
}

class _SwitchingComponent extends StatelessWidget {
  const _SwitchingComponent({required this.useSecondLeaf});

  final bool useSecondLeaf;

  @override
  Widget build(BuildContext context) =>
      useSecondLeaf ? const _RenderLeafB() : const _RenderLeafA();
}

class _StatefulLeaf extends StatefulWidget {
  const _StatefulLeaf(this.label, {super.key});

  final String label;

  @override
  State<_StatefulLeaf> createState() => _StatefulLeafState();
}

class _StatefulLeafState extends State<_StatefulLeaf> {
  @override
  Widget build(BuildContext context) => _ProbeRenderWidget(widget.label);
}

class _DisposingLeaf extends StatefulWidget {
  const _DisposingLeaf({required this.states, this.failure});

  final List<_DisposingLeafState> states;
  final Error? failure;

  @override
  State<_DisposingLeaf> createState() => _DisposingLeafState();
}

class _DisposingLeafState extends State<_DisposingLeaf> {
  int disposeCount = 0;

  @override
  void initState() {
    super.initState();
    widget.states.add(this);
  }

  @override
  Widget build(BuildContext context) => const _RenderLeafA();

  @override
  void dispose() {
    super.dispose();
    disposeCount++;
    final failure = widget.failure;
    if (failure != null) {
      throw failure;
    }
  }
}

class _TeardownTree extends StatelessWidget {
  const _TeardownTree({required this.states, required this.failure});

  final List<_DisposingLeafState> states;
  final Error failure;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(),
    child: Row(
      children: [
        Flexible(
          child: _DisposingLeaf(states: states, failure: failure),
        ),
        _DisposingLeaf(states: states),
      ],
    ),
  );
}

class _ProbeRenderWidget extends RenderObjectWidget {
  const _ProbeRenderWidget(this.label);

  final String label;

  @override
  RenderObject createRenderObject(BuildContext context) => _ProbeRenderBox();

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _ProbeRenderBox renderObject,
  ) {}
}

class _RenderLeafA extends RenderObjectWidget {
  const _RenderLeafA();

  @override
  RenderObject createRenderObject(BuildContext context) => _ProbeRenderBox();
}

class _RenderLeafB extends RenderObjectWidget {
  const _RenderLeafB();

  @override
  RenderObject createRenderObject(BuildContext context) => _ProbeRenderBox();
}

class _ProbeRenderBox extends RenderBox {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = const Size(1, 1);
  }
}
