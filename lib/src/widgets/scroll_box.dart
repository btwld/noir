// ignore_for_file: avoid_setters_without_getters
import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../core/color.dart';
import '../core/input.dart';
import '../foundation/change_notifier.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/object.dart';
import '../rendering/proxy_box.dart';
import 'actions.dart';
import 'focus.dart';
import 'focus_node_owner_mixin.dart';
import 'intents.dart';
import 'pointer_listener.dart';
import 'shortcuts.dart';
import 'theme.dart';

/// Observable scroll state shared between [ScrollBox] and its consumers.
///
/// Holds the current scroll offset (in lines) and the max scroll extent
/// computed by the viewport. Listeners are notified on every change.
///
/// The [initialOffset] passed to the constructor is held verbatim until the
/// hosting [ScrollBox]'s render object computes a real
/// [maxScrollExtent] during layout — at that point it is clamped. This
/// matches the natural expectation that a controller created before its
/// box's layout still remembers the requested scroll position.
class ScrollController extends ChangeNotifier {
  /// Preserves [initialOffset] until layout publishes extents and clamps it.
  ScrollController({double initialOffset = 0}) : _offset = initialOffset;

  double _offset;
  double _maxScrollExtent = 0;
  int _viewportExtent = 0;
  bool _layoutStateChanged = false;

  /// Current scroll offset in lines (or cells for horizontal scroll).
  double get offset => _offset;

  /// Maximum reachable scroll offset, updated by the render object after layout.
  double get maxScrollExtent => _maxScrollExtent;

  /// Visible size of the viewport in lines (vertical) or cells (horizontal).
  int get viewportExtent => _viewportExtent;

  /// Jump immediately to [target], clamped to `[0, maxScrollExtent]`.
  void jumpTo(double target) {
    final clamped = target.clamp(0.0, _maxScrollExtent);
    if (clamped == _offset) return;
    _offset = clamped;
    notifyListeners();
  }

  /// Page up by [viewportExtent], clamped. No-op if extent is unknown (0).
  void pageUp() {
    if (_viewportExtent <= 0) return;
    jumpTo(_offset - _viewportExtent);
  }

  /// Page down by [viewportExtent], clamped.
  void pageDown() {
    if (_viewportExtent <= 0) return;
    jumpTo(_offset + _viewportExtent);
  }

  /// Update the viewport extent (called by the render object during layout).
  /// Does not directly notify — listeners are notified through
  /// [updateMaxScrollExtent], which is always called immediately after.
  void _updateViewportExtent(int extent) {
    requireNonNegativeExtent(extent, 'extent');
    if (_viewportExtent == extent) return;
    _viewportExtent = extent;
    _layoutStateChanged = true;
  }

  /// Update the max scroll extent. Called by the viewport during layout.
  /// Notifies listeners when either the extent changes or the offset is forced
  /// to clamp because the new extent shrank below it.
  void updateMaxScrollExtent(double max) {
    if (!max.isFinite || max < 0) {
      throw ArgumentError.value(max, 'max', 'must be finite and non-negative');
    }
    final oldOffset = _offset;
    final maxChanged = max != _maxScrollExtent;
    if (!maxChanged && !_layoutStateChanged) {
      final clamped = _offset.clamp(0.0, _maxScrollExtent);
      if (clamped != _offset) {
        _offset = clamped;
        notifyListeners();
      }
      return;
    }
    _maxScrollExtent = max;
    final clamped = _offset.clamp(0.0, _maxScrollExtent);
    if (clamped != _offset) {
      _offset = clamped;
    }
    final shouldNotify =
        maxChanged || _layoutStateChanged || oldOffset != _offset;
    _layoutStateChanged = false;
    if (shouldNotify) {
      notifyListeners();
    }
  }
}

