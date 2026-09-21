import 'dart:collection';

import 'package:noir/src/framework/build_context.dart';
import 'package:noir/src/framework/element.dart';
import 'package:noir/src/framework/owner.dart';
import 'package:noir/src/framework/widget.dart';
import 'package:test/test.dart';

void main() {
  group('BuildOwner dirty element scheduling', () {
    test('duplicate schedules rebuild an element once', () {
      final owner = BuildOwner();
      final log = <String>[];
      final element = _ProbeWidget('root', log).createElement()
        ..mount(null, owner);
      log.clear();

      owner
        ..scheduleBuild(element)
        ..scheduleBuild(element)
        ..buildScope();

      expect(log, ['root']);
      element.unmount();
      owner.dispose();
    });

    test('duplicate mounted schedules still request frames', () {
      final owner = BuildOwner();
      final log = <String>[];
      final element = _ProbeWidget('root', log).createElement()
        ..mount(null, owner);
      var frameRequests = 0;
      owner.setFrameCallback(() => frameRequests++);
      log.clear();

      owner
        ..scheduleBuild(element)
        ..scheduleBuild(element);

      expect(frameRequests, 2);
      owner.buildScope();
      expect(log, ['root']);
      element.unmount();
      owner.dispose();
    });

    test('unmounted dirty elements are skipped', () {
      final owner = BuildOwner();
      final log = <String>[];
      final element = _ProbeWidget('root', log).createElement()
        ..mount(null, owner);
      log.clear();

      owner.scheduleBuild(element);
      element.unmount();
      owner.buildScope();

      expect(log, isEmpty);
      owner.dispose();
    });

    test('parent rebuilds before child when both are dirty', () {
      final owner = BuildOwner();
      final log = <String>[];
      final parent = _ProbeWidget('parent', log).createElement()
        ..mount(null, owner);
      final child = _ProbeWidget('child', log).createElement()
        ..mount(parent, owner);
      parent.addChildForTest(child);
      log.clear();

      owner
        ..scheduleBuild(child)
        ..scheduleBuild(parent)
        ..buildScope();

      expect(log, ['parent', 'child']);
      parent.unmount();
      owner.dispose();
    });

    test('dirty elements scheduled during a build run in a later batch', () {
      final owner = BuildOwner();
      final log = <String>[];
      final parentWidget = _ProbeWidget('parent', log);
      final parent = parentWidget.createElement()..mount(null, owner);
      late _ProbeElement child;
      child = _ProbeWidget('child', log).createElement()..mount(parent, owner);
      parent.addChildForTest(child);
      parentWidget.onRebuild = () {
        log.add('parent scheduled child');
        owner.scheduleBuild(child);
      };
      log.clear();

      owner
        ..scheduleBuild(parent)
        ..buildScope();

      expect(log, ['parent', 'parent scheduled child', 'child']);
      parent.unmount();
      owner.dispose();
    });

    test('reentrant buildScope throws a clear StateError', () {
      final owner = BuildOwner();
      final widget = _ProbeWidget('root', <String>[]);
      final element = widget.createElement()..mount(null, owner);
      widget.onRebuild = owner.buildScope;

      owner.scheduleBuild(element);

      expect(
        owner.buildScope,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('cannot be re-entered'),
          ),
        ),
      );
      element.unmount();
      owner.dispose();
    });
  });

  group('BuildOwner failed build pass recovery', () {
    test('a throwing rebuild leaves unvisited elements drainable', () {
      final owner = BuildOwner();
      final log = <String>[];
      final first = _ProbeWidget('first', log);
      final firstElement = first.createElement()..mount(null, owner);
      final secondElement = _ProbeWidget('second', log).createElement()
        ..mount(null, owner);
      final thirdElement = _ProbeWidget('third', log).createElement()
        ..mount(null, owner);
      final failure = StateError('first failed');
      first.onRebuild = () => throw failure;
      log.clear();

      owner
        ..scheduleBuild(firstElement)
        ..scheduleBuild(secondElement)
        ..scheduleBuild(thirdElement);
      expect(owner.buildScope, throwsA(same(failure)));
      expect(log, ['first']);

      first.onRebuild = null;
      owner.buildScope();

      expect(
        log,
        ['first', 'second', 'third'],
        reason: 'the failed element is not retried; the rest keep their order',
      );
      firstElement.unmount();
      secondElement.unmount();
      thirdElement.unmount();
      owner.dispose();
    });

    test('a recovered element schedules normally afterwards', () {
      final owner = BuildOwner();
      final log = <String>[];
      final first = _ProbeWidget('first', log);
      final firstElement = first.createElement()..mount(null, owner);
      final secondElement = _ProbeWidget('second', log).createElement()
        ..mount(null, owner);
      first.onRebuild = () => throw StateError('first failed');

      owner
        ..scheduleBuild(firstElement)
        ..scheduleBuild(secondElement);
      expect(owner.buildScope, throwsStateError);
      first.onRebuild = null;
      log.clear();

      // A second schedule of the stranded element must not be swallowed by a
      // reservation that has no executable queue entry behind it.
      owner
        ..scheduleBuild(secondElement)
        ..buildScope();
      expect(log, ['second']);

      owner
        ..scheduleBuild(secondElement)
        ..scheduleBuild(firstElement)
        ..buildScope();
      expect(log, ['second', 'second', 'first']);
      firstElement.unmount();
      secondElement.unmount();
      owner.dispose();
    });

    test('a throwing middle element keeps only the unvisited tail', () {
      final owner = BuildOwner();
      final log = <String>[];
      final middle = _ProbeWidget('middle', log);
      final firstElement = _ProbeWidget('first', log).createElement()
        ..mount(null, owner);
      final middleElement = middle.createElement()..mount(null, owner);
      final lastElement = _ProbeWidget('last', log).createElement()
        ..mount(null, owner);
      middle.onRebuild = () => throw StateError('middle failed');
      log.clear();

      owner
        ..scheduleBuild(firstElement)
        ..scheduleBuild(middleElement)
        ..scheduleBuild(lastElement);
      expect(owner.buildScope, throwsStateError);
      middle.onRebuild = null;
      owner.buildScope();

      expect(log, ['first', 'middle', 'last']);
      firstElement.unmount();
      middleElement.unmount();
      lastElement.unmount();
      owner.dispose();
    });

    test('work scheduled by the failing rebuild survives once', () {
      final owner = BuildOwner();
      final log = <String>[];
      final first = _ProbeWidget('first', log);
      final firstElement = first.createElement()..mount(null, owner);
      final secondElement = _ProbeWidget('second', log).createElement()
        ..mount(null, owner);
      final newElement = _ProbeWidget('new', log).createElement()
        ..mount(null, owner);
      first.onRebuild = () {
        owner
          ..scheduleBuild(newElement)
          ..scheduleBuild(secondElement);
        throw StateError('first failed');
      };
      log.clear();

      owner
        ..scheduleBuild(firstElement)
        ..scheduleBuild(secondElement);
      expect(owner.buildScope, throwsStateError);
      first.onRebuild = null;
      owner.buildScope();

      expect(log, ['first', 'second', 'new']);
      firstElement.unmount();
      secondElement.unmount();
      newElement.unmount();
      owner.dispose();
    });

    test('a reservation cleared during the failed pass stays cleared', () {
      final owner = BuildOwner();
      final log = <String>[];
      final first = _ProbeWidget('first', log);
      final firstElement = first.createElement()..mount(null, owner);
      final secondElement = _ProbeWidget('second', log).createElement()
        ..mount(null, owner);
      first.onRebuild = () {
        // A direct cascade rebuild consumes the reservation.
        secondElement.rebuild();
        throw StateError('first failed');
      };
      log.clear();

      owner
        ..scheduleBuild(firstElement)
        ..scheduleBuild(secondElement);
      expect(owner.buildScope, throwsStateError);
      first.onRebuild = null;
      owner.buildScope();

      expect(log, ['first', 'second']);
      firstElement.unmount();
      secondElement.unmount();
      owner.dispose();
    });

    test('an element unmounted after the failure is not rebuilt', () {
      final owner = BuildOwner();
      final log = <String>[];
      final first = _ProbeWidget('first', log);
      final firstElement = first.createElement()..mount(null, owner);
      final secondElement = _ProbeWidget('second', log).createElement()
        ..mount(null, owner);
      first.onRebuild = () => throw StateError('first failed');
      log.clear();

      owner
        ..scheduleBuild(firstElement)
        ..scheduleBuild(secondElement);
      expect(owner.buildScope, throwsStateError);
      secondElement.unmount();
      owner.buildScope();

      expect(log, ['first']);
      firstElement.unmount();
      owner.dispose();
    });

    test('the original error and stack trace propagate', () {
      final owner = BuildOwner();
      final first = _ProbeWidget('first', <String>[]);
      final firstElement = first.createElement()..mount(null, owner);
      final secondElement = _ProbeWidget('second', <String>[]).createElement()
        ..mount(null, owner);
      final failure = StateError('first failed');
      final failureStack = StackTrace.fromString('original build stack');
      first.onRebuild = () => Error.throwWithStackTrace(failure, failureStack);
      // A frame request that fails during recovery must not replace it.
      var frameRequests = 0;
      owner.setFrameCallback(() {
        frameRequests++;
        if (frameRequests > 2) throw StateError('frame request failed');
      });

      owner
        ..scheduleBuild(firstElement)
        ..scheduleBuild(secondElement);
      Object? caught;
      StackTrace? caughtStack;
      try {
        owner.buildScope();
      } on Object catch (error, stackTrace) {
        caught = error;
        caughtStack = stackTrace;
      }

      expect(caught, same(failure));
      expect(caughtStack.toString(), failureStack.toString());
      owner.setFrameCallback(() {});
      firstElement.unmount();
      secondElement.unmount();
      owner.dispose();
    });

    test('recovered work requests a frame', () {
      final owner = BuildOwner();
      final first = _ProbeWidget('first', <String>[]);
      final firstElement = first.createElement()..mount(null, owner);
      final secondElement = _ProbeWidget('second', <String>[]).createElement()
        ..mount(null, owner);
      first.onRebuild = () => throw StateError('first failed');
      owner
        ..scheduleBuild(firstElement)
        ..scheduleBuild(secondElement);
      var frameRequests = 0;
      owner.setFrameCallback(() => frameRequests++);

      expect(owner.buildScope, throwsStateError);
      expect(frameRequests, 1);

      // Nothing was left behind, so a lone failure requests nothing.
      owner.buildScope();
      frameRequests = 0;
      owner.scheduleBuild(firstElement);
      frameRequests = 0;
      expect(owner.buildScope, throwsStateError);
      expect(frameRequests, 0);
      firstElement.unmount();
      secondElement.unmount();
      owner.dispose();
    });
  });

  group('BuildOwner.dispose finalization', () {
    test('dispose() unmounts elements still pending in the inactive set '
        '(no lost dispose)', () {
      final owner = BuildOwner();
      final log = <String>[];

      Widget buildTree({required bool includeChild}) =>
          _Wrapper(includeChild ? _Removable(log: log) : const _Other());

      final element = buildTree(includeChild: true).createElement()
        ..mount(null, owner);
      owner.buildScope();

      expect(log, ['initState']);
      log.clear();

      // Deactivate the stateful child WITHOUT flushing buildScope()
      // afterward: this leaves it pending in BuildOwner._inactiveElements,
      // exactly the state an in-flight build can be in if the app tears
      // down mid-frame, before finalizeTree() would normally run.
      element.update(buildTree(includeChild: false));

      expect(
        log,
        isEmpty,
        reason: 'dispose must not have run before finalization',
      );

      owner.dispose();

      expect(log, ['dispose']);
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

class _Wrapper extends StatelessWidget {
  const _Wrapper(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _Other extends StatelessWidget {
  const _Other();

  @override
  Widget build(BuildContext context) => const _Leaf();
}

class _Removable extends StatefulWidget {
  const _Removable({required this.log});
  final List<String> log;

  @override
  State<_Removable> createState() => _RemovableState();
}

class _RemovableState extends State<_Removable> {
  @override
  void initState() {
    super.initState();
    widget.log.add('initState');
  }

  @override
  void dispose() {
    widget.log.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const _Leaf();
}

/// Minimal non-render leaf, matching `_ProbeWidget`/`_ProbeElement` above:
/// no render object is needed to exercise `BuildOwner.dispose()`'s
/// finalization of a pending-inactive element.
class _Leaf extends Widget {
  const _Leaf();

  @override
  Element createElement() => _LeafElement(this);
}

class _LeafElement extends Element {
  _LeafElement(_Leaf super.widget);

  @override
  void performRebuild() {}
}
