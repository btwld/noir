// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes, cascade_invocations

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/tui_binding.dart' show runTuiAppForTesting;
import 'package:noir/src/framework/element.dart';
import 'package:test/test.dart';

void main() {
  group('framework identity collections', () {
    test('inherited dependents use Element identity', () {
      final owner = BuildOwner();
      final notifications = <_DependencyNotification>[];
      final first = _EqualElement(const _LeafWidget(), notifications)
        ..mount(null, owner);
      final second = _EqualElement(const _LeafWidget(), notifications)
        ..mount(null, owner);
      final inherited = InheritedElement(const _ProbeInherited());

      addTearDown(() {
        if (first.mounted) first.unmount();
        if (second.mounted) second.unmount();
        owner.dispose();
      });

      expect(identical(first, second), isFalse);

      inherited
        ..updateDependencies(first, 'first-aspect')
        ..updateDependencies(second, 'second-aspect')
        ..notifyDependents();

      expect(notifications, hasLength(2));
      expect(notifications[0].dependent, same(first));
      expect(notifications[0].aspect, 'first-aspect');
      expect(notifications[1].dependent, same(second));
      expect(notifications[1].aspect, 'second-aspect');

      notifications.clear();
      inherited
        ..removeDependent(first)
        ..notifyDependents();

      expect(notifications, hasLength(1));
      expect(notifications.single.dependent, same(second));
      expect(notifications.single.aspect, 'second-aspect');
    });

    test(
      'reverse inherited dependencies and removal snapshots use identity',
      () {
        final owner = BuildOwner();
        final inheritedElements = <_EqualInheritedElement>[];
        final notifications = <InheritedElement>[];

        Widget buildTree({required bool listen}) => _OuterInherited(
          elements: inheritedElements,
          child: _InnerInherited(
            elements: inheritedElements,
            child: _DualDependencyProbe(
              listen: listen,
              notifications: notifications,
            ),
          ),
        );

        final root = buildTree(listen: true).createElement()
          ..mount(null, owner);
        addTearDown(() {
          if (root.mounted) root.unmount();
          owner.dispose();
        });

        expect(inheritedElements, hasLength(2));
        expect(identical(inheritedElements[0], inheritedElements[1]), isFalse);

        root.update(buildTree(listen: false));
        owner.buildScope();

        for (final inherited in inheritedElements) {
          inherited.notifyDependents();
        }

        expect(
          notifications,
          isEmpty,
          reason:
              'stopping both dependencies must unregister the exact probe '
              'from both equality-equal inherited ancestors',
        );
      },
    );

    test(
      'focus membership, primary focus, detach, and traversal use identity',
      () async {
        final keyCalls = <FocusNode>[];
        final first = _EqualFocusNode(debugLabel: 'first');
        final second = _EqualFocusNode(debugLabel: 'second');
        final third = FocusNode(debugLabel: 'third');
        final app = runTuiAppForTesting(
          Column(
            children: [
              Focus(
                focusNode: first,
                child: const SizedBox(width: 1, height: 1),
              ),
              Focus(
                focusNode: second,
                onKeyEvent: (node, event) {
                  keyCalls.add(node);
                  return KeyEventResult.handled;
                },
                child: const SizedBox(width: 1, height: 1),
              ),
              Focus(
                focusNode: third,
                child: const SizedBox(width: 1, height: 1),
              ),
            ],
          ),
          headless: true,
        );

        addTearDown(() {
          app.dispose();
          first.dispose();
          second.dispose();
          third.dispose();
        });

        final manager = app.buildOwner.focusManager;
        _expectIdentityOrder(manager.rootScope.children, [
          first,
          second,
          third,
        ]);

        second.requestFocus();
        expect(manager.primaryFocus, same(second));
        expect(first.hasPrimaryFocus, isFalse);
        expect(second.hasPrimaryFocus, isTrue);

        expect(manager.focusNext(), isTrue);
        expect(manager.primaryFocus, same(third));

        second.requestFocus();
        first.detach();
        _expectIdentityOrder(manager.traversalOrder(), [second, third]);

        app.inputManager.dispatchKey(
          KeyEvent(logicalKey: LogicalKeyboardKey.escape, keyCode: 27),
        );
        await Future<void>.delayed(Duration.zero);

        expect(keyCalls, hasLength(1));
        expect(keyCalls.single, same(second));
      },
    );

    test('focus children expose one live unmodifiable identity view', () {
      final owner = BuildOwner();
      final root = const Row(
        children: [
          SizedBox(width: 1, height: 1),
          SizedBox(width: 1, height: 1),
        ],
      ).createElement()..mount(null, owner);
      final childElements = root.children.toList();
      final parent = FocusNode(debugLabel: 'parent');
      final first = _EqualFocusNode(debugLabel: 'first');
      final second = _EqualFocusNode(debugLabel: 'second');
      final parentAttachment = parent.attach(root.buildContext);
      final view = parent.children;

      addTearDown(() {
        first.dispose();
        second.dispose();
        parentAttachment.detach();
        parent.dispose();
        if (root.mounted) root.unmount();
        owner.dispose();
      });

      expect(parent.children, same(view));
      first.attach(childElements[0].buildContext);
      second.attach(childElements[1].buildContext);
      _expectIdentityOrder(view, [first, second]);

      expect(() => (view as Set<FocusNode>).clear(), throwsUnsupportedError);
      expect(first.parent, same(parent));
      expect(second.parent, same(parent));
      _expectIdentityOrder(view, [first, second]);

      first.detach();
      _expectIdentityOrder(view, [second]);
      second.detach();
      expect(view, isEmpty);
    });

    test('an equality-equal supplied FocusNode is still a replacement', () {
      final owner = BuildOwner();
      final first = _EqualFocusNode(debugLabel: 'first');
      final second = _EqualFocusNode(debugLabel: 'second');
      final element = Focus(
        focusNode: first,
        child: const SizedBox(width: 1, height: 1),
      ).createElement()..mount(null, owner);

      addTearDown(() {
        if (element.mounted) element.unmount();
        owner.dispose();
        first.dispose();
        second.dispose();
      });

      expect(first.isAttached, isTrue);
      expect(second.isAttached, isFalse);

      element.update(
        Focus(focusNode: second, child: const SizedBox(width: 1, height: 1)),
      );

      expect(first.isAttached, isFalse);
      expect(second.isAttached, isTrue);
      expect(owner.focusManager.nodeForElement(element), same(second));
    });
  });
}