/// A scrollable container, parity with OpenTUI-React `<scrollbox>`.
///
/// Composition: [Focus] -> [PointerListener] (for mouse wheel) -> custom
/// [_ScrollBoxRenderObjectWidget] which clips and offsets its child along
/// [scrollDirection] and optionally paints a 1-cell-wide scrollbar gutter.
///
/// Input bindings when focused:
/// - ArrowUp/Down (or Left/Right for horizontal) move by 1 line
/// - PageUp/Down move by the laid-out viewport extent (rows for vertical,
///   cells for horizontal) — read from the [ScrollController].
/// - Home/End jump to bounds
/// Mouse wheel input follows [scrollDirection]. Holding Shift rotates vertical
/// wheel directions to horizontal and horizontal directions to vertical.
class ScrollBox extends StatefulWidget {
  /// Configures a one-axis clipped viewport with optional caller-owned controls.
  const ScrollBox({
    required this.child,
    super.key,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.showScrollbar = true,
    this.scrollbarColor,
    this.trackColor,
    this.focusNode,
    this.autofocus = false,
    this.onScroll,
  });

  /// Controller that tracks and drives the scroll position. One is created internally when null.
  final ScrollController? controller;

  /// Axis along which the content scrolls.
  final Axis scrollDirection;

  /// Whether to paint the 1-cell-wide scrollbar gutter on the trailing edge.
  final bool showScrollbar;

  /// Color of the scrollbar thumb. Falls back to [ThemeData.scrollbarThumb].
  final Color? scrollbarColor;

  /// Color of the scrollbar track (gutter background). Falls back to
  /// [ThemeData.scrollbarTrack].
  final Color? trackColor;

  /// Focus node controlling keyboard scroll. One is created if null.
  final FocusNode? focusNode;

  /// Whether this widget requests focus when first mounted.
  final bool autofocus;

  /// Called after the scroll offset changes.
  final void Function(double offset)? onScroll;

  /// Content widget that may overflow the viewport and become scrollable.
  final Widget child;

  @override
  State<ScrollBox> createState() => _ScrollBoxState();
}

