import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';

/// This retained file must fail analysis with one internal-use warning at
/// every `seam:` marker. It is never part of positive consumer analysis.
void probeInternalSeams({
  required BuildContext context,
  required FocusNode focusNode,
  required BuildOwner buildOwner,
  required FocusManager focusManager,
  required RenderObject renderObject,
  required Widget widget,
  required WidgetInspectorService inspector,
  required Buffer buffer,
  required Renderer renderer,
  required TextBuffer textBuffer,
}) {
  final element = context.element; // seam:BuildContext.element
  context.owner; // seam:BuildContext.owner
  context
      .getElementForInheritedWidgetOfExactType<
        // seam:BuildContext.getElementForInheritedWidgetOfExactType
        _ConsumerInherited
      >();
  context.findRenderObject(); // seam:BuildContext.findRenderObject
  context
      .findAncestorRenderObjectOfType<
        // seam:BuildContext.findAncestorRenderObjectOfType
        RenderBox
      >();
  context.visitAncestorElements(
    // seam:BuildContext.visitAncestorElements
    (ancestor) => true,
  );
  context.visitChildElements(
    // seam:BuildContext.visitChildElements
    (child) {},
  );

  widget.createElement(); // seam:Widget.createElement
  focusNode.attach(context); // seam:FocusNode.attach
  focusNode.detach(); // seam:FocusNode.detach

  final pipeline = buildOwner.pipelineOwner; // seam:BuildOwner.pipelineOwner
  buildOwner.scheduleBuild(element); // seam:BuildOwner.scheduleBuild
  BuildOwner.test(pipelineOwner: pipeline); // seam:BuildOwner.test

  renderObject.pipelineOwner; // seam:RenderObject.pipelineOwner
  renderObject.attach(pipeline); // seam:RenderObject.attach

  inspector.rootElement; // seam:WidgetInspectorService.rootElement
  inspector.registerRoot(element); // seam:WidgetInspectorService.registerRoot
  inspector.unregisterRoot(
    // seam:WidgetInspectorService.unregisterRoot
    element,
  );
  focusManager.nodeForElement(element); // seam:FocusManager.nodeForElement

  buffer.invalidate(); // seam:Buffer.invalidate
  buffer.handle; // seam:Buffer.handle
  renderer.debugCurrentBuffer; // seam:Renderer.debugCurrentBuffer
  renderer.handle; // seam:Renderer.handle
  renderer.bindings; // seam:Renderer.bindings
  textBuffer.lineInfo; // seam:TextBuffer.lineInfo
  textBuffer.handle; // seam:TextBuffer.handle
}

final class _ConsumerInherited extends InheritedWidget {
  const _ConsumerInherited({required super.child});

  @override
  bool updateShouldNotify(covariant _ConsumerInherited oldWidget) => false;
}
