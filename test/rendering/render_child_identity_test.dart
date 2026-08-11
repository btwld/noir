// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes, invalid_use_of_protected_member

import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/flex.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:test/test.dart';

void main() {
  group('RenderObject child identity', () {
    test('children view stays identical and live across edge operations', () {
      final parent = _RenderParent();
      final first = _EqualRenderBox();
      final second = _EqualRenderBox();
      final third = _EqualRenderBox();
      final view = parent.children;

      void expectEdges(List<RenderObject> expected) {
        expect(parent.children, same(view));
        expect(view, hasLength(expected.length));
        for (var index = 0; index < expected.length; index++) {
          expect(view[index], same(expected[index]), reason: 'child $index');
        }
        for (final child in <RenderObject>[first, second, third]) {
          expect(
            child.parent,
            expected.any((candidate) => identical(candidate, child))
                ? same(parent)
                : isNull,
          );
        }
      }

      expectEdges(const <RenderObject>[]);
      parent.adoptChild(first);
      expectEdges(<RenderObject>[first]);
      parent.adoptChild(second);
      expectEdges(<RenderObject>[first, second]);
      parent.adoptChild(third);
      expectEdges(<RenderObject>[first, second, third]);
      parent.moveChild(first, after: third);
      expectEdges(<RenderObject>[second, third, first]);
      parent.dropChild(second);
      expectEdges(<RenderObject>[third, first]);
    });

    for (final mutation
        in <
          ({
            String name,
            void Function(
              List<RenderObject>,
              RenderObject,
              RenderObject,
              RenderObject,
            )
            apply,
          })
        >[
          (
            name: 'element replacement',
            apply: (view, first, second, outsider) => view[0] = outsider,
          ),
          (
            name: 'structural growth',
            apply: (view, first, second, outsider) => view.add(outsider),
          ),
          (
            name: 'reordering',
            apply: (view, first, second, outsider) {
              view.sort((left, right) => identical(left, first) ? 1 : -1);
            },
          ),
        ]) {
      test('children view rejects ${mutation.name}', () {
        final parent = _RenderParent();
        final first = _EqualRenderBox();
        final second = _EqualRenderBox();
        final outsider = _EqualRenderBox();
        parent
          ..adoptChild(first)
          ..adoptChild(second);
        final view = parent.children;

        expect(
          () => mutation.apply(view, first, second, outsider),
          throwsUnsupportedError,
        );

        expect(parent.children, same(view));
        expect(view, [same(first), same(second)]);
        expect(first.parent, same(parent));
        expect(second.parent, same(parent));
        expect(outsider.parent, isNull);
      });
    }

    test('dropChild removes the requested equal-valued identity', () {
      final parent = _RenderParent();
      final first = _EqualRenderBox();
      final second = _EqualRenderBox();
      parent
        ..adoptChild(first)
        ..adoptChild(second);

      expect(first, equals(second));
      expect(identical(first, second), isFalse);

      parent.dropChild(second);

      expect(parent.children, [same(first)]);
      expect(first.parent, same(parent));
      expect(second.parent, isNull);
    });

    test('moveChild reorders by identity without changing parent edges', () {
      final parent = _RenderParent();
      final first = _EqualRenderBox();
      final second = _EqualRenderBox();
      final third = _EqualRenderBox();
      parent
        ..adoptChild(first)
        ..adoptChild(second)
        ..adoptChild(third)
        ..moveChild(first, after: third)
        ..moveChild(third);

      expect(parent.children, [same(third), same(second), same(first)]);
      expect([
        first.parent,
        second.parent,
        third.parent,
      ], everyElement(same(parent)));
    });

    test('moveChild invalidates layout only when order changes', () {
      final owner = PipelineOwner();
      final parent = _RenderParent();
      final first = _EqualRenderBox();
      final second = _EqualRenderBox();
      parent
        ..adoptChild(first)
        ..adoptChild(second)
        ..attach(owner);
      owner.flushLayout(
        parent,
        const BoxConstraints.tight(width: 2, height: 1),
      );

      parent.moveChild(second, after: first);
      expect(parent.debugNeedsLayout, isFalse);

      parent.moveChild(second);
      expect(parent.children, [same(second), same(first)]);
      expect(parent.debugNeedsLayout, isTrue);
    });

    test('moveChild rejects invalid child and anchor before mutation', () {
      final parent = _RenderParent();
      final first = _EqualRenderBox();
      final second = _EqualRenderBox();
      final foreignParent = _RenderParent();
      final foreign = _EqualRenderBox();
      parent
        ..adoptChild(first)
        ..adoptChild(second);
      foreignParent.adoptChild(foreign);
      final before = List<RenderBox>.from(parent.children.cast<RenderBox>());

      expect(() => parent.moveChild(foreign), throwsStateError);
      expect(() => parent.moveChild(second, after: foreign), throwsStateError);

      expect(parent.children, [same(before[0]), same(before[1])]);
      expect(first.parent, same(parent));
      expect(second.parent, same(parent));
      expect(foreign.parent, same(foreignParent));
    });

    test('equal-valued parents cannot claim a foreign child as retained', () {
      final firstParent = _EqualRenderFlex();
      final secondParent = _EqualRenderFlex();
      final child = _EqualRenderBox();
      firstParent.add(child);

      expect(firstParent, equals(secondParent));
      expect(identical(firstParent, secondParent), isFalse);

      expect(() => secondParent.add(child), throwsStateError);

      expect(child.parent, same(firstParent));
      expect(firstParent.children, [same(child)]);
      expect(secondParent.children, isEmpty);
    });
  });
}

class _RenderParent extends RenderBox {}

class _EqualRenderBox extends RenderBox {
  @override
  bool operator ==(Object other) => other is _EqualRenderBox;

  @override
  int get hashCode => 0;
}

class _EqualRenderFlex extends RenderFlex {
  _EqualRenderFlex() : super(direction: Axis.horizontal);

  @override
  bool operator ==(Object other) => other is _EqualRenderFlex;

  @override
  int get hashCode => 0;
}
