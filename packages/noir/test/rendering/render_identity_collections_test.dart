// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/flex.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:noir/src/widgets/flexible.dart';
import 'package:test/test.dart';

void main() {
  group('render-tree identity collections', () {
    test('detaching one equal node preserves the other node pending work', () {
      final owner = PipelineOwner();
      final first = _EqualRenderBox()..attach(owner);
      final second = _EqualRenderBox()..attach(owner);

      expect(first, equals(second));
      expect(identical(first, second), isFalse);

      first.detach();

      expect(first.pipelineOwner, isNull);
      expect(second.pipelineOwner, same(owner));
      expect(second.debugNeedsLayout, isTrue);
      expect(second.debugNeedsPaint, isTrue);
      expect(owner.debugNeedsLayout, isTrue);
      expect(owner.debugNeedsPaint, isTrue);

      owner.flushLayout(
        second,
        const BoxConstraints.tight(width: 1, height: 1),
      );
      expect(second.layoutCount, 1);
    });

    test('equal Flex children retain independent metadata', () {
      final first = _EqualRenderBox();
      final second = _EqualRenderBox();
      RenderFlex(direction: Axis.horizontal)
        ..add(first, flex: 1, fit: FlexFit.tight)
        ..add(second, flex: 2, fit: FlexFit.tight)
        ..layout(const BoxConstraints.tight(width: 6, height: 1));

      expect(first.size.width, 2);
      expect(second.size.width, 4);
      expect(first.x, 0);
      expect(second.x, 2);
    });
  });
}

final class _EqualRenderBox extends RenderBox {
  int layoutCount = 0;

  @override
  bool operator ==(Object other) => other is _EqualRenderBox;

  @override
  int get hashCode => 0;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    layoutCount++;
    super.performBoxLayout(constraints);
  }
}
