import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:noir/src/rendering/proxy_box.dart';
import 'package:test/test.dart';

void main() {
  test('parent render objects clear child layout state through layout()', () {
    final owner = PipelineOwner();
    final child = _ProbeRenderBox();
    final root = RenderProxyBox(child)
      ..attach(owner)
      ..layout(const BoxConstraints.tight(width: 10, height: 4));

    expect(child.layoutCount, 1);
    expect(root.debugNeedsLayout, isFalse);
    expect(child.debugNeedsLayout, isFalse);
    owner.dispose();
  });
}

class _ProbeRenderBox extends RenderBox {
  int layoutCount = 0;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    layoutCount++;
    size = Size(
      constraints.maxWidth ?? constraints.minWidth,
      constraints.maxHeight ?? constraints.minHeight,
    );
  }
}
