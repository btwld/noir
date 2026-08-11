// ignore_for_file: cascade_invocations
import 'package:noir/src/painting/box_decoration.dart';
import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/constrained_box.dart';
import 'package:noir/src/rendering/decorated_box.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:noir/src/rendering/padding.dart';
import 'package:noir/src/rendering/positioned_box.dart';
import 'package:noir/src/rendering/proxy_box.dart';
import 'package:noir/src/rendering/render_view.dart';
import 'package:test/test.dart';

void main() {
  group('package-internal single-child transition', () {
    test(
      'proxy replacement publishes one child before visual failure escapes',
      () {
        var updates = 0;
        var shouldThrow = false;
        final callbackError = StateError('visual update failed');
        final owner = PipelineOwner(
          onNeedVisualUpdate: () {
            updates++;
            if (shouldThrow) {
              throw callbackError;
            }
          },
        );
        final current = _ProbeRenderBox();
        final parent = RenderProxyBox(current)..attach(owner);
        _flushClean(owner, parent);
        updates = 0;
        shouldThrow = true;
        final next = _ProbeRenderBox();

        expect(() => parent.child = next, throwsA(same(callbackError)));

        expect(parent.child, same(next));
        expect(parent.children, [same(next)]);
        expect(current.parent, isNull);
        expect(current.pipelineOwner, isNull);
        expect(next.parent, same(parent));
        expect(next.pipelineOwner, same(owner));
        expect(owner.debugNeedsLayout, isTrue);
        expect(owner.debugNeedsPaint, isTrue);
        expect(updates, 2);
      },
    );

    test(
      'single-child removal publishes empty state before visual failure escapes',
      () {
        var updates = 0;
        var shouldThrow = false;
        final callbackError = StateError('visual update failed');
        final owner = PipelineOwner(
          onNeedVisualUpdate: () {
            updates++;
            if (shouldThrow) {
              throw callbackError;
            }
          },
        );
        final current = _ProbeRenderBox();
        final parent = RenderProxyBox(current)..attach(owner);
        _flushClean(owner, parent);
        updates = 0;
        shouldThrow = true;

        expect(() => parent.child = null, throwsA(same(callbackError)));

        expect(parent.child, isNull);
        expect(parent.children, isEmpty);
        expect(current.parent, isNull);
        expect(current.pipelineOwner, isNull);
        expect(owner.debugNeedsLayout, isTrue);
        expect(owner.debugNeedsPaint, isTrue);
        expect(updates, 1);
      },
    );

    test(
      'replacement stops empty when child detach reports a lifecycle error',
      () {
        var updates = 0;
        final owner = PipelineOwner(onNeedVisualUpdate: () => updates++);
        final detachError = StateError('detach failed');
        final current = _ThrowingDetachBox(detachError);
        final parent = RenderProxyBox(current)..attach(owner);
        _flushClean(owner, parent);
        updates = 0;
        final next = _ProbeRenderBox();

        expect(() => parent.child = next, throwsA(same(detachError)));

        expect(parent.child, isNull);
        expect(parent.children, isEmpty);
        expect(current.parent, isNull);
        expect(current.pipelineOwner, isNull);
        expect(next.parent, isNull);
        expect(next.pipelineOwner, isNull);
        expect(owner.debugNeedsLayout, isTrue);
        expect(owner.debugNeedsPaint, isTrue);
        expect(updates, 1);
      },
    );

    test(
      'RenderView insertion publishes one child before visual failure escapes',
      () {
        var updates = 0;
        var shouldThrow = false;
        final callbackError = StateError('visual update failed');
        final owner = PipelineOwner(
          onNeedVisualUpdate: () {
            updates++;
            if (shouldThrow) {
              throw callbackError;
            }
          },
        );
        final view = RenderView(width: 1, height: 1)..attach(owner);
        _flushClean(owner, view);
        updates = 0;
        shouldThrow = true;
        final child = _ProbeRenderObject();

        expect(() => view.setChild(child), throwsA(same(callbackError)));

        expect(view.child, same(child));
        expect(view.children, [same(child)]);
        expect(child.parent, same(view));
        expect(child.pipelineOwner, same(owner));
        expect(owner.debugNeedsLayout, isTrue);
        expect(owner.debugNeedsPaint, isTrue);
        expect(updates, 2);
      },
    );

    test('direct adopt and drop use the authoritative single-child edge', () {
      final parent = RenderProxyBox();
      final first = _ProbeRenderBox();

      parent.adoptChild(first);

      expect(parent.child, same(first));
      expect(parent.children, [same(first)]);
      final visited = <RenderObject>[];
      parent.visitChildren(visited.add);
      expect(visited, [same(first)]);
      final second = _ProbeRenderBox();
      expect(() => parent.adoptChild(second), throwsStateError);
      expect(second.parent, isNull);

      parent.dropChild(first);

      expect(parent.child, isNull);
      expect(parent.children, isEmpty);
      expect(first.parent, isNull);
    });

    test('RenderView directly adopts a non-box child', () {
      final view = RenderView(width: 1, height: 1);
      final child = _ProbeRenderObject();

      view.adoptChild(child);

      expect(view.child, same(child));
      expect(view.children, [same(child)]);
      expect(child.parent, same(view));
    });

    test('typed owners reject direct non-box adoption without mutation', () {
      final owners = <String, RenderObjectWithSingleChild>{
        'RenderProxyBox': RenderProxyBox(),
        'RenderConstrainedBox': RenderConstrainedBox(
          additionalConstraints: const BoxConstraints(),
        ),
        'RenderPadding': RenderPadding(padding: EdgeInsets.zero),
        'RenderPositionedBox': RenderPositionedBox(alignment: Alignment.center),
        'RenderDecoratedBox': RenderDecoratedBox(
          decoration: const BoxDecoration(),
        ),
      };

      for (final MapEntry(key: label, value: owner) in owners.entries) {
        final candidate = _ProbeRenderObject();

        expect(
          () => owner.adoptChild(candidate),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message.toString(),
              'message',
              contains('$label children must be RenderBox'),
            ),
          ),
        );
        expect(owner.child, isNull);
        expect(owner.children, isEmpty);
        expect(candidate.parent, isNull);
      }
    });

    test('constructors bypass hooks while later public calls stay virtual', () {
      _constructorHooks.clear();
      final proxyChild = _ProbeRenderBox();
      final paddingChild = _ProbeRenderBox();
      final proxy = _HookedProxy(proxyChild);
      final padding = _HookedPadding(paddingChild);

      expect(_constructorHooks, isEmpty);
      expect(proxy.child, same(proxyChild));
      expect(padding.child, same(paddingChild));

      final replacement = _ProbeRenderBox();
      proxy.child = replacement;
      padding.dropChild(paddingChild);
      padding.adoptChild(_ProbeRenderBox());

      expect(_constructorHooks, [
        'proxy.child=',
        'padding.dropChild',
        'padding.adoptChild',
      ]);
      expect(proxy.child, same(replacement));
      expect(proxyChild.parent, isNull);
    });

    test('valid paths bypass virtual set adopt and drop hooks', () {
      final owner = PipelineOwner();
      final parent = _SingleChildProbe()..attach(owner);
      final first = _ProbeRenderBox();

      setSingleRenderObjectChild(parent, first);
      expect(parent.child, same(first));
      expect(first.parent, same(parent));

      final second = _ProbeRenderBox();
      setSingleRenderObjectChild(parent, second);
      expect(parent.child, same(second));
      expect(first.parent, isNull);
      expect(second.parent, same(parent));

      setSingleRenderObjectChild(parent, second);
      setSingleRenderObjectChild(parent, null);
      expect(parent.child, isNull);
      expect(parent.children, isEmpty);
      expect(parent.overrideCalls, [0, 0, 0]);
    });

    test('public setChild delegates while nested edge hooks stay bypassed', () {
      final parent = _SingleChildProbe();
      final first = _ProbeRenderBox();
      parent.setChild(first);

      expect(parent.child, same(first));
      expect(first.parent, same(parent));
      expect(parent.overrideCalls, [1, 0, 0]);

      final second = _ProbeRenderBox();
      parent.setChild(second);
      expect(parent.child, same(second));
      expect(first.parent, isNull);
      expect(second.parent, same(parent));
      expect(parent.overrideCalls, [2, 0, 0]);
    });

    test(
      'single-child replacement rejects foreign next before dropping current',
      () {
        var updatesA = 0;
        var updatesB = 0;
        final ownerA = PipelineOwner(onNeedVisualUpdate: () => updatesA++);
        final ownerB = PipelineOwner(onNeedVisualUpdate: () => updatesB++);
        final parent = _SingleChildProbe()..attach(ownerA);
        final current = _ProbeRenderBox();
        setSingleRenderObjectChild(parent, current);
        final foreignParent = _SingleChildProbe()..attach(ownerB);
        final next = _ProbeRenderBox();
        foreignParent.adoptDirectly(next);
        parent.resetCounters();
        foreignParent.resetCounters();
        final ownerALayout = ownerA.debugNeedsLayout;
        final ownerAPaint = ownerA.debugNeedsPaint;
        final ownerBLayout = ownerB.debugNeedsLayout;
        final ownerBPaint = ownerB.debugNeedsPaint;
        final beforeUpdatesA = updatesA;
        final beforeUpdatesB = updatesB;

        expect(
          () => setSingleRenderObjectChild(parent, next),
          throwsStateError,
        );

        expect(parent.child, same(current));
        expect(parent.children, [same(current)]);
        expect(current.parent, same(parent));
        expect(current.pipelineOwner, same(ownerA));
        expect(next.parent, same(foreignParent));
        expect(next.pipelineOwner, same(ownerB));
        expect(parent.overrideCalls, [0, 0, 0]);
        expect(foreignParent.overrideCalls, [0, 0, 0]);
        expect(ownerA.debugNeedsLayout, ownerALayout);
        expect(ownerA.debugNeedsPaint, ownerAPaint);
        expect(ownerB.debugNeedsLayout, ownerBLayout);
        expect(ownerB.debugNeedsPaint, ownerBPaint);
        expect(updatesA, beforeUpdatesA);
        expect(updatesB, beforeUpdatesB);
      },
    );

    test(
      'single-child replacement rejects split next before typed or generic mutation',
      () {
        final ownerA = PipelineOwner();
        final ownerB = PipelineOwner();
        final parent = _SingleChildProbe()..attach(ownerA);
        final current = _ProbeRenderBox();
        setSingleRenderObjectChild(parent, current);
        final next = _ProbeRenderBox();
        final grandchild = _ProbeRenderBox();
        next.adoptChild(grandchild);
        grandchild.attach(ownerB);
        parent.resetCounters();

        expect(
          () => setSingleRenderObjectChild(parent, next),
          throwsStateError,
        );

        expect(parent.child, same(current));
        expect(parent.children, [same(current)]);
        expect(current.parent, same(parent));
        expect(next.parent, isNull);
        expect(next.pipelineOwner, isNull);
        expect(grandchild.parent, same(next));
        expect(grandchild.pipelineOwner, same(ownerB));
        expect(parent.overrideCalls, [0, 0, 0]);
      },
    );

    test(
      'single-child removal rejects inconsistent current edge atomically',
      () {
        final ownerA = PipelineOwner();
        final parent = _SingleChildProbe()..attach(ownerA);
        final current = _ProbeRenderBox();
        setSingleRenderObjectChild(parent, current);
        current.detach();
        parent.resetCounters();

        expect(
          () => setSingleRenderObjectChild(parent, null),
          throwsStateError,
        );

        expect(parent.children.single, same(current));
        expect(parent.children, [same(current)]);
        expect(current.parent, same(parent));
        expect(current.pipelineOwner, isNull);
        expect(parent.overrideCalls, [0, 0, 0]);
      },
    );

    test(
      'RenderProxyBox rejects a foreign replacement without tree mutation',
      () {
        var updatesA = 0;
        var updatesB = 0;
        final ownerA = PipelineOwner(onNeedVisualUpdate: () => updatesA++);
        final ownerB = PipelineOwner(onNeedVisualUpdate: () => updatesB++);
        final current = _ProbeRenderBox();
        final parent = RenderProxyBox(current)..attach(ownerA);
        final next = _ProbeRenderBox();
        final foreignParent = RenderProxyBox(next)..attach(ownerB);
        _flushClean(ownerA, parent);
        _flushClean(ownerB, foreignParent);
        updatesA = 0;
        updatesB = 0;

        expect(() => parent.child = next, throwsStateError);

        expect(parent.child, same(current));
        expect(parent.children, [same(current)]);
        expect(current.parent, same(parent));
        expect(current.pipelineOwner, same(ownerA));
        expect(next.parent, same(foreignParent));
        expect(next.pipelineOwner, same(ownerB));
        expect(foreignParent.child, same(next));
        expect(foreignParent.children, [same(next)]);
        expect(ownerA.debugNeedsLayout, isFalse);
        expect(ownerA.debugNeedsPaint, isFalse);
        expect(ownerB.debugNeedsLayout, isFalse);
        expect(ownerB.debugNeedsPaint, isFalse);
        expect(updatesA, 0);
        expect(updatesB, 0);
      },
    );

    test('RenderView rejects a foreign replacement without tree mutation', () {
      var updatesA = 0;
      var updatesB = 0;
      final ownerA = PipelineOwner(onNeedVisualUpdate: () => updatesA++);
      final ownerB = PipelineOwner(onNeedVisualUpdate: () => updatesB++);
      final current = _ProbeRenderBox();
      final parent = RenderView(width: 1, height: 1)
        ..setChild(current)
        ..attach(ownerA);
      final next = _ProbeRenderBox();
      final foreignParent = RenderView(width: 1, height: 1)
        ..setChild(next)
        ..attach(ownerB);
      _flushClean(ownerA, parent);
      _flushClean(ownerB, foreignParent);
      updatesA = 0;
      updatesB = 0;

      expect(() => parent.setChild(next), throwsStateError);

      expect(parent.child, same(current));
      expect(parent.children, [same(current)]);
      expect(current.parent, same(parent));
      expect(current.pipelineOwner, same(ownerA));
      expect(next.parent, same(foreignParent));
      expect(next.pipelineOwner, same(ownerB));
      expect(foreignParent.child, same(next));
      expect(foreignParent.children, [same(next)]);
      expect(ownerA.debugNeedsLayout, isFalse);
      expect(ownerA.debugNeedsPaint, isFalse);
      expect(ownerB.debugNeedsLayout, isFalse);
      expect(ownerB.debugNeedsPaint, isFalse);
      expect(updatesA, 0);
      expect(updatesB, 0);
    });

    test('RenderView identical set is a no-op after direct adoption', () {
      var updates = 0;
      final owner = PipelineOwner(onNeedVisualUpdate: () => updates++);
      final view = RenderView(width: 1, height: 1)..attach(owner);
      final child = _ProbeRenderBox();
      view.adoptChild(child);
      _flushClean(owner, view);
      updates = 0;

      view.setChild(child);

      expect(view.child, same(child));
      expect(view.children, [same(child)]);
      expect(child.parent, same(view));
      expect(child.pipelineOwner, same(owner));
      expect(owner.debugNeedsLayout, isFalse);
      expect(owner.debugNeedsPaint, isFalse);
      expect(updates, 0);
    });
  });
}

