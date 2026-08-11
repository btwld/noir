import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/constrained_box.dart';
import 'package:test/test.dart';

void main() {
  test('RenderBox rejects malformed generic constraints before layout', () {
    final box = _ProbeBox();

    expect(
      () => box.layout(_NegativeMaxConstraints()),
      throwsA(isA<ArgumentError>()),
    );
    expect(box.layoutCalls, 0);
  });

  test('RenderBox rejects malformed typed constraints before layout', () {
    final box = _ProbeBox();

    expect(
      () => box.layout(_InvertedBoxConstraints()),
      throwsA(isA<ArgumentError>()),
    );
    expect(box.layoutCalls, 0);
  });

  test('negative layout output is rejected before size state mutates', () {
    final box = _BadSizeBox()
      ..layout(const BoxConstraints.tight(width: 4, height: 2));
    expect(box.size, const Size(4, 2));
    expect(box.width, 4);
    expect(box.height, 2);

    box.emitBadSize = true;
    expect(
      () => box.layout(const BoxConstraints.tight(width: 5, height: 3)),
      throwsA(isA<StateError>()),
    );
    expect(box.size, const Size(4, 2));
    expect(box.width, 4);
    expect(box.height, 2);
  });

  test('zero and unbounded constraints produce non-negative sizes', () {
    final unbounded = _ProbeBox()..layout(const BoxConstraints());
    expect(unbounded.size, Size.zero);

    final zero = _ProbeBox()
      ..layout(const BoxConstraints.tight(width: 0, height: 0));
    expect(zero.size, Size.zero);

    final looseZero = _ProbeBox()
      ..layout(const BoxConstraints.loose(maxWidth: 0, maxHeight: 0));
    expect(looseZero.size, Size.zero);

    final positive = _ProbeBox()
      ..layout(const BoxConstraints.tight(width: 3, height: 2));
    expect(positive.size, const Size(3, 2));
  });

  test('valid child layout enters through layout', () {
    final child = _ProbeBox();
    final parent = RenderConstrainedBox(
      additionalConstraints: const BoxConstraints(),
      child: child,
    )..layout(const BoxConstraints.tight(width: 3, height: 2));

    expect(child.layoutCalls, 1);
    expect(child.size, const Size(3, 2));
    expect(parent.size, const Size(3, 2));
  });
}

final class _NegativeMaxConstraints extends Constraints {
  _NegativeMaxConstraints() : super(maxWidth: 1);

  @override
  int? get maxWidth => -1;
}

final class _InvertedBoxConstraints extends BoxConstraints {
  _InvertedBoxConstraints() : super(minWidth: 1, maxWidth: 2);

  @override
  int get minWidth => 3;
}

final class _BadSize extends Size {
  const _BadSize() : super(1, 1);

  @override
  int get width => -1;
}

class _ProbeBox extends RenderBox {
  int layoutCalls = 0;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    layoutCalls++;
    size = Size(
      constraints.maxWidth ?? constraints.minWidth,
      constraints.maxHeight ?? constraints.minHeight,
    );
  }
}

final class _BadSizeBox extends RenderBox {
  bool emitBadSize = false;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = emitBadSize
        ? const _BadSize()
        : Size(
            constraints.maxWidth ?? constraints.minWidth,
            constraints.maxHeight ?? constraints.minHeight,
          );
  }
}
