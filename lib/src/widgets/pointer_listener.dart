import 'package:meta/meta.dart';

import '../core/input.dart';
import '../core/mouse_cursor.dart';
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
    this.mouseCursor,
    this.onPointerDown,
    this.onPointerUp,
    this.onPointerMove,
    this.onPointerScroll,
  });

  /// Pointer shape over this region; null defers to an annotated ancestor.
  ///
  /// Requires mouse reporting and an OSC 22 supporting terminal. High-level
  /// mouse reporting includes movement by default. Unsupported terminals keep
  /// their own pointer. iTerm2 uses legacy shape names and restores its default
  /// pointer on exit; modern OSC 22 terminals restore the previous stack entry.
  /// The deepest annotated hit target wins; use
  /// [MouseCursor.basic] to override an ancestor with the standard arrow.
  /// This annotation also participates in hit testing without callbacks.
  final MouseCursor? mouseCursor;

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
        mouseCursor: mouseCursor,
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
    renderObject.mouseCursor = mouseCursor;
    renderObject.updateCallbacks(
      onPointerDown: onPointerDown,
      onPointerUp: onPointerUp,
      onPointerMove: onPointerMove,
      onPointerScroll: onPointerScroll,
    );
  }
}

/// Proxy render box that hit-tests while a handler or cursor annotation is set
/// and dispatches local-position mouse events.
class RenderPointerListener extends RenderProxyBox
    implements HitTestTarget, MouseCursorTarget {
  /// Stores optional handlers and child for local-position hit dispatch.
  RenderPointerListener({
    this.mouseCursor,
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

  /// Shape shared by every cell in this listener.
  MouseCursor? mouseCursor;

  @override
  MouseCursor? mouseCursorAt(Offset position) => mouseCursor;

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
      mouseCursor != null ||
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
