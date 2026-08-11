import 'package:meta/meta.dart';

import '../core/input.dart';
import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/box.dart';
import '../rendering/object.dart';
import '../rendering/proxy_box.dart';

/// Invokes mouse callbacks for events hit-tested within [child]'s bounds.
class PointerListener extends SingleChildRenderObjectWidget {
  /// Configures callbacks for hit-tested mouse events over [child].
  const PointerListener({
    super.key,
    super.child,
    this.onPointerDown,
    this.onPointerUp,
    this.onPointerMove,
    this.onPointerScroll,
  });

  /// Called for a hit-tested mouse-button press.
  final MouseEventHandler? onPointerDown;

  /// Called for a hit-tested mouse-button release.
  final MouseEventHandler? onPointerUp;

  /// Called for hit-tested mouse movement.
  final MouseEventHandler? onPointerMove;

  /// Called for a hit-tested mouse-wheel event.
  final MouseEventHandler? onPointerScroll;

  @override
  @internal
  RenderPointerListener createRenderObject(BuildContext context) =>
      RenderPointerListener(
        onPointerDown: onPointerDown,
        onPointerUp: onPointerUp,
        onPointerMove: onPointerMove,
        onPointerScroll: onPointerScroll,
      );

  @override
  @internal
  void updateRenderObject(
    BuildContext context,
    RenderPointerListener renderObject,
  ) {
    renderObject.updateCallbacks(
      onPointerDown: onPointerDown,
      onPointerUp: onPointerUp,
      onPointerMove: onPointerMove,
      onPointerScroll: onPointerScroll,
    );
  }
}

/// Proxy render box that hit-tests itself only while a handler is set and
/// dispatches local-position mouse events.
class RenderPointerListener extends RenderProxyBox implements HitTestTarget {
  /// Stores optional handlers and child for local-position hit dispatch.
  RenderPointerListener({
    MouseEventHandler? onPointerDown,
    MouseEventHandler? onPointerUp,
    MouseEventHandler? onPointerMove,
    MouseEventHandler? onPointerScroll,
    RenderBox? child,
  }) : _onPointerDown = onPointerDown,
       _onPointerUp = onPointerUp,
       _onPointerMove = onPointerMove,
       _onPointerScroll = onPointerScroll,
       super(child);

  MouseEventHandler? _onPointerDown;
  MouseEventHandler? _onPointerUp;
  MouseEventHandler? _onPointerMove;
  MouseEventHandler? _onPointerScroll;

  /// Replace the callbacks invoked by this listener.
  void updateCallbacks({
    MouseEventHandler? onPointerDown,
    MouseEventHandler? onPointerUp,
    MouseEventHandler? onPointerMove,
    MouseEventHandler? onPointerScroll,
  }) {
    _onPointerDown = onPointerDown;
    _onPointerUp = onPointerUp;
    _onPointerMove = onPointerMove;
    _onPointerScroll = onPointerScroll;
  }

  @override
  bool hitTestSelf(Offset position) =>
      _onPointerDown != null ||
      _onPointerUp != null ||
      _onPointerMove != null ||
      _onPointerScroll != null;

  @override
  void handleEvent(MouseEvent event, HitTestEntry entry) {
    switch (event.type) {
      case MouseEventType.down:
        _onPointerDown?.call(event);
      case MouseEventType.up:
        _onPointerUp?.call(event);
      case MouseEventType.move:
        _onPointerMove?.call(event);
      case MouseEventType.scroll:
        _onPointerScroll?.call(event);
    }
  }
}
