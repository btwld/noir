import 'dart:collection';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart' show RenderBox, RenderFlex;
import 'package:noir/src/framework/element.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:noir/src/widgets/flexible.dart' show FlexibleElement;
import 'package:test/test.dart';

import '../helpers/test_element_host.dart';

void main() {
  group('end-to-end atomic deactivate via render Element callers', () {
    test(
      'single-child _updateChild(null) preflight rejection leaves edges intact',
      () {
        // Real path: SingleChildRenderObjectElement._updateChild(null) →
        // BuildOwner.deactivateChild. Must fail if callers re-introduce a
        // pre-drop before deactivateChild.
        final host = TestElementHost()
          ..mount(
            const SizedBox(
              width: 4,
              height: 1,
              child: _Poisonable(child: Text('x')),
            ),
          );

        final singleChild = _findSingleChildRenderObjectElement(host.root!);
        final childElement = singleChild.children.single;
        final parentRo = singleChild.renderObject!;
        final childRo = Element.findRenderObjectElement(
          childElement,
        )!.renderObject!;
        expect(identical(childRo.parent, parentRo), isTrue);
        expect(identical(childElement.parent, singleChild), isTrue);
        expect(childElement.active, isTrue);

        _poisonWithGhost(childElement);

        // Drive the Element caller, not BuildOwner.deactivateChild directly.
        expect(
          () => host.root!.update(const SizedBox(width: 4, height: 1)),
          throwsStateError,
        );

        expect(identical(childElement.parent, singleChild), isTrue);
        expect(childElement.active, isTrue);
        expect(identical(childRo.parent, parentRo), isTrue);
        // Parent still tracks the same child Element slot.
        expect(identical(singleChild.children.single, childElement), isTrue);

        _repairGhost(childElement);
        host.dispose();
      },
    );

    test('single-child type-swap preflight rejection leaves edges intact', () {
      // Real path: SingleChildRenderObjectElement._updateChild when
      // Widget.canUpdate is false → deactivateChild then inflate.
      final host = TestElementHost()
        ..mount(
          const SizedBox(
            width: 4,
            height: 1,
            child: _Poisonable(child: Text('x')),
          ),
        );

      final singleChild = _findSingleChildRenderObjectElement(host.root!);
      final childElement = singleChild.children.single;
      final parentRo = singleChild.renderObject!;
      final childRo = Element.findRenderObjectElement(
        childElement,
      )!.renderObject!;

      _poisonWithGhost(childElement);

      // Text cannot update to Padding — forces deactivate + inflate path.
      expect(
        () => host.root!.update(
          const SizedBox(
            width: 4,
            height: 1,
            child: Padding(padding: EdgeInsets.zero, child: Text('y')),
          ),
        ),
        throwsStateError,
      );

      expect(identical(childElement.parent, singleChild), isTrue);
      expect(childElement.active, isTrue);
      expect(identical(childRo.parent, parentRo), isTrue);
      expect(identical(singleChild.children.single, childElement), isTrue);

      _repairGhost(childElement);
      host.dispose();
    });

    test(
      'multi-child _deactivateChild preflight rejection leaves edges intact',
      () {
        // Real path: MultiChildRenderObjectElement leftover loop →
        // _deactivateChild → BuildOwner.deactivateChild.
        final host = TestElementHost()
          ..mount(
            const Row(
              children: [
                _Poisonable(key: ValueKey<String>('a'), child: Text('a')),
                Text('b', key: ValueKey<String>('b')),
              ],
            ),
          );

        final multi = _findMultiChildRenderObjectElement(host.root!);
        expect(multi.children, hasLength(2));
        final victim = multi.children.firstWhere(
          (e) => e.widget.key == const ValueKey<String>('a'),
        );
        final parentRo = multi.renderObject!;
        final childRo = Element.findRenderObjectElement(victim)!.renderObject!;
        expect(identical(childRo.parent, parentRo), isTrue);
        expect(identical(victim.parent, multi), isTrue);

        _poisonWithGhost(victim);

        // Drop key 'a' so the multi-child leftover path deactivates victim.
        expect(
          () => host.root!.update(
            const Row(children: [Text('b', key: ValueKey<String>('b'))]),
          ),
          throwsStateError,
        );

        expect(identical(victim.parent, multi), isTrue);
        expect(victim.active, isTrue);
        expect(identical(childRo.parent, parentRo), isTrue);
        // Multi-child list not published past the rejected deactivate.
        expect(multi.children, hasLength(2));
        expect(multi.children, contains(victim));

        _repairGhost(victim);
        host.dispose();
      },
    );

    test(
      'Flex multi-child _deactivateChild preflight rejection leaves edges intact',
      () {
        // FlexRenderObjectElement extends MultiChild; real leftover deactivate
        // must not pre-drop specialized flex render edges.
        final host = TestElementHost()
          ..mount(
            const Column(
              children: [
                Expanded(
                  key: ValueKey<String>('flex'),
                  child: _Poisonable(child: Text('flex-a')),
                ),
                Text('b', key: ValueKey<String>('b')),
              ],
            ),
          );

        final flex = _findMultiChildRenderObjectElement(host.root!);
        final victim = flex.children.firstWhere(
          (e) => e.widget.key == const ValueKey<String>('flex'),
        );
        final parentRo = flex.renderObject!;
        final childRo = Element.findRenderObjectElement(victim)!.renderObject!;
        expect(identical(childRo.parent, parentRo), isTrue);

        _poisonWithGhost(victim);

        expect(
          () => host.root!.update(
            const Column(children: [Text('b', key: ValueKey<String>('b'))]),
          ),
          throwsStateError,
        );

        expect(identical(childRo.parent, parentRo), isTrue);
        expect(identical(victim.parent, flex), isTrue);
        expect(victim.active, isTrue);
        expect(flex.children, contains(victim));

        _repairGhost(victim);
        host.dispose();
      },
    );

    test(
      'successful single-child nulling detaches render through Element update',
      () {
        final host = TestElementHost()
          ..mount(const SizedBox(width: 4, height: 1, child: Text('x')));
        final single = _findSingleChildRenderObjectElement(host.root!);
        final child = single.children.single;
        final childRo = Element.findRenderObjectElement(child)!.renderObject!;
        expect(childRo.parent, isNotNull);

        // Real caller path with no poison: deactivate succeeds and detaches.
        host.root!.update(const SizedBox(width: 4, height: 1));
        host.owner.buildScope();

        expect(single.children, isEmpty);
        expect(child.active, isFalse);
        expect(childRo.parent, isNull);

        host.dispose();
      },
    );

    test(
      'successful multi-child removal detaches render through Element update',
      () {
        final host = TestElementHost()
          ..mount(
            const Row(
              children: [
                Text('a', key: ValueKey<String>('a')),
                Text('b', key: ValueKey<String>('b')),
              ],
            ),
          );
        final multi = _findMultiChildRenderObjectElement(host.root!);
        final victim = multi.children.firstWhere(
          (e) => e.widget.key == const ValueKey<String>('a'),
        );
        final parentRo = multi.renderObject!;
        final childRo = Element.findRenderObjectElement(victim)!.renderObject!;
        expect(identical(childRo.parent, parentRo), isTrue);

        host.root!.update(
          const Row(children: [Text('b', key: ValueKey<String>('b'))]),
        );
        host.owner.buildScope();

        expect(victim.active, isFalse);
        expect(childRo.parent, isNull);
        expect(multi.children, hasLength(1));
        expect(multi.children.single.widget.key, const ValueKey<String>('b'));

        host.dispose();
      },
    );

    for (final kind in _DeactivateOwnerKind.values) {
      final name = switch (kind) {
        _DeactivateOwnerKind.multi =>
          'multi removal keeps a committed render error primary over a '
              'deactivate error',
        _ => '${kind.name} removal completes after State.deactivate throws',
      };
      test(name, () {
        final key = GlobalKey<_ThrowingDeactivateState>();
        final fixture = _createThrowingDeactivateFixture(
          kind,
          key,
          StateError('${kind.name} deactivate failed'),
          StackTrace.fromString('${kind.name}-deactivate-stack'),
        );

        _expectThrowingDeactivateCompletion(fixture, key);

        if (kind == _DeactivateOwnerKind.multi) {
          fixture.host.owner.setFrameCallback(() {});
        }
        fixture.host.dispose();
      });
    }

    test(
      'generic multi-child pre-mutation detach failure preserves both trees',
      () {
        final lifecycle = _DetachLifecycle();
        final host = TestElementHost()
          ..mount(
            _ThrowingMulti(children: [_DetachWrapper(lifecycle: lifecycle)]),
          );
        final multi = host.root! as MultiChildRenderObjectElement;
        final victim = multi.children.single;
        final renderLeaf = Element.findRenderObjectElement(victim)!;
        final renderParent = multi.renderObject! as _ThrowingMultiRenderBox;
        final renderChild = renderLeaf.renderObject!;
        final originalDepth = victim.depth;
        final error = StateError('injected pre-mutation detach failure');
        renderParent.errorBeforeDetach = error;

        expect(
          () => multi.update(const _ThrowingMulti()),
          throwsA(same(error)),
        );

        expect(victim.parent, same(multi));
        expect(victim.depth, originalDepth);
        expect(victim.active, isTrue);
        expect(multi.children.single, same(victim));
        expect(renderChild.parent, same(renderParent));
        expect(renderParent.children.single, same(renderChild));

        renderParent.errorBeforeDetach = null;
        multi.update(const _ThrowingMulti());
        expect(renderChild.parent, isNull);
        expect(multi.children, isEmpty);
        expect(victim.active, isFalse);
        expect(victim.mounted, isTrue);
        expect(lifecycle.unmounts, 0);

        host.owner.buildScope();
        expect(victim.mounted, isFalse);
        expect(lifecycle.unmounts, 1);
        host.owner.finalizeTree();
        expect(lifecycle.unmounts, 1);
        host.dispose();
      },
    );

    test('single-child committed scheduling failure publishes removal', () {
      final host = TestElementHost()
        ..mount(const Align(child: Text('x')))
        ..pumpFrame(
          constraints: const BoxConstraints.tight(width: 4, height: 1),
        );
      addTearDown(() {
        host.owner.setFrameCallback(() {});
        host.dispose();
      });

      final single = host.root! as SingleChildRenderObjectElement;
      final victim = single.children.single;
      final renderParent = single.renderObject!;
      final renderChild = Element.findRenderObjectElement(
        victim,
      )!.renderObject!;
      final error = StateError('single committed scheduling failure');
      final stackTrace = StackTrace.fromString('single-commit-stack');
      host.owner.setFrameCallback(
        () => Error.throwWithStackTrace(error, stackTrace),
      );

      final caught = _catchSync(() => single.update(const Align()));

      expect(caught.error, same(error));
      expect(caught.stackTrace.toString(), stackTrace.toString());
      expect(renderChild.parent, isNull);
      expect(renderParent.children, isEmpty);
      expect(victim.parent, isNull);
      expect(victim.depth, 0);
      expect(victim.active, isFalse);
      expect(single.children, isEmpty);
    });

    test(
      'component committed scheduling failure publishes incompatible removal',
      () {
        final host = TestElementHost()
          ..mount(const Align(child: _SwapComponent()))
          ..pumpFrame(
            constraints: const BoxConstraints.tight(width: 4, height: 1),
          );
        addTearDown(() {
          host.owner.setFrameCallback(() {});
          host.dispose();
        });

        final single = host.root! as SingleChildRenderObjectElement;
        final component = single.children.single as StatelessElement;
        final victim = component.children.single;
        final renderParent = single.renderObject!;
        final renderChild = Element.findRenderObjectElement(
          victim,
        )!.renderObject!;
        final error = StateError('component committed scheduling failure');
        final stackTrace = StackTrace.fromString('component-commit-stack');
        host.owner.setFrameCallback(
          () => Error.throwWithStackTrace(error, stackTrace),
        );

        final caught = _catchSync(
          () => component.update(const _SwapComponent(showSecond: true)),
        );

        expect(caught.error, same(error));
        expect(caught.stackTrace.toString(), stackTrace.toString());
        expect(renderChild.parent, isNull);
        expect(renderParent.children, isEmpty);
        expect(victim.parent, isNull);
        expect(victim.depth, 0);
        expect(victim.active, isFalse);
        expect(component.children, isEmpty);
      },
    );

    test('generic multi committed scheduling failure publishes removal', () {
      final host = TestElementHost()
        ..mount(const _ThrowingMulti(children: [Text('x')]))
        ..pumpFrame(
          constraints: const BoxConstraints.tight(width: 4, height: 1),
        );
      addTearDown(() {
        host.owner.setFrameCallback(() {});
        host.dispose();
      });

      final multi = host.root! as MultiChildRenderObjectElement;
      final victim = multi.children.single;
      final renderParent = multi.renderObject!;
      final renderChild = Element.findRenderObjectElement(
        victim,
      )!.renderObject!;
      final error = StateError('multi committed scheduling failure');
      final stackTrace = StackTrace.fromString('multi-commit-stack');
      host.owner.setFrameCallback(
        () => Error.throwWithStackTrace(error, stackTrace),
      );

      final caught = _catchSync(() => multi.update(const _ThrowingMulti()));

      expect(caught.error, same(error));
      expect(caught.stackTrace.toString(), stackTrace.toString());
      expect(renderChild.parent, isNull);
      expect(renderParent.children, isEmpty);
      expect(victim.parent, isNull);
      expect(victim.depth, 0);
      expect(victim.active, isFalse);
      expect(multi.children, isEmpty);
    });

    test('Flexible and Flex publish committed incompatible removal', () {
      final host = TestElementHost()
        ..mount(const Row(children: [Flexible(child: Text('x'))]))
        ..pumpFrame(
          constraints: const BoxConstraints.tight(width: 4, height: 1),
        );
      addTearDown(() {
        host.owner.setFrameCallback(() {});
        host.dispose();
      });

      final flex = host.root! as MultiChildRenderObjectElement;
      final flexible = _findFlexibleElement(flex);
      final victim = flexible.children.single;
      final renderParent = flex.renderObject! as RenderFlex;
      final renderChild = Element.findRenderObjectElement(
        victim,
      )!.renderObject!;
      final error = StateError('flex committed scheduling failure');
      final stackTrace = StackTrace.fromString('flex-commit-stack');
      host.owner.setFrameCallback(
        () => Error.throwWithStackTrace(error, stackTrace),
      );

      final caught = _catchSync(
        () => flex.update(
          const Row(
            children: [
              Flexible(
                child: Padding(padding: EdgeInsets.zero, child: Text('y')),
              ),
            ],
          ),
        ),
      );

      expect(caught.error, same(error));
      expect(caught.stackTrace.toString(), stackTrace.toString());
      expect(renderChild.parent, isNull);
      expect(renderParent.childrenBoxes, isEmpty);
      expect(victim.parent, isNull);
      expect(victim.depth, 0);
      expect(victim.active, isFalse);
      expect(flexible.children, isEmpty);
    });
  });
}

