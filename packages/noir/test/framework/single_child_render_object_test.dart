import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart' show RenderObjectElement;
import 'package:test/test.dart';

void main() {
  test('SingleChildRenderObjectElement wires render object child', () {
    final owner = BuildOwner();
    final element =
        PointerListener(child: Container(width: 1, height: 1)).createElement()
            as RenderObjectElement;

    element.mount(null, owner);
    owner.buildScope();

    final renderObject = element.renderObject;
    if (renderObject is! RenderProxyBox) {
      fail('Expected RenderProxyBox, got $renderObject');
    }
    expect(renderObject.child, isNotNull);

    element.update(const PointerListener());
    owner.buildScope();

    expect(renderObject.child, isNull);

    element.unmount();
  });
}