void _flushClean(PipelineOwner owner, RenderBox root) {
  owner.flushLayout(root, const BoxConstraints.tight(width: 1, height: 1));
  owner.flushPaint(root, (_) {});
}

class _SingleChildProbe extends RenderBox with RenderObjectWithSingleChild {
  int setCalls = 0;
  int adoptCalls = 0;
  int dropCalls = 0;

  List<int> get overrideCalls => [setCalls, adoptCalls, dropCalls];

  void resetCounters() {
    setCalls = 0;
    adoptCalls = 0;
    dropCalls = 0;
  }

  void adoptDirectly(RenderObject child) {
    super.adoptChild(child);
  }

  @override
  void setChild(RenderObject? child) {
    setCalls++;
    super.setChild(child);
  }

  @override
  void adoptChild(RenderObject child) {
    adoptCalls++;
    super.adoptChild(child);
  }

  @override
  void dropChild(RenderObject child) {
    dropCalls++;
    super.dropChild(child);
  }
}

class _ProbeRenderBox extends RenderBox {}

class _ThrowingDetachBox extends RenderBox {
  _ThrowingDetachBox(this.error);

  final StateError error;

  @override
  void detach() {
    super.detach();
    throw error;
  }
}

class _ProbeRenderObject extends RenderObject {
  @override
  void paint(PaintingContext context, Offset offset) {}

  @override
  void performLayout(Constraints constraints) {}
}

final List<String> _constructorHooks = <String>[];

class _HookedProxy extends RenderProxyBox {
  _HookedProxy(super.child);

  @override
  set child(RenderBox? value) {
    _constructorHooks.add('proxy.child=');
    super.child = value;
  }
}

class _HookedPadding extends RenderPadding {
  _HookedPadding(RenderBox child)
    : super(padding: EdgeInsets.zero, child: child);

  @override
  void adoptChild(RenderObject child) {
    _constructorHooks.add('padding.adoptChild');
    super.adoptChild(child);
  }

  @override
  void dropChild(RenderObject child) {
    _constructorHooks.add('padding.dropChild');
    super.dropChild(child);
  }
}
