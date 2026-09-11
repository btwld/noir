// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'dart:collection';

import 'package:noir/src/framework/element.dart';
import 'package:noir/src/framework/owner.dart';
import 'package:noir/src/framework/widget.dart';
import 'package:test/test.dart';

void main() {
  group('failure-atomic deactivation', () {
    test('missing registration rejects without mutating the live tree', () {
      final owner = BuildOwner();
      final root = _Probe('root').createElement()..mount(null, owner);
      final child = _Probe('child').createElement()..mount(root, owner);
      root.addChildForTest(child);

      final orphan = _Probe('orphan').createElement();
      expect(() => owner.deactivateChild(orphan), throwsStateError);
      expect(root.depth, 0);
      expect(child.depth, 1);
      expect(child.parent, same(root));
      expect(orphan.parent, isNull);

      root.unmount();
      owner.dispose();
    });

    test('cycle in the child graph rejects without mutation', () {
      final owner = BuildOwner();
      final root = _Probe('root').createElement()..mount(null, owner);
      final child = _Probe('child').createElement()..mount(root, owner);
      root.addChildForTest(child);
      child.addChildForTest(root);
      updateElementParent(root, child);

      expect(() => owner.deactivateChild(root), throwsStateError);
      expect(root.active, isTrue);
      expect(child.active, isTrue);
      expect(root.parent, same(child));
      expect(child.parent, same(root));
      expect(root.depth, 0);
      expect(child.depth, 1);

      child.removeChildForTest(root);
      updateElementParent(root, null);
      root.unmount();
      owner.dispose();
    });

    test('inconsistent parent edge rejects without mutation', () {
      final owner = BuildOwner();
      final root = _Probe('root').createElement()..mount(null, owner);
      final child = _Probe('child').createElement()..mount(root, owner);
      final grandchild = _Probe('grandchild').createElement()
        ..mount(child, owner);
      root.addChildForTest(child);
      child.addChildForTest(grandchild);

      updateElementParent(grandchild, root);
      final childDepth = child.depth;
      final grandchildDepth = grandchild.depth;

      expect(() => owner.deactivateChild(child), throwsStateError);
      expect(child.parent, same(root));
      expect(grandchild.parent, same(root));
      expect(child.depth, childDepth);
      expect(grandchild.depth, grandchildDepth);
      expect(child.active, isTrue);
      expect(grandchild.active, isTrue);

      updateElementParent(grandchild, child);
      root.unmount();
      owner.dispose();
    });

    test('unregistered descendant rejects without mutation', () {
      final owner = BuildOwner();
      final root = _Probe('root').createElement()..mount(null, owner);
      final child = _Probe('child').createElement()..mount(root, owner);
      root.addChildForTest(child);

      final ghost = _Probe('ghost').createElement();
      updateElementParent(ghost, child);
      child.addChildForTest(ghost);

      expect(() => owner.deactivateChild(child), throwsStateError);
      expect(child.parent, same(root));
      expect(child.depth, 1);
      expect(child.active, isTrue);

      child.removeChildForTest(ghost);
      updateElementParent(ghost, null);
      root.unmount();
      owner.dispose();
    });

    test(
      'successful deactivation rebases subtree depth under a null parent',
      () {
        final owner = BuildOwner();
        final root = _Probe('root').createElement()..mount(null, owner);
        final branch = _Probe('branch').createElement()..mount(root, owner);
        final deep = _Probe('deep').createElement()..mount(branch, owner);
        final leaf = _Probe('leaf').createElement()..mount(deep, owner);
        root.addChildForTest(branch);
        branch.addChildForTest(deep);
        deep.addChildForTest(leaf);

        owner.deactivateChild(deep);
        branch.removeChildForTest(deep);

        expect(deep.parent, isNull);
        expect(deep.depth, 0);
        expect(leaf.parent, same(deep));
        expect(leaf.depth, 1);
        expect(deep.active, isFalse);
        expect(leaf.active, isFalse);

        owner.finalizeTree();
        expect(deep.mounted, isFalse);
        expect(leaf.mounted, isFalse);

        root.unmount();
        owner.dispose();
      },
    );

    test('deactivateChild publishes a null parent after preflight', () {
      final owner = BuildOwner();
      final root = _Probe('root').createElement()..mount(null, owner);
      final child = _Probe('child').createElement()..mount(root, owner);
      root.addChildForTest(child);

      owner.deactivateChild(child);
      root.removeChildForTest(child);
      expect(child.parent, isNull);
      expect(child.depth, 0);
      expect(child.active, isFalse);

      owner
        ..buildScope()
        ..dispose();
    });

    test('BuildOwner keeps equality-overriding Elements distinct', () {
      final owner = BuildOwner();
      final rebuilds = <String>[];
      final firstRoot = _EqualElement(_Probe('first-root', rebuilds: rebuilds))
        ..mount(null, owner);
      final firstChild = _EqualElement(
        _Probe('first-child', rebuilds: rebuilds),
      )..mount(firstRoot, owner);
      firstRoot.addChildForTest(firstChild);
      final secondRoot = _EqualElement(
        _Probe('second-root', rebuilds: rebuilds),
      )..mount(null, owner);

      expect(firstRoot, equals(firstChild));
      expect(firstRoot, equals(secondRoot));
      expect(identical(firstRoot, firstChild), isFalse);
      expect(identical(firstRoot, secondRoot), isFalse);
      rebuilds.clear();

      owner
        ..scheduleBuild(firstChild)
        ..scheduleBuild(secondRoot)
        ..scheduleBuild(firstRoot)
        ..buildScope();
      expect(rebuilds, ['second-root', 'first-root', 'first-child']);

      owner.deactivateChild(firstRoot);
      expect(firstRoot.depth, 0);
      expect(firstChild.depth, 1);
      expect(firstRoot.active, isFalse);
      expect(firstChild.active, isFalse);
      expect(secondRoot.active, isTrue);

      owner
        ..deactivateChild(secondRoot)
        ..finalizeTree();
      expect(firstRoot.mounted, isFalse);
      expect(firstChild.mounted, isFalse);
      expect(secondRoot.mounted, isFalse);
      owner.dispose();
    });
  });
}

class _Probe extends Widget {
  _Probe(this.label, {this.rebuilds});

  final String label;
  final List<String>? rebuilds;

  @override
  _ProbeElement createElement() => _ProbeElement(this);

  @override
  String toString() => 'Probe($label)';
}

class _ProbeElement extends Element {
  _ProbeElement(_Probe super.widget);

  final List<Element> _children = <Element>[];
  late final List<Element> _childrenView = UnmodifiableListView<Element>(
    _children,
  );

  @override
  _Probe get widget => super.widget as _Probe;

  @override
  List<Element> get children => _childrenView;

  void addChildForTest(Element child) => _children.add(child);

  void removeChildForTest(Element child) => _children.remove(child);

  @override
  void performRebuild() => widget.rebuilds?.add(widget.label);

  @override
  void unmount() {
    try {
      super.unmount();
    } finally {
      _children.clear();
    }
  }
}

class _EqualElement extends _ProbeElement {
  _EqualElement(super.widget);

  @override
  bool operator ==(Object other) => other is _EqualElement;

  @override
  int get hashCode => 0;
}
