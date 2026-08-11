import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';

/// A supported single-child custom render widget. The framework-owned
/// createElement adapter is deliberately inherited.
final class ConsumerProxyWidget extends SingleChildRenderObjectWidget {
  const ConsumerProxyWidget({super.child, super.key, this.background});

  final Color? background;

  @override
  ConsumerProxyBox createRenderObject(BuildContext context) =>
      ConsumerProxyBox(background: background);

  @override
  void updateRenderObject(BuildContext context, ConsumerProxyBox renderObject) {
    renderObject.background = background;
  }
}

final class ConsumerProxyBox extends RenderProxyBox {
  ConsumerProxyBox({Color? background}) : _background = background;

  Color? _background;

  set background(Color? value) {
    if (_background == value) return;
    _background = value;
    markNeedsPaint();
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    super.performBoxLayout(constraints);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final background = _background;
    if (background != null) {
      context.canvas.fillRect(offset & size, background);
    }
    final child = this.child;
    if (child != null) {
      context.paintChild(child, offset + Offset(child.x, child.y));
    }
  }
}

/// Type-checks advanced binding injection and Buffer's high-level companion
/// option type without executing native code.
TuiBinding createConsumerBinding(Renderer renderer, InputManager inputManager) {
  final TerminalCapabilities capabilities = CapabilitiesDetection(
    renderer,
  ).detectCapabilities();
  capabilities.toString();
  renderer.nextBuffer.drawBox(
    0,
    0,
    8,
    3,
    const BoxOptions(title: 'Noir', titleAlignment: TextAlign.center),
    Color.white,
    Color.black,
  );
  return TuiBinding(
    width: 20,
    height: 5,
    headless: true,
    inputManager: inputManager,
    renderer: renderer,
  );
}
