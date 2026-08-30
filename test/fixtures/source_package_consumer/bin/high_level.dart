import 'package:noir/noir.dart';

void main() {
  _buildConsumerTree();
}

Widget _buildConsumerTree() => ScrollBox(
  scrollDirection: Axis.horizontal,
  child: Container(
    decoration: BoxDecoration(
      border: Border(
        sides: const BorderSides(left: false),
        title: 'consumer',
        titleAlignment: TextAlign.center,
      ),
    ),
    padding: const EdgeInsets.all(1),
    child: const Row(
      spacing: 1,
      children: [
        Expanded(child: Text('Noir')),
        SizedBox(width: 1),
        Text('source consumer'),
      ],
    ),
  ),
);

/// Proves that the app entrypoint returns the narrowed lifecycle facade and
/// that registrations are cancellable without exposing InputManager.
TuiApp launchConsumerApp(Widget root) {
  final TuiApp app = runTuiApp(root, headless: true);
  final VoidCallback cancelKey = app.onKey((event) {});
  final VoidCallback cancelMouse = app.onMouse((event) {});
  final VoidCallback cancelPaste = app.onPaste((event) {});
  cancelKey();
  cancelMouse();
  cancelPaste();
  app
    ..enableMouse(enableMovement: true)
    ..disableMouse()
    ..enableKittyKeyboard()
    ..disableKittyKeyboard();
  final bool isHeadless = app.isHeadless;
  if (!isHeadless) {
    app.dispose();
  }
  return app;
}

/// Proves the supported high-level decoration/canvas vocabulary.
final class ConsumerDecoration extends Decoration {
  const ConsumerDecoration();

  @override
  void paint(TuiCanvas canvas, Rect rect) {
    canvas
      ..save()
      ..clipRect(rect)
      ..fillRect(rect, Color.black)
      ..drawText('Noir', Offset(rect.left, rect.top), Color.white)
      ..drawBox(
        rect,
        BoxOptions(
          sides: BorderSides(bottom: false),
          titleAlignment: TextAlign.right,
        ),
        Color.cyan,
        Color.transparent,
      )
      ..setCell(
        Offset(rect.left, rect.top),
        'N',
        Color.white,
        Color.black,
        Attr.bold,
      )
      ..restore();
  }
}

final ActionCallback<ActivateIntent> consumerAction = (intent, context) =>
    KeyEventResult.handled;

Widget consumerOverlayAndMenu() {
  final portal = OverlayPortalController(debugLabel: 'consumer');
  final modal = ModalController();
  final menu = MenuController();
  const WidgetBuilder overlayBuilder = _overlayChild;
  return Column(
    children: [
      OverlayPortal(
        controller: portal,
        overlayChildBuilder: overlayBuilder,
        child: const Text('portal-child'),
      ),
      Modal(
        controller: modal,
        modalBuilder: (context) =>
            const Panel(title: 'Modal', child: Text('modal-child')),
        child: Text(modal.isOpen ? 'open-modal' : 'closed-modal'),
      ),
      MenuAnchor(
        controller: menu,
        alignmentOffset: Offset.zero,
        reservedPadding: EdgeInsets.zero,
        onOpen: () {},
        onClose: () {},
        menuChildren: const [Text('item')],
        builder:
            (BuildContext context, MenuController controller, Widget? child) =>
                Text(controller.isOpen ? 'open' : 'closed'),
        child: const Text('launcher'),
      ),
    ],
  );
}

Widget consumerAutocomplete() {
  final controller = TextEditingController();
  return Autocomplete<String>(
    controller: controller,
    options: const ['alpha', 'beta'],
    status: AutocompleteStatus.ready,
    optionBuilder: (context, option, highlighted) => Text(option),
    onChanged: (value) {},
    onSelected: (option) {},
    onDismiss: () {},
  );
}

Widget consumerTreeView() {
  final controller = TreeViewController<String>(
    roots: [
      TreeNode<String>.branch(
        id: 'root',
        value: 'Root',
        children: [TreeNode<String>.leaf(id: 'child', value: 'Child')],
      ),
    ],
  );
  return TreeView<String>(
    controller: controller,
    itemBuilder: (context, node, selected) => Text(node.value),
    onSelectionChanged: (node) {},
    onActivate: (node) {},
  );
}

Widget _overlayChild(BuildContext context) => const Text('overlay');