class _ScrollBoxState extends State<ScrollBox>
    with FocusNodeOwnerStateMixin<ScrollBox> {
  late ScrollController _controller;
  late bool _ownsController;

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ScrollController();
    _ownsController = widget.controller == null;
    _controller.addListener(_handleScrollChange);
  }

  @override
  void didUpdateWidget(ScrollBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
    if (oldWidget.controller != widget.controller) {
      final next = widget.controller ?? ScrollController();
      final nextOwned = widget.controller == null;
      next.addListener(_handleScrollChange);
      _controller.removeListener(_handleScrollChange);
      if (_ownsController) _controller.dispose();
      _controller = next;
      _ownsController = nextOwned;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleScrollChange);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _handleScrollChange() {
    if (!mounted) return;
    setState(() {});
    widget.onScroll?.call(_controller.offset);
  }

  void _scrollBy(double delta) {
    _controller.jumpTo(_controller.offset + delta);
  }

  void _handlePointerScroll(MouseEvent event) {
    if (event.type != MouseEventType.scroll) return;
    final scroll = event.scroll!;
    final direction = event.modifiers & KeyModifiers.shift != 0
        ? switch (scroll.direction) {
            MouseScrollDirection.up => MouseScrollDirection.left,
            MouseScrollDirection.down => MouseScrollDirection.right,
            MouseScrollDirection.left => MouseScrollDirection.up,
            MouseScrollDirection.right => MouseScrollDirection.down,
          }
        : scroll.direction;
    final matchesAxis = switch (direction) {
      MouseScrollDirection.up ||
      MouseScrollDirection.down => widget.scrollDirection == Axis.vertical,
      MouseScrollDirection.left ||
      MouseScrollDirection.right => widget.scrollDirection == Axis.horizontal,
    };
    if (!matchesAxis) return;

    final sign = switch (direction) {
      MouseScrollDirection.up || MouseScrollDirection.left => -1,
      MouseScrollDirection.down || MouseScrollDirection.right => 1,
    };
    final before = _controller.offset;
    _scrollBy((sign * scroll.magnitude).toDouble());
    if (_controller.offset != before) {
      event.consume();
    }
  }

  Map<Type, Action<Intent>> get _actions => {
    ScrollUpIntent: CallbackAction<ScrollUpIntent>((intent, context) {
      if (widget.scrollDirection != Axis.vertical) {
        return KeyEventResult.ignored;
      }
      _scrollBy(-1);
      return KeyEventResult.handled;
    }),
    ScrollDownIntent: CallbackAction<ScrollDownIntent>((intent, context) {
      if (widget.scrollDirection != Axis.vertical) {
        return KeyEventResult.ignored;
      }
      _scrollBy(1);
      return KeyEventResult.handled;
    }),
    ScrollLeftIntent: CallbackAction<ScrollLeftIntent>((intent, context) {
      if (widget.scrollDirection != Axis.horizontal) {
        return KeyEventResult.ignored;
      }
      _scrollBy(-1);
      return KeyEventResult.handled;
    }),
    ScrollRightIntent: CallbackAction<ScrollRightIntent>((intent, context) {
      if (widget.scrollDirection != Axis.horizontal) {
        return KeyEventResult.ignored;
      }
      _scrollBy(1);
      return KeyEventResult.handled;
    }),
    ScrollPageUpIntent: CallbackAction<ScrollPageUpIntent>((intent, context) {
      _controller.pageUp();
      return KeyEventResult.handled;
    }),
    ScrollPageDownIntent: CallbackAction<ScrollPageDownIntent>((
      intent,
      context,
    ) {
      _controller.pageDown();
      return KeyEventResult.handled;
    }),
    ScrollToStartIntent: CallbackAction<ScrollToStartIntent>((intent, context) {
      _controller.jumpTo(0);
      return KeyEventResult.handled;
    }),
    ScrollToEndIntent: CallbackAction<ScrollToEndIntent>((intent, context) {
      _controller.jumpTo(_controller.maxScrollExtent);
      return KeyEventResult.handled;
    }),
  };

  Map<ShortcutActivator, Intent> get _shortcuts => const {
    SingleActivator(LogicalKeyboardKey.arrowUp): ScrollUpIntent(),
    SingleActivator(LogicalKeyboardKey.arrowDown): ScrollDownIntent(),
    SingleActivator(LogicalKeyboardKey.arrowLeft): ScrollLeftIntent(),
    SingleActivator(LogicalKeyboardKey.arrowRight): ScrollRightIntent(),
    SingleActivator(LogicalKeyboardKey.pageUp): ScrollPageUpIntent(),
    SingleActivator(LogicalKeyboardKey.pageDown): ScrollPageDownIntent(),
    SingleActivator(LogicalKeyboardKey.home): ScrollToStartIntent(),
    SingleActivator(LogicalKeyboardKey.end): ScrollToEndIntent(),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions,
        child: Focus(
          focusNode: focusNode,
          autofocus: widget.autofocus,
          child: PointerListener(
            onPointerScroll: _handlePointerScroll,
            child: _ScrollBoxRenderObjectWidget(
              controller: _controller,
              scrollDirection: widget.scrollDirection,
              showScrollbar: widget.showScrollbar,
              scrollbarColor: widget.scrollbarColor ?? theme.scrollbarThumb,
              trackColor: widget.trackColor ?? theme.scrollbarTrack,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollBoxRenderObjectWidget extends SingleChildRenderObjectWidget {
  const _ScrollBoxRenderObjectWidget({
    required this.controller,
    required this.scrollDirection,
    required this.showScrollbar,
    required this.scrollbarColor,
    required this.trackColor,
    required Widget super.child,
  });

  final ScrollController controller;
  final Axis scrollDirection;
  final bool showScrollbar;
  final Color scrollbarColor;
  final Color trackColor;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderScrollBox(
    controller: controller,
    scrollDirection: scrollDirection,
    showScrollbar: showScrollbar,
    scrollbarColor: scrollbarColor,
    trackColor: trackColor,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderScrollBox renderObject,
  ) {
    renderObject
      ..controller = controller
      ..scrollDirection = scrollDirection
      ..showScrollbar = showScrollbar
      ..scrollbarColor = scrollbarColor
      ..trackColor = trackColor;
  }
}

/// RenderObject behind [ScrollBox]: lays out its child unbounded along the
/// scroll axis, then translates and clips during paint. Renders an optional
/// 1-cell scrollbar gutter on the trailing edge.
class RenderScrollBox extends RenderProxyBox {
  /// Borrows [controller]; layout sizes the child with an unbounded scroll axis
  /// and publishes extents, while paint translates, clips, and draws any scrollbar.
  RenderScrollBox({
    required ScrollController controller,
    required Axis scrollDirection,
    required bool showScrollbar,
    required Color scrollbarColor,
    required Color trackColor,
  }) : _controller = controller,
       _scrollDirection = scrollDirection,
       _showScrollbar = showScrollbar,
       _scrollbarColor = scrollbarColor,
       _trackColor = trackColor;

  ScrollController _controller;
  Axis _scrollDirection;
  bool _showScrollbar;
  Color _scrollbarColor;
  Color _trackColor;
  bool _hasControllerListener = false;

  set controller(ScrollController v) {
    if (identical(_controller, v)) return;
    if (_hasControllerListener) {
      _controller.removeListener(_handleControllerChanged);
      _hasControllerListener = false;
    }
    _controller = v;
    _syncControllerListener();
    markNeedsLayout();
  }

  set scrollDirection(Axis v) {
    if (_scrollDirection == v) return;
    _scrollDirection = v;
    markNeedsLayout();
  }

  set showScrollbar(bool v) {
    if (_showScrollbar == v) return;
    _showScrollbar = v;
    markNeedsLayout();
  }

  set scrollbarColor(Color v) {
    if (_scrollbarColor == v) return;
    _scrollbarColor = v;
    markNeedsPaint();
  }

  set trackColor(Color v) {
    if (_trackColor == v) return;
    _trackColor = v;
    markNeedsPaint();
  }

  @override
  @internal
  @protected
  void didAttach(PipelineOwner owner) {
    _syncControllerListener();
  }

  @override
  void detach() {
    try {
      super.detach();
    } finally {
      _syncControllerListener();
    }
  }

  void _handleControllerChanged() {
    markNeedsPaint();
  }

  void _syncControllerListener() {
    final shouldListen = pipelineOwner != null;
    if (_hasControllerListener == shouldListen) return;
    if (shouldListen) {
      _controller.addListener(_handleControllerChanged);
    } else {
      _controller.removeListener(_handleControllerChanged);
    }
    _hasControllerListener = shouldListen;
  }

  int get _gutterWidth =>
      _showScrollbar && _scrollDirection == Axis.vertical ? 1 : 0;
  int get _gutterHeight =>
      _showScrollbar && _scrollDirection == Axis.horizontal ? 1 : 0;

  int get _viewportWidth => math.max(0, width - _gutterWidth);
  int get _viewportHeight => math.max(0, height - _gutterHeight);

  @override
  void performBoxLayout(BoxConstraints constraints) {
    // Self size: take all available space. Unbounded (null max) falls back
    // to the lower bound so a ScrollBox always has a definite size.
    final w = constraints.maxWidth ?? constraints.minWidth;
    final h = constraints.maxHeight ?? constraints.minHeight;
    size = Size(w, h);

    final c = child;
    if (c == null) {
      _controller._updateViewportExtent(0);
      _controller.updateMaxScrollExtent(0);
      return;
    }

    // Child gets bounded cross-axis, unbounded (null) along scroll axis.
    final BoxConstraints childConstraints;
    if (_scrollDirection == Axis.vertical) {
      childConstraints = BoxConstraints(
        minWidth: _viewportWidth,
        maxWidth: _viewportWidth,
      );
    } else {
      childConstraints = BoxConstraints(
        minHeight: _viewportHeight,
        maxHeight: _viewportHeight,
      );
    }
    c.layout(childConstraints);
    c
      ..x = 0
      ..y = 0;

    final contentExtent = _scrollDirection == Axis.vertical
        ? c.size.height.toDouble()
        : c.size.width.toDouble();
    final viewportExtent = _scrollDirection == Axis.vertical
        ? _viewportHeight
        : _viewportWidth;
    final maxScroll = (contentExtent - viewportExtent).clamp(
      0.0,
      contentExtent,
    );
    _controller._updateViewportExtent(viewportExtent);
    _controller.updateMaxScrollExtent(maxScroll);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final originX = offset.dx + x;
    final originY = offset.dy + y;
    final viewportW = _viewportWidth;
    final viewportH = _viewportHeight;
    if (width <= 0 || height <= 0 || viewportW <= 0 || viewportH <= 0) {
      return;
    }

    final c = child;
    if (c != null) {
      // Paint child, translated by -offset, clipped to viewport.
      final scrollX = _scrollDirection == Axis.horizontal
          ? -_controller.offset.round()
          : 0;
      final scrollY = _scrollDirection == Axis.vertical
          ? -_controller.offset.round()
          : 0;

      context.canvas.save();
      context.canvas.clipRect(
        Rect.fromLTWH(originX, originY, viewportW, viewportH),
      );
      context.paintChild(c, Offset(originX + scrollX, originY + scrollY));
      context.canvas.restore();
    }

    if (_showScrollbar) {
      _paintScrollbar(context, originX, originY, viewportW, viewportH);
    }
  }

  @override
  bool hitTestChildren(HitTestResult result, Offset position) {
    if (width <= 0 ||
        height <= 0 ||
        _viewportWidth <= 0 ||
        _viewportHeight <= 0) {
      return false;
    }
    final c = child;
    if (c == null) {
      return false;
    }
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx >= _viewportWidth ||
        position.dy >= _viewportHeight) {
      return false;
    }

    final scrollX = _scrollDirection == Axis.horizontal
        ? _controller.offset.round()
        : 0;
    final scrollY = _scrollDirection == Axis.vertical
        ? _controller.offset.round()
        : 0;
    final childPosition =
        position - Offset(c.x, c.y) + Offset(scrollX, scrollY);
    return c.hitTest(result, childPosition);
  }

  void _paintScrollbar(
    PaintingContext context,
    int originX,
    int originY,
    int viewW,
    int viewH,
  ) {
    final canvas = context.canvas;
    if (_scrollDirection == Axis.vertical) {
      final trackX = originX + viewW;
      // Track
      canvas.fillRect(Rect.fromLTWH(trackX, originY, 1, height), _trackColor);
      // Thumb
      final c = child;
      if (c == null) return;
      final contentH = c.size.height;
      if (contentH <= viewH) return;
      final thumbHeight = (viewH * viewH / contentH).clamp(1, viewH).round();
      final maxThumbY = viewH - thumbHeight;
      final progress = _controller.maxScrollExtent == 0
          ? 0.0
          : _controller.offset / _controller.maxScrollExtent;
      final thumbY = originY + (progress * maxThumbY).round();
      canvas.fillRect(
        Rect.fromLTWH(trackX, thumbY, 1, thumbHeight),
        _scrollbarColor,
      );
    } else {
      final trackY = originY + viewH;
      canvas.fillRect(Rect.fromLTWH(originX, trackY, width, 1), _trackColor);
      final c = child;
      if (c == null) return;
      final contentW = c.size.width;
      if (contentW <= viewW) return;
      final thumbWidth = (viewW * viewW / contentW).clamp(1, viewW).round();
      final maxThumbX = viewW - thumbWidth;
      final progress = _controller.maxScrollExtent == 0
          ? 0.0
          : _controller.offset / _controller.maxScrollExtent;
      final thumbX = originX + (progress * maxThumbX).round();
      canvas.fillRect(
        Rect.fromLTWH(thumbX, trackY, thumbWidth, 1),
        _scrollbarColor,
      );
    }
  }
}
