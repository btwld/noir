import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:noir/src/rendering/proxy_box.dart';
import 'package:test/test.dart';

void main() {
  group('acyclic render edges', () {
    test('generic adoption rejects self without changing edges', () {
      final box = _Box();

      expect(() => box.adoptChild(box), throwsStateError);

      expect(box.parent, isNull);
      expect(box.children, isEmpty);
    });

    test('generic adoption rejects an ancestor without changing edges', () {
      final ancestor = _Box();
      final descendant = _Box();
      ancestor.adoptChild(descendant);

      expect(() => descendant.adoptChild(ancestor), throwsStateError);

      expect(ancestor.parent, isNull);
      expect(ancestor.children, [same(descendant)]);
      expect(descendant.parent, same(ancestor));
      expect(descendant.children, isEmpty);
    });

    for (final attached in [false, true]) {
      test(
        'self replacement preserves the current child (attached: $attached)',
        () {
          final previous = _Box();
          final box = RenderProxyBox(previous);
          final owner = attached ? PipelineOwner() : null;
          if (owner != null) box.attach(owner);

          expect(() => box.child = box, throwsStateError);

          expect(box.parent, isNull);
          expect(box.child, same(previous));
          expect(previous.parent, same(box));
          expect(previous.pipelineOwner, same(owner));
          box.detach();
        },
      );

      test(
        'ancestor replacement preserves the current child (attached: $attached)',
        () {
          final previous = _Box();
          final descendant = RenderProxyBox(previous);
          final ancestor = RenderProxyBox(descendant);
          final owner = attached ? PipelineOwner() : null;
          if (owner != null) ancestor.attach(owner);

          expect(() => descendant.child = ancestor, throwsStateError);

          expect(ancestor.parent, isNull);
          expect(ancestor.child, same(descendant));
          expect(descendant.child, same(previous));
          expect(previous.parent, same(descendant));
          expect(previous.pipelineOwner, same(owner));
          ancestor.detach();
        },
      );
    }
  });

  test(
    'detach attempts all siblings and descendants, retaining the first error',
    () {
      final log = <String>[];
      final firstError = StateError('first cleanup');
      final secondError = StateError('second cleanup');
      final first = _DetachBox('first', log, error: firstError);
      final second = _DetachBox('second', log, error: secondError);
      final grandchild = _DetachBox('grandchild', log);
      final last = _DetachBox('last', log)..adoptChild(grandchild);
      final owner = PipelineOwner();
      final root = _Box()
        ..adoptChild(first)
        ..adoptChild(second)
        ..adoptChild(last)
        ..attach(owner);

      expect(root.detach, throwsA(same(firstError)));

      expect(log, ['first', 'second', 'grandchild', 'last']);
      for (final node in [root, first, second, last, grandchild]) {
        expect(node.pipelineOwner, isNull);
      }
      expect(owner.debugNeedsLayout, isFalse);
      expect(owner.debugNeedsPaint, isFalse);
      expect(root.detach, returnsNormally);
      expect(log, ['first', 'second', 'grandchild', 'last']);
    },
  );

  for (final schedulingFails in [false, true]) {
    test(
      'committed drop invalidates after cleanup failure (scheduling fails: $schedulingFails)',
      () {
        var failScheduling = false;
        var updates = 0;
        final cleanupError = StateError('cleanup');
        final schedulingError = StateError('scheduling');
        final owner = PipelineOwner(
          onNeedVisualUpdate: () {
            updates++;
            if (failScheduling) throw schedulingError;
          },
        );
        final child = _DetachBox('child', [], error: cleanupError);
        final root = _Box()
          ..adoptChild(child)
          ..attach(owner);
        owner.flushLayout(
          root,
          const BoxConstraints.tight(width: 1, height: 1),
        );
        owner.flushPaint(root, (_) {});
        updates = 0;
        failScheduling = schedulingFails;

        expect(() => root.dropChild(child), throwsA(same(cleanupError)));

        expect(root.children, isEmpty);
        expect(child.parent, isNull);
        expect(child.pipelineOwner, isNull);
        expect(updates, 1);
        expect(owner.debugNeedsLayout, isTrue);
        expect(owner.debugNeedsPaint, isTrue);
        failScheduling = false;
        root.detach();
      },
    );
  }
}

class _DetachBox extends RenderBox {
  _DetachBox(this.label, this.log, {this.error});

  final String label;
  final List<String> log;
  final StateError? error;

  @override
  void detach() {
    super.detach();
    log.add(label);
    final failure = error;
    if (failure != null) throw failure;
  }
}

class _Box extends RenderBox {}