enum _DeactivateOwnerKind { single, component, multi, flexible }

typedef _ThrowingDeactivateFixture = ({
  TestElementHost host,
  Element victim,
  List<Element> ownerChildren,
  void Function() remove,
  Object expectedError,
  StackTrace expectedStackTrace,
});

_ThrowingDeactivateFixture _createThrowingDeactivateFixture(
  _DeactivateOwnerKind kind,
  GlobalKey<_ThrowingDeactivateState> key,
  Object hookError,
  StackTrace hookStack,
) {
  final probe = _ThrowingDeactivate(
    key: key,
    failure: hookError,
    stackTrace: hookStack,
  );
  final host = TestElementHost();
  switch (kind) {
    case _DeactivateOwnerKind.single:
      host.mount(Align(child: probe));
      final owner = host.root! as SingleChildRenderObjectElement;
      return (
        host: host,
        victim: owner.children.single,
        ownerChildren: owner.children,
        remove: () => owner.update(const Align()),
        expectedError: hookError,
        expectedStackTrace: hookStack,
      );
    case _DeactivateOwnerKind.component:
      host.mount(_SwapComponent(first: probe));
      final owner = host.root! as StatelessElement;
      return (
        host: host,
        victim: owner.children.single,
        ownerChildren: owner.children,
        remove: () =>
            owner.update(_SwapComponent(first: probe, showSecond: true)),
        expectedError: hookError,
        expectedStackTrace: hookStack,
      );
    case _DeactivateOwnerKind.multi:
      host
        ..mount(Row(children: [probe]))
        ..pumpFrame(
          constraints: const BoxConstraints.tight(width: 4, height: 1),
        );
      final owner = host.root! as MultiChildRenderObjectElement;
      final renderError = StateError('multi scheduling failed');
      final renderStack = StackTrace.fromString('multi-scheduling-stack');
      host.owner.setFrameCallback(
        () => Error.throwWithStackTrace(renderError, renderStack),
      );
      return (
        host: host,
        victim: owner.children.single,
        ownerChildren: owner.children,
        remove: () => owner.update(const Row()),
        expectedError: renderError,
        expectedStackTrace: renderStack,
      );
    case _DeactivateOwnerKind.flexible:
      host.mount(Row(children: [Flexible(child: probe)]));
      final row = host.root! as MultiChildRenderObjectElement;
      final owner = _findFlexibleElement(row);
      return (
        host: host,
        victim: owner.children.single,
        ownerChildren: owner.children,
        remove: () => row.update(
          const Row(children: [Flexible(child: Text('replacement'))]),
        ),
        expectedError: hookError,
        expectedStackTrace: hookStack,
      );
  }
}

