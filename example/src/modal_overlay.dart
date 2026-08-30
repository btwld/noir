import 'package:noir/noir.dart';

/// Example-local modal composition built only from Noir's public widgets.
///
/// The overlay deliberately leaves the base frame undimmed. A transparent,
/// full-terminal pointer target sits behind [dialog] so the base application
/// cannot receive pointer input while the modal is visible.
class DemoModalOverlay extends StatelessWidget {
  const DemoModalOverlay({
    required this.controller,
    required this.onDismiss,
    required this.dialog,
    required this.child,
    this.traversalPolicy,
    super.key,
  });

  final OverlayPortalController controller;
  final VoidCallback onDismiss;
  final FocusTraversalPolicy? traversalPolicy;
  final Widget dialog;
  final Widget child;

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: controller,
    child: child,
    overlayChildBuilder: (context) => Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>((intent, context) {
            onDismiss();
            return KeyEventResult.handled;
          }),
        },
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              bottom: 0,
              child: PointerListener(
                onPointerDown: _consumePointer,
                onPointerUp: _consumePointer,
                onPointerMove: _consumePointer,
                onPointerScroll: _consumePointer,
                child: const Align(child: SizedBox.shrink()),
              ),
            ),
            Align(
              child: FocusScope(
                traversalPolicy: traversalPolicy,
                child: dialog,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _consumePointer(MouseEvent event) => event.consume();

/// Cycles focus through a caller-owned set of modal controls.
///
/// Detached or disabled nodes are skipped. Returning true for a single live
/// node intentionally consumes Tab so focus cannot escape the modal.
final class DemoClosedLoopTraversalPolicy extends FocusTraversalPolicy {
  DemoClosedLoopTraversalPolicy(Iterable<FocusNode> nodes)
    : _nodes = List<FocusNode>.unmodifiable(nodes);

  final List<FocusNode> _nodes;

  List<FocusNode> get _available => [
    for (final node in _nodes)
      if (node.isAttached && node.canRequestFocus) node,
  ];

  @override
  FocusNode? findFirstFocus(FocusScopeNode scope) {
    final available = _available;
    return available.isEmpty ? null : available.first;
  }

  @override
  FocusNode? findLastFocus(FocusScopeNode scope) {
    final available = _available;
    return available.isEmpty ? null : available.last;
  }

  @override
  bool next(FocusNode currentNode) => _move(currentNode, 1);

  @override
  bool previous(FocusNode currentNode) => _move(currentNode, -1);

  bool _move(FocusNode currentNode, int delta) {
    final available = _available;
    if (available.isEmpty) return false;
    final current = available.indexWhere(
      (candidate) => identical(candidate, currentNode),
    );
    final int next;
    if (current < 0) {
      next = delta > 0 ? 0 : available.length - 1;
    } else {
      next = (current + delta) % available.length;
    }
    available[next].requestFocus();
    return true;
  }
}
