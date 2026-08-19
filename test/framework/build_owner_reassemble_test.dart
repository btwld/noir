import 'dart:collection';

import 'package:noir/src/framework/build_context.dart';
import 'package:noir/src/framework/element.dart';
import 'package:noir/src/framework/owner.dart';
import 'package:noir/src/framework/widget.dart';
import 'package:test/test.dart';

void main() {
  group('BuildOwner.reassemble', () {
    test('marks every registered element, not only the root', () {
      final owner = BuildOwner();
      final log = <String>[];
      // `_ProbeElement.performRebuild` deliberately does not reconcile its
      // children, so only an element the owner marked itself can rebuild.
      final parent = _ProbeWidget('parent', log).createElement()
        ..mount(null, owner);
      final child = _ProbeWidget('child', log).createElement()
        ..mount(parent, owner);
      parent.addChildForTest(child);
      log.clear();

      owner
        ..reassemble()
        ..buildScope();

      expect(log, <String>['parent', 'child']);
      parent.unmount();
      owner.dispose();
    });

    test('requests a frame so the marked tree actually rebuilds', () {
      final owner = BuildOwner();
      final log = <String>[];
      final element = _ProbeWidget('root', log).createElement()
        ..mount(null, owner);
      var frameRequests = 0;
      owner.setFrameCallback(() => frameRequests++);

      owner.reassemble();

      expect(frameRequests, isPositive);
      element.unmount();
      owner.dispose();
    });

    test('rebuilds a cascading tree exactly once, parent before child', () {
      final owner = BuildOwner();
      final log = <String>[];
      final element = _Node(
        'root',
        log,
        _Node('mid', log, _Leaf('leaf', log)),
      ).createElement()..mount(null, owner);
      log.clear();

      owner
        ..reassemble()
        ..buildScope();

      expect(log, <String>['root', 'mid', 'leaf']);
      element.unmount();
      owner.dispose();
    });

    test('is a no-op with no mounted elements', () {
      final owner = BuildOwner();

      expect(owner.reassemble, returnsNormally);
      expect(owner.buildScope, returnsNormally);
      owner.dispose();
    });

    test('is a no-op after dispose', () {
      final owner = BuildOwner();
      final log = <String>[];
      final element = _ProbeWidget('root', log).createElement()
        ..mount(null, owner);
      element.unmount();
      owner.dispose();
      log.clear();

      expect(owner.reassemble, returnsNormally);
      expect(log, isEmpty);
    });

    test('called from inside a build drains in a later batch', () {
      final owner = BuildOwner();
      final log = <String>[];
      final parentWidget = _ProbeWidget('parent', log);
      final parent = parentWidget.createElement()..mount(null, owner);
      final child = _ProbeWidget('child', log).createElement()
        ..mount(parent, owner);
      parent.addChildForTest(child);
      var reassembled = false;
      parentWidget.onRebuild = () {
        if (reassembled) return;
        reassembled = true;
        owner.reassemble();
      };
      log.clear();

      owner
        ..scheduleBuild(parent)
        ..buildScope();

      // The in-build call never re-enters `buildScope`; its marks drain in the
      // next batch of the same pass, each element rebuilt once by that batch.
      expect(log, <String>['parent', 'parent', 'child']);
      parent.unmount();
      owner.dispose();
    });

    test('invokes retained State callbacks parents-first, before any '
        'rebuild', () {
      final owner = BuildOwner();
      final log = <String>[];
      final element = _StatefulNode(
        'root',
        log,
        child: _StatefulNode('child', log, child: _Leaf('leaf', log)),
      ).createElement()..mount(null, owner);
      log.clear();

      owner.reassemble();
      expect(log, <String>['reassemble:root', 'reassemble:child']);

      owner.buildScope();
      expect(log, <String>[
        'reassemble:root',
        'reassemble:child',
        'build:root',
        'build:child',
        'leaf',
      ]);

      element.unmount();
      owner.dispose();
    });

    test('attempts every callback, marks the tree, and rethrows the first '
        'failure', () {
      final owner = BuildOwner();
      final log = <String>[];
      final element = _StatefulNode(
        'root',
        log,
        failReassemble: true,
        child: _StatefulNode('child', log, child: _Leaf('leaf', log)),
      ).createElement()..mount(null, owner);
      log.clear();

      expect(owner.reassemble, throwsStateError);
      expect(log, <String>[
        'reassemble:root',
        'reassemble:child',
      ], reason: 'a failing callback does not skip its siblings');

      owner.buildScope();
      expect(log.sublist(2), <String>['build:root', 'build:child', 'leaf']);

      element.unmount();
      owner.dispose();
    });

    test('skips a deactivated state that has not been finalized yet', () {
      final owner = BuildOwner();
      final log = <String>[];
      final root = _Swap(
        _StatefulNode('child', log, child: _Leaf('leaf', log)),
      ).createElement()..mount(null, owner);

      root.update(_Swap(_Leaf('replacement', <String>[])));
      log.clear();

      owner.reassemble();

      expect(log, isEmpty, reason: 'an inactive subtree is not reassembled');

      owner.buildScope();
      root.unmount();
      owner.dispose();
    });
  });
}

class _ProbeWidget extends Widget {
  _ProbeWidget(this.label, this.log);

  final String label;
  final List<String> log;
  void Function()? onRebuild;

  @override
  _ProbeElement createElement() => _ProbeElement(this);
}

class _ProbeElement extends Element {
  _ProbeElement(_ProbeWidget super.widget);

  final List<Element> _children = <Element>[];
  late final List<Element> _childrenView = UnmodifiableListView<Element>(
    _children,
  );

  @override
  List<Element> get children => _childrenView;

  @override
  _ProbeWidget get widget => super.widget as _ProbeWidget;

  void addChildForTest(Element child) => _children.add(child);

  @override
  void performRebuild() {
    widget.log.add(widget.label);
    widget.onRebuild?.call();
  }

  @override
  void unmount() {
    try {
      super.unmount();
    } finally {
      _children.clear();
    }
  }
}

/// Stateless link whose rebuild cascades into its retained child element.
class _Node extends StatelessWidget {
  const _Node(this.label, this.log, this.child);

  final String label;
  final List<String> log;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    log.add(label);
    return child;
  }
}

/// Stateful link whose retained [State] records the reassemble callback.
class _StatefulNode extends StatefulWidget {
  const _StatefulNode(
    this.label,
    this.log, {
    required this.child,
    this.failReassemble = false,
  });

  final String label;
  final List<String> log;
  final Widget child;
  final bool failReassemble;

  @override
  State<_StatefulNode> createState() => _StatefulNodeState();
}

class _StatefulNodeState extends State<_StatefulNode> {
  @override
  void reassemble() {
    super.reassemble();
    widget.log.add('reassemble:${widget.label}');
    if (widget.failReassemble) {
      throw StateError('reassemble failed for ${widget.label}');
    }
  }

  @override
  Widget build(BuildContext context) {
    widget.log.add('build:${widget.label}');
    return widget.child;
  }
}

/// Stateless link used to swap a child out for an incompatible one.
class _Swap extends StatelessWidget {
  const _Swap(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Childless tail of the cascade: no render object is needed to observe it.
class _Leaf extends Widget {
  const _Leaf(this.label, this.log);

  final String label;
  final List<String> log;

  @override
  Element createElement() => _LeafElement(this);
}

class _LeafElement extends Element {
  _LeafElement(_Leaf super.widget);

  @override
  void performRebuild() {
    final leaf = widget as _Leaf;
    leaf.log.add(leaf.label);
  }
}