void _expectIdentityOrder(
  Iterable<FocusNode> actual,
  List<FocusNode> expected,
) {
  final nodes = actual.toList();
  expect(nodes, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(
      identical(nodes[i], expected[i]),
      isTrue,
      reason: 'focus node at index $i must be the exact expected instance',
    );
  }
}

class _DependencyNotification {
  const _DependencyNotification(this.dependent, this.aspect);

  final Element dependent;
  final Object? aspect;
}

class _LeafWidget extends Widget {
  const _LeafWidget();

  @override
  Element createElement() => _LeafElement(this);
}

class _LeafElement extends Element {
  _LeafElement(super.widget);

  @override
  void performRebuild() {}
}

class _EqualElement extends Element {
  _EqualElement(super.widget, this.notifications);

  final List<_DependencyNotification> notifications;

  @override
  void performRebuild() {}

  @override
  void notifyDependent(InheritedElement inherited, Object? aspect) {
    notifications.add(_DependencyNotification(this, aspect));
  }

  @override
  bool operator ==(Object other) => other is _EqualElement;

  @override
  int get hashCode => 0;
}

class _ProbeInherited extends InheritedWidget {
  const _ProbeInherited() : super(child: const _LeafWidget());

  @override
  bool updateShouldNotify(covariant _ProbeInherited oldWidget) => false;
}

class _OuterInherited extends InheritedWidget {
  const _OuterInherited({required this.elements, required super.child});

  final List<_EqualInheritedElement> elements;

  @override
  InheritedElement createElement() {
    final element = _EqualInheritedElement(this);
    elements.add(element);
    return element;
  }

  @override
  bool updateShouldNotify(covariant _OuterInherited oldWidget) => false;
}

class _InnerInherited extends InheritedWidget {
  const _InnerInherited({required this.elements, required super.child});

  final List<_EqualInheritedElement> elements;

  @override
  InheritedElement createElement() {
    final element = _EqualInheritedElement(this);
    elements.add(element);
    return element;
  }

  @override
  bool updateShouldNotify(covariant _InnerInherited oldWidget) => false;
}

class _EqualInheritedElement extends InheritedElement {
  _EqualInheritedElement(super.widget);

  @override
  bool operator ==(Object other) => other is _EqualInheritedElement;

  @override
  int get hashCode => 0;
}

class _DualDependencyProbe extends Widget {
  const _DualDependencyProbe({
    required this.listen,
    required this.notifications,
  });

  final bool listen;
  final List<InheritedElement> notifications;

  @override
  Element createElement() => _DualDependencyProbeElement(this);
}

class _DualDependencyProbeElement extends Element {
  _DualDependencyProbeElement(_DualDependencyProbe super.widget);

  @override
  _DualDependencyProbe get widget => super.widget as _DualDependencyProbe;

  @override
  void performRebuild() {
    if (!widget.listen) return;
    dependOnInheritedElementOfExactType<_OuterInherited>();
    dependOnInheritedElementOfExactType<_InnerInherited>();
  }

  @override
  void notifyDependent(InheritedElement inherited, Object? aspect) {
    widget.notifications.add(inherited);
  }
}

class _EqualFocusNode extends FocusNode {
  _EqualFocusNode({super.debugLabel});

  @override
  bool operator ==(Object other) => other is _EqualFocusNode;

  @override
  int get hashCode => 0;
}
