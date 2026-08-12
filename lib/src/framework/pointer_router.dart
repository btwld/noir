import '../core/input.dart';
import '../render/geometry.dart';
import '../rendering/object.dart';

/// Routes mouse events through render-tree hit testing.
final class PointerRouter {
  /// Creates a pointer router backed by [inputManager].
  PointerRouter(InputManager inputManager) {
    _subscription = inputManager.dispatcher.onMouse(
      route,
      priority: InputPriority.focus,
    );
  }

  late final InputSubscription _subscription;

  /// Render-tree root used for pointer hit testing.
  RenderObject? root;

  /// Dispose the input subscription owned by this router.
  void dispose() {
    _subscription.cancel();
  }

  /// Route [event] to the current render-tree hit-test path.
  void route(MouseEvent event) {
    if (event.isConsumed) {
      return;
    }
    final hitRoot = root;
    if (hitRoot == null) {
      return;
    }

    final result = HitTestResult();
    if (!hitRoot.hitTest(result, Offset(event.x, event.y))) {
      return;
    }

    for (final entry in result.path) {
      if (event.isConsumed) {
        return;
      }
      final localEvent = _localize(event, entry.localPosition);
      entry.target.handleEvent(localEvent, entry);
      if (localEvent.isConsumed) {
        event.consume();
        return;
      }
    }
  }

  MouseEvent _localize(MouseEvent event, Offset localPosition) => MouseEvent(
    type: event.type,
    button: event.button,
    x: event.x,
    y: event.y,
    modifiers: event.modifiers,
    scroll: event.scroll,
    localPosition: localPosition,
  );
}