void _expectThrowingDeactivateCompletion(
  _ThrowingDeactivateFixture fixture,
  GlobalKey<_ThrowingDeactivateState> key,
) {
  final state = key.currentState!;
  final renderObject = Element.findRenderObjectElement(
    fixture.victim,
  )!.renderObject!;
  final caught = _catchSync(fixture.remove);
  expect(caught.error, same(fixture.expectedError));
  expect(caught.stackTrace.toString(), fixture.expectedStackTrace.toString());
  expect(renderObject.parent, isNull);
  expect(fixture.victim.parent, isNull);
  expect(fixture.victim.depth, 0);
  expect(fixture.victim.active, isFalse);
  expect(fixture.ownerChildren, isNot(contains(fixture.victim)));
  expect(state.deactivateCount, 1);
  expect(state.wasActiveAndMounted, isTrue);
  expect(state.mounted, isTrue);
  fixture.host.owner.finalizeTree();
  expect(state.disposeCount, 1);
  expect(state.mounted, isFalse);
  expect(key.currentContext, isNull);
  fixture.host.owner.finalizeTree();
  expect(state.deactivateCount, 1);
  expect(state.disposeCount, 1);
}

final class _Caught {
  const _Caught(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

_Caught _catchSync(void Function() action) {
  try {
    action();
  } on Object catch (error, stackTrace) {
    return _Caught(error, stackTrace);
  }
  throw StateError('Expected action to throw');
}

void _poisonWithGhost(Element target) {
  _findPoisonableElement(target).addGhostForTest();
}

void _repairGhost(Element target) {
  _findPoisonableElement(target).removeGhostsForTest();
}

_PoisonableElement _findPoisonableElement(Element root) {
  _PoisonableElement? found;
  void walk(Element element) {
    if (element is _PoisonableElement) {
      found = element;
      return;
    }
    element.visitChildren(walk);
  }

  walk(root);
  return found!;
}

SingleChildRenderObjectElement _findSingleChildRenderObjectElement(
  Element root,
) {
  SingleChildRenderObjectElement? found;
  void walk(Element e) {
    if (e is SingleChildRenderObjectElement) {
      found = e;
      return;
    }
    e.visitChildren(walk);
  }

  walk(root);
  return found!;
}

MultiChildRenderObjectElement _findMultiChildRenderObjectElement(Element root) {
  MultiChildRenderObjectElement? found;
  void walk(Element e) {
    if (e is MultiChildRenderObjectElement) {
      found = e;
      return;
    }
    e.visitChildren(walk);
  }

  walk(root);
  return found!;
}

FlexibleElement _findFlexibleElement(Element root) {
  FlexibleElement? found;
  void walk(Element element) {
    if (element is FlexibleElement) {
      found = element;
      return;
    }
    element.visitChildren(walk);
  }

  walk(root);
  return found!;
}

/// Unregistered Element used only to poison child lists for preflight rejection.
class _GhostWidget extends Widget {
  @override
  Element createElement() => _GhostElement(this);
}

class _GhostElement extends Element {
  _GhostElement(super.widget);

  @override
  void performRebuild() {}
}

class _Poisonable extends Widget {
  const _Poisonable({required this.child, super.key});

  final Widget child;

  @override
  _PoisonableElement createElement() => _PoisonableElement(this);
}

class _PoisonableElement extends Element {
  _PoisonableElement(_Poisonable super.widget);

  final List<Element> _children = <Element>[];
  late final List<Element> _childrenView = UnmodifiableListView<Element>(
    _children,
  );

  @override
  _Poisonable get widget => super.widget as _Poisonable;

  @override
  List<Element> get children => _childrenView;

  @override
  void performRebuild() {
    final candidate = widget.child;
    if (_children.isEmpty) {
      _children.add(Element.inflateWidget(candidate, this));
      return;
    }
    final current = _children.first;
    if (Widget.canUpdate(current.widget, candidate)) {
      current.update(candidate);
      return;
    }
    owner.deactivateChild(current);
    final child = Element.inflateWidget(candidate, this);
    _children
      ..clear()
      ..add(child);
  }

  void addGhostForTest() {
    final ghost = _GhostElement(_GhostWidget());
    updateElementParent(ghost, this);
    _children.add(ghost);
  }

  void removeGhostsForTest() {
    final ghosts = _children.whereType<_GhostElement>().toList();
    for (final ghost in ghosts) {
      _children.remove(ghost);
      updateElementParent(ghost, null);
    }
  }

  @override
  RenderObject? findRenderObject() =>
      _children.isEmpty ? null : _children.first.findRenderObject();

  @override
  void unmount() {
    try {
      super.unmount();
    } finally {
      _children.clear();
    }
  }
}

class _DetachLifecycle {
  int unmounts = 0;
}

class _SwapComponent extends StatelessWidget {
  const _SwapComponent({this.showSecond = false, this.first});

  final bool showSecond;
  final Widget? first;

  @override
  Widget build(BuildContext context) => showSecond
      ? const Padding(padding: EdgeInsets.zero, child: Text('y'))
      : first ?? const Text('x');
}

class _ThrowingMulti extends MultiChildRenderObjectWidget {
  const _ThrowingMulti({super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ThrowingMultiRenderBox();
}

class _ThrowingMultiRenderBox extends RenderBox {
  Error? errorBeforeDetach;

  @override
  void dropChild(RenderObject child) {
    final error = errorBeforeDetach;
    if (error != null) {
      throw error;
    }
    super.dropChild(child);
  }
}

class _DetachWrapper extends StatelessWidget {
  const _DetachWrapper({required this.lifecycle});

  final _DetachLifecycle lifecycle;

  @override
  StatelessElement createElement() => _CountingStatelessElement(this);

  @override
  Widget build(BuildContext context) => const Text('x');
}

class _CountingStatelessElement extends StatelessElement {
  _CountingStatelessElement(_DetachWrapper super.widget);

  @override
  void unmount() {
    if (mounted) {
      (widget as _DetachWrapper).lifecycle.unmounts++;
    }
    super.unmount();
  }
}

class _ThrowingDeactivate extends StatefulWidget {
  const _ThrowingDeactivate({
    required this.failure,
    required this.stackTrace,
    super.key,
  });

  final Object failure;
  final StackTrace stackTrace;

  @override
  State<_ThrowingDeactivate> createState() => _ThrowingDeactivateState();
}

class _ThrowingDeactivateState extends State<_ThrowingDeactivate> {
  int deactivateCount = 0;
  int disposeCount = 0;
  bool? wasActiveAndMounted;

  @override
  void deactivate() {
    deactivateCount++;
    wasActiveAndMounted = context.element.active && mounted;
    Error.throwWithStackTrace(widget.failure, widget.stackTrace);
  }

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 1, height: 1);
}
