// ignore_for_file: cascade_invocations
import 'dart:async';

import 'package:noir/src/core/color.dart';
import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:noir/src/widgets/scroll_box.dart';
import 'package:test/test.dart';

void main() {
  test('attached render object schedules initial layout and paint', () {
    var visualUpdates = 0;
    final owner = PipelineOwner(onNeedVisualUpdate: () => visualUpdates++);
    final root = _ProbeRenderBox();

    root.attach(owner);

    expect(root.pipelineOwner, same(owner));
    expect(root.debugNeedsLayout, isTrue);
    expect(root.debugNeedsPaint, isTrue);
    expect(owner.debugNeedsLayout, isTrue);
    expect(owner.debugNeedsPaint, isTrue);
    expect(visualUpdates, 1);
  });

  test('flushLayout lays out a dirty root and clears layout dirtiness', () {
    final owner = PipelineOwner();
    final root = _ProbeRenderBox()..attach(owner);
    const constraints = BoxConstraints.tight(width: 10, height: 4);

    owner.flushLayout(root, constraints);

    expect(root.layoutCount, 1);
    expect(root.lastConstraints, same(constraints));
    expect(root.size, const Size(10, 4));
    expect(root.debugNeedsLayout, isFalse);
    expect(owner.debugNeedsLayout, isFalse);
    expect(root.debugNeedsPaint, isTrue);
    expect(owner.debugNeedsPaint, isTrue);
  });

  test('flushLayout relayouts when root constraints change', () {
    final owner = PipelineOwner();
    final root = _ProbeRenderBox()..attach(owner);

    owner.flushLayout(root, const BoxConstraints.tight(width: 10, height: 4));
    owner.flushLayout(root, const BoxConstraints.tight(width: 10, height: 4));
    owner.flushLayout(root, const BoxConstraints.tight(width: 12, height: 4));

    expect(root.layoutCount, 2);
    expect(root.size, const Size(12, 4));
  });

  test('markNeedsLayout implies paint', () {
    final owner = PipelineOwner();
    final root = _ProbeRenderBox()..attach(owner);
    var paintCount = 0;
    const constraints = BoxConstraints.tight(width: 10, height: 4);

    owner.flushLayout(root, constraints);
    owner.flushPaint(root, (_) => paintCount++);
    root.markNeedsLayout();

    owner.flushLayout(root, constraints);
    final painted = owner.flushPaint(root, (_) => paintCount++);

    expect(root.layoutCount, 2);
    expect(painted, isTrue);
    expect(paintCount, 2);
    expect(root.debugNeedsLayout, isFalse);
    expect(root.debugNeedsPaint, isFalse);
  });

  test('markNeedsPaint flushes paint without layout', () {
    final owner = PipelineOwner();
    final root = _ProbeRenderBox()..attach(owner);
    var paintCount = 0;
    const constraints = BoxConstraints.tight(width: 10, height: 4);

    owner.flushLayout(root, constraints);
    owner.flushPaint(root, (_) => paintCount++);
    root.markNeedsPaint();

    final painted = owner.flushPaint(root, (_) => paintCount++);

    expect(root.layoutCount, 1);
    expect(painted, isTrue);
    expect(paintCount, 2);
    expect(root.debugNeedsPaint, isFalse);
  });

  test('detaching the only queued subtree clears both former-owner queues', () {
    final owner = PipelineOwner();
    final root = _ProbeRenderBox()..attach(owner);
    const constraints = BoxConstraints.tight(width: 10, height: 4);
    owner.flushLayout(root, constraints);
    owner.flushPaint(root, (_) {});

    root
      ..markNeedsLayout()
      ..markNeedsPaint()
      ..detach();

    expect(root.pipelineOwner, isNull);
    expect(owner.debugNeedsLayout, isFalse);
    expect(owner.debugNeedsPaint, isFalse);
    expect(
      owner.flushPaint(root, (_) => fail('detached work was painted')),
      isFalse,
    );
  });

  test(
    'detaching one queued subtree preserves unrelated attached dirty work',
    () {
      final owner = PipelineOwner();
      final detached = _ProbeRenderBox()..attach(owner);
      final retained = _ProbeRenderBox()..attach(owner);
      const constraints = BoxConstraints.tight(width: 10, height: 4);
      owner.flushLayout(detached, constraints);
      owner.flushPaint(detached, (_) {});
      detached.markNeedsLayout();
      retained.markNeedsPaint();

      detached.detach();

      expect(detached.pipelineOwner, isNull);
      expect(retained.pipelineOwner, same(owner));
      expect(owner.debugNeedsPaint, isTrue);
    },
  );

  test(
    'detached mutation stays local and does not request a former-owner frame',
    () {
      var visualUpdates = 0;
      final owner = PipelineOwner(onNeedVisualUpdate: () => visualUpdates++);
      final parent = _ProbeRenderBox();
      final child = _ProbeRenderBox();
      final grandchild = _ProbeRenderBox();
      child.adoptChild(grandchild);
      parent.adoptChild(child);
      parent.attach(owner);
      const constraints = BoxConstraints.tight(width: 10, height: 4);
      owner.flushLayout(parent, constraints);
      owner.flushPaint(parent, (_) {});

      parent.dropChild(child);
      owner.flushLayout(parent, constraints);
      owner.flushPaint(parent, (_) {});
      final updatesAfterDrop = visualUpdates;
      child.markNeedsLayout();
      grandchild.markNeedsPaint();

      expect(parent.pipelineOwner, same(owner));
      expect(child.pipelineOwner, isNull);
      expect(grandchild.pipelineOwner, isNull);
      expect(child.debugNeedsLayout, isTrue);
      expect(grandchild.debugNeedsPaint, isTrue);
      expect(owner.debugNeedsLayout, isFalse);
      expect(owner.debugNeedsPaint, isFalse);
      expect(visualUpdates, updatesAfterDrop);
    },
  );

  test(
    'scheduleLayout rejects detached and live foreign nodes without mutation',
    () {
      final ownerA = PipelineOwner();
      final ownerB = PipelineOwner();
      final detached = _ProbeRenderBox();
      final foreign = _ProbeRenderBox()..attach(ownerA);
      final detachedDirty = detached.debugNeedsLayout;
      final foreignDirty = foreign.debugNeedsLayout;

      expect(() => ownerB.scheduleLayout(detached), throwsStateError);
      expect(() => ownerB.scheduleLayout(foreign), throwsStateError);

      expect(detached.pipelineOwner, isNull);
      expect(detached.debugNeedsLayout, detachedDirty);
      expect(foreign.pipelineOwner, same(ownerA));
      expect(foreign.debugNeedsLayout, foreignDirty);
      expect(ownerB.debugNeedsLayout, isFalse);
      expect(ownerB.debugNeedsPaint, isFalse);
    },
  );

  test('schedulePaint rejects a foreign node before disposed-owner return', () {
    final ownerA = PipelineOwner();
    final ownerB = PipelineOwner()..dispose();
    final foreign = _ProbeRenderBox()..attach(ownerA);
    final dirty = foreign.debugNeedsPaint;

    expect(() => ownerB.schedulePaint(foreign), throwsStateError);

    expect(foreign.pipelineOwner, same(ownerA));
    expect(foreign.debugNeedsPaint, dirty);
    expect(ownerB.debugNeedsPaint, isFalse);
  });

  test('attach rejects a foreign owner without changing either owner', () {
    var updatesA = 0;
    var updatesB = 0;
    final ownerA = PipelineOwner(onNeedVisualUpdate: () => updatesA++);
    final ownerB = PipelineOwner(onNeedVisualUpdate: () => updatesB++);
    final root = _ProbeRenderBox();
    final child = _ProbeRenderBox();
    root.adoptChild(child);
    root.attach(ownerA);
    final beforeA = updatesA;
    final beforeB = updatesB;

    expect(() => root.attach(ownerB), throwsStateError);

    expect(root.pipelineOwner, same(ownerA));
    expect(child.pipelineOwner, same(ownerA));
    expect(updatesA, beforeA);
    expect(updatesB, beforeB);
    expect(ownerB.debugNeedsLayout, isFalse);
    expect(ownerB.debugNeedsPaint, isFalse);
  });

  test('adopting a foreign-owned subtree is failure atomic', () {
    var updatesA = 0;
    var updatesB = 0;
    final ownerA = PipelineOwner(onNeedVisualUpdate: () => updatesA++);
    final ownerB = PipelineOwner(onNeedVisualUpdate: () => updatesB++);
    final parent = _ProbeRenderBox()..attach(ownerB);
    final child = _ProbeRenderBox()..attach(ownerA);
    final beforeA = updatesA;
    final beforeB = updatesB;

    expect(() => parent.adoptChild(child), throwsStateError);

    expect(parent.children, isEmpty);
    expect(child.parent, isNull);
    expect(child.pipelineOwner, same(ownerA));
    expect(updatesA, beforeA);
    expect(updatesB, beforeB);
  });

  test('attach preflight rejects a foreign-owned grandchild atomically', () {
    var updatesA = 0;
    var updatesB = 0;
    final ownerA = PipelineOwner(onNeedVisualUpdate: () => updatesA++);
    final ownerB = PipelineOwner(onNeedVisualUpdate: () => updatesB++);
    final root = _ProbeRenderBox();
    final grandchild = _ProbeRenderBox();
    root.adoptChild(grandchild);
    grandchild.attach(ownerA);
    final beforeA = updatesA;
    final beforeB = updatesB;

    expect(() => root.attach(ownerB), throwsStateError);

    expect(root.pipelineOwner, isNull);
    expect(grandchild.pipelineOwner, same(ownerA));
    expect(grandchild.parent, same(root));
    expect(root.children, [same(grandchild)]);
    expect(updatesA, beforeA);
    expect(updatesB, beforeB);
    expect(ownerB.debugNeedsLayout, isFalse);
    expect(ownerB.debugNeedsPaint, isFalse);
  });

  test(
    'adopt preflight rejects a foreign-owned grandchild before edge mutation',
    () {
      var updatesA = 0;
      var updatesB = 0;
      final ownerA = PipelineOwner(onNeedVisualUpdate: () => updatesA++);
      final ownerB = PipelineOwner(onNeedVisualUpdate: () => updatesB++);
      final parent = _ProbeRenderBox()..attach(ownerB);
      final child = _ProbeRenderBox();
      final grandchild = _ProbeRenderBox();
      child.adoptChild(grandchild);
      grandchild.attach(ownerA);
      final beforeA = updatesA;
      final beforeB = updatesB;

      expect(() => parent.adoptChild(child), throwsStateError);

      expect(parent.children, isEmpty);
      expect(child.parent, isNull);
      expect(child.pipelineOwner, isNull);
      expect(grandchild.pipelineOwner, same(ownerA));
      expect(updatesA, beforeA);
      expect(updatesB, beforeB);
    },
  );

  test(
    'new subtree attach schedules initial layout and paint after owner assignment',
    () {
      var updates = 0;
      final owner = PipelineOwner(onNeedVisualUpdate: () => updates++);
      final root = _ProbeRenderBox();
      final child = _ProbeRenderBox();
      final grandchild = _ProbeRenderBox();
      child.adoptChild(grandchild);
      root.adoptChild(child);

      root.attach(owner);

      expect(
        [root.pipelineOwner, child.pipelineOwner, grandchild.pipelineOwner],
        [same(owner), same(owner), same(owner)],
      );
      expect([
        root.debugNeedsLayout,
        child.debugNeedsLayout,
        grandchild.debugNeedsLayout,
      ], everyElement(isTrue));
      expect([
        root.debugNeedsPaint,
        child.debugNeedsPaint,
        grandchild.debugNeedsPaint,
      ], everyElement(isTrue));
      expect(updates, 3);

      const constraints = BoxConstraints.tight(width: 10, height: 4);
      owner.flushLayout(root, constraints);
      owner.flushPaint(root, (_) {});
      final afterFlush = updates;
      root.attach(owner);
      expect(updates, afterFlush);

      root.detach();
      root.detach();
      expect(
        [root.pipelineOwner, child.pipelineOwner, grandchild.pipelineOwner],
        [isNull, isNull, isNull],
      );
    },
  );

  test(
    'explicit drop then adopt supports same-owner and cross-owner reparent',
    () {
      final ownerA = PipelineOwner();
      final ownerB = PipelineOwner();
      final parentA = _ProbeRenderBox()..attach(ownerA);
      final parentB = _ProbeRenderBox()..attach(ownerA);
      final parentC = _ProbeRenderBox()..attach(ownerB);
      final child = _ProbeRenderBox();
      final grandchild = _ProbeRenderBox();
      child.adoptChild(grandchild);
      parentA.adoptChild(child);

      parentA.dropChild(child);
      expect(child.pipelineOwner, isNull);
      expect(grandchild.pipelineOwner, isNull);
      parentB.adoptChild(child);
      expect(child.parent, same(parentB));
      expect(child.pipelineOwner, same(ownerA));
      expect(grandchild.pipelineOwner, same(ownerA));

      parentB.dropChild(child);
      parentC.adoptChild(child);
      expect(child.parent, same(parentC));
      expect(child.pipelineOwner, same(ownerB));
      expect(grandchild.pipelineOwner, same(ownerB));
    },
  );

  test(
    'post-commit attach completes every schedule and hook before rethrow',
    () {
      final visualError = StateError('visual');
      var visualCalls = 0;
      final owner = PipelineOwner(
        onNeedVisualUpdate: () {
          visualCalls++;
          throw visualError;
        },
      );
      final root = _AttachHookProbe();
      final child = _AttachHookProbe();
      final grandchild = _AttachHookProbe();
      child.adoptChild(grandchild);
      root.adoptChild(child);

      expect(() => root.attach(owner), throwsA(same(visualError)));

      expect(
        [root.pipelineOwner, child.pipelineOwner, grandchild.pipelineOwner],
        [same(owner), same(owner), same(owner)],
      );
      expect(
        [root.attachCount, child.attachCount, grandchild.attachCount],
        [1, 1, 1],
      );
      expect([
        root.debugNeedsLayout,
        child.debugNeedsLayout,
        grandchild.debugNeedsLayout,
      ], everyElement(isTrue));
      expect(visualCalls, 3);
    },
  );

  test('throwing attach hook does not skip later hooks or scheduling', () {
    final hookError = StateError('hook');
    final owner = PipelineOwner();
    final root = _AttachHookProbe(onAttach: () => throw hookError);
    final child = _AttachHookProbe();
    root.adoptChild(child);

    expect(() => root.attach(owner), throwsA(same(hookError)));

    expect(root.pipelineOwner, same(owner));
    expect(child.pipelineOwner, same(owner));
    expect(root.attachCount, 1);
    expect(child.attachCount, 1);
    expect(root.debugNeedsLayout, isTrue);
    expect(child.debugNeedsLayout, isTrue);
  });

  test(
    'throwing visual update still registers a nested ScrollBox listener',
    () {
      final visualError = StateError('visual');
      var visualCalls = 0;
      final owner = PipelineOwner(
        onNeedVisualUpdate: () {
          visualCalls++;
          throw visualError;
        },
      );
      final controller = ScrollController();
      final scroll = RenderScrollBox(
        controller: controller,
        scrollDirection: Axis.vertical,
        showScrollbar: true,
        scrollbarColor: Color.white,
        trackColor: Color.black,
      );
      final root = _AttachHookProbe()..adoptChild(scroll);

      expect(() => root.attach(owner), throwsA(same(visualError)));

      expect(root.pipelineOwner, same(owner));
      expect(scroll.pipelineOwner, same(owner));
      expect(root.attachCount, 1);
      expect(root.debugNeedsLayout, isTrue);
      expect(scroll.debugNeedsLayout, isTrue);
      expect(owner.debugNeedsLayout, isTrue);
      expect(owner.debugNeedsPaint, isTrue);
      expect(visualCalls, 2);

      owner
        ..flushLayout(root, const BoxConstraints.tight(width: 10, height: 4))
        ..flushPaint(root, (_) {});

      Object? reportedError;
      runZonedGuarded(
        () => controller.updateMaxScrollExtent(10),
        (error, _) => reportedError = error,
      );
      expect(reportedError, same(visualError));
      expect(scroll.debugNeedsLayout, isFalse);
      expect(scroll.debugNeedsPaint, isTrue);
      expect(owner.debugNeedsLayout, isFalse);
      expect(owner.debugNeedsPaint, isTrue);
      expect(visualCalls, 3);
    },
  );

  test('same-owner attach does not repeat post-commit hook', () {
    final owner = PipelineOwner();
    final root = _AttachHookProbe()..attach(owner);
    expect(root.attachCount, 1);

    root.attach(owner);

    expect(root.attachCount, 1);
  });
}

class _ProbeRenderBox extends RenderBox {
  int layoutCount = 0;
  Constraints? lastConstraints;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    layoutCount++;
    lastConstraints = constraints;
    size = Size(
      constraints.maxWidth ?? constraints.minWidth,
      constraints.maxHeight ?? constraints.minHeight,
    );
  }
}

class _AttachHookProbe extends _ProbeRenderBox {
  _AttachHookProbe({this.onAttach});

  final void Function()? onAttach;
  int attachCount = 0;

  @override
  void didAttach(PipelineOwner owner) {
    attachCount++;
    onAttach?.call();
  }
}
