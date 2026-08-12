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
