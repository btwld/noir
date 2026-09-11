import 'dart:async';

import 'package:noir/src/core/color.dart';
import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/flex.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:noir/src/widgets/row_column.dart';
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

  test(
    'a layout request raised during layout is honoured in the same flush',
    () {
      final owner = PipelineOwner();
      final parent = _SequenceParentProbe();
      final a = _ProbeRenderBox();
      var marked = false;
      // `a` is laid out before `b`, so a mark raised from `b` targets a node the
      // pass has already finished with.
      final b = _HookedProbe(
        onLayout: () {
          if (marked) return;
          marked = true;
          a.markNeedsLayout();
        },
      );
      parent
        ..adoptChild(a)
        ..adoptChild(b)
        ..attach(owner);
      const constraints = BoxConstraints.tight(width: 10, height: 4);

      owner.flushLayout(parent, constraints);

      expect(a.layoutCount, 2, reason: 'the mid-pass request must be retried');
      expect(a.debugNeedsLayout, isFalse);
      expect(owner.debugNeedsLayout, isFalse);
    },
  );

  test(
    'an active ancestor invalidated by child layout recomputes its size',
    () {
      final owner = PipelineOwner();
      late final RenderFlex root;
      final child = _HookedProbe(onLayout: () => root.spacing = 5);
      root = RenderFlex(
        direction: Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        children: [child, _ProbeRenderBox()],
      )..attach(owner);

      owner.flushLayout(root, const BoxConstraints(maxWidth: 20, maxHeight: 1));

      expect(root.size.width, 5, reason: 'the new spacing contributes to size');
      expect(child.layoutCount, 2);
      expect(owner.debugNeedsLayout, isFalse);
    },
  );

  test('a self-invalidating layout fails after exactly the pass cap', () {
    final owner = PipelineOwner();
    late final _HookedProbe root;
    root = _HookedProbe(onLayout: () => root.markNeedsLayout())..attach(owner);

    expect(
      () => owner.flushLayout(
        root,
        const BoxConstraints.tight(width: 1, height: 1),
      ),
      throwsStateError,
    );
    expect(root.layoutCount, PipelineOwner.maxLayoutPasses);
  });

  test('adopting a child during layout retries the invalidated parent', () {
    final owner = PipelineOwner();
    late final _HookedProbe root;
    _ProbeRenderBox? adopted;
    root = _HookedProbe(
      onLayout: () {
        if (adopted != null) return;
        // Adoption also invalidates the parent while its layout is active.
        final child = _ProbeRenderBox();
        adopted = child;
        root.adoptChild(child);
        child.layout(const BoxConstraints.tight(width: 1, height: 1));
      },
    )..attach(owner);

    owner.flushLayout(root, const BoxConstraints.tight(width: 10, height: 4));

    expect(root.layoutCount, 2);
    expect(adopted!.layoutCount, 1);
    expect(owner.debugNeedsLayout, isFalse);
  });

  test('a child request satisfied later in the pass needs no retry', () {
    final owner = PipelineOwner();
    final child = _ProbeRenderBox();
    final root = _SequenceParentProbe()
      ..adoptChild(_HookedProbe(onLayout: child.markNeedsLayout))
      ..adoptChild(child)
      ..attach(owner);

    owner.flushLayout(root, const BoxConstraints.tight(width: 10, height: 4));

    expect(root.layoutCount, 1);
    expect(child.layoutCount, 1);
    expect(owner.debugNeedsLayout, isFalse);
  });

  test('a layout request that never settles fails after the pass cap', () {
    final owner = PipelineOwner();
    final parent = _SequenceParentProbe();
    final a = _ProbeRenderBox();
    final b = _HookedProbe(onLayout: a.markNeedsLayout);
    parent
      ..adoptChild(a)
      ..adoptChild(b)
      ..attach(owner);
    const constraints = BoxConstraints.tight(width: 10, height: 4);

    expect(
      () => owner.flushLayout(parent, constraints),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains('did not settle'), contains('_ProbeRenderBox')),
        ),
      ),
    );
    expect(owner.debugNeedsLayout, isFalse, reason: 'the queue is drained');
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

/// Runs [onLayout] on every layout, after the probe has recorded it.
class _HookedProbe extends _ProbeRenderBox {
  _HookedProbe({required this.onLayout});

  final void Function() onLayout;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    super.performBoxLayout(constraints);
    onLayout();
  }
}

/// Lays its children out in adoption order with its own constraints.
class _SequenceParentProbe extends _ProbeRenderBox {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    super.performBoxLayout(constraints);
    for (final child in children) {
      child.layout(constraints);
    }
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
