import 'package:noir/noir.dart' show BoxConstraints, BuildContext, Size;
import 'package:noir/noir_low_level.dart'
    show BuildOwner, RenderBox, RenderObject, RenderObjectWidget;
import 'package:noir/src/framework/element.dart' show Element;
import 'package:test/test.dart';

void main() {
  test('RenderObjectElement exposes its render object for layout', () {
    final owner = BuildOwner();
    final widget = _ProbeWidget();
    final element = widget.createElement();

    element.mount(null, owner);

    final renderElement = Element.findRenderObjectElement(element)!;
    final renderObject = renderElement.renderObject! as _ProbeRenderBox;
    renderObject.layout(const BoxConstraints(maxWidth: 10, maxHeight: 10));

    expect(renderObject.laidOut, isTrue);
    expect(renderObject.size.width, equals(10));
    expect(renderObject.size.height, equals(10));
  });
}

class _ProbeWidget extends RenderObjectWidget {
  const _ProbeWidget();

  @override
  RenderObject createRenderObject(BuildContext context) => _ProbeRenderBox();
}

class _ProbeRenderBox extends RenderBox {
  bool laidOut = false;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    laidOut = true;
    size = Size(
      constraints.maxWidth ?? constraints.minWidth,
      constraints.maxHeight ?? constraints.minHeight,
    );
  }
}
