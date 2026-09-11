import '../core/input.dart';
import '../core/mouse_cursor.dart';
import '../render/geometry.dart';
import '../rendering/object.dart';

/// Routes mouse events through render-tree hit testing.
final class PointerRouter {
  /// Creates a pointer router backed by [inputManager].
  PointerRouter(InputManager inputManager)
    : _dispatcher = inputManager.dispatcher {
    _subscription = inputManager.dispatcher.onMouse(
      route,
      priority: InputPriority.focus,
    );
  }

  late final InputSubscription _subscription;

  /// Render-tree root used for pointer hit testing.
  RenderObject? root;

  final InputDispatcher _dispatcher;

  /// Resolves the current pointer shape against the latest layout.
  MouseCursor get mouseCursor {
    final position = _dispatcher.mousePosition;
    if (position != null) {
      final result = hitTest(position);
      if (result != null) {
        for (final entry in result.path) {
          final target = entry.target;
          if (target is MouseCursorTarget && target.mouseCursor != null) {
            return target.mouseCursor!;
          }
        }
      }
    }
    return MouseCursor.basic;
  }

  /// Dispose the input subscription owned by this router.
  void dispose() {
    _subscription.cancel();
  }

  /// Resolves the current render-tree hit path without dispatching an event.
  HitTestResult? hitTest(Offset position) {
    final hitRoot = root;
    if (hitRoot == null) {
      return null;
    }
    final result = HitTestResult();
    return hitRoot.hitTest(result, position) ? result : null;
  }

  /// Route [event] to the current render-tree hit-test path.
  void route(MouseEvent event) {
    if (event.isConsumed) {
      return;
    }
    final result = hitTest(Offset(event.x, event.y));
    if (result == null) {
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
