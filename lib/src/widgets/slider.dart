// ignore_for_file: avoid_setters_without_getters

import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../core/color.dart';
import '../core/input.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/box.dart';
import '../rendering/object.dart';
import 'actions.dart';
import 'focus.dart';
import 'focus_node_owner_mixin.dart';
import 'input.dart' show ValueChanged;
import 'intents.dart';
import 'pointer_listener.dart';
import 'shortcuts.dart';
import 'theme.dart';

/// A controlled horizontal or vertical value slider.
class Slider extends StatefulWidget {
  /// Configures a slider over the inclusive [min]–[max] range.
  const Slider({
    required this.value,
    super.key,
    this.min = 0,
    this.max = 100,
    this.viewportSize,
    this.axis = Axis.horizontal,
    this.step = 1,
    this.trackColor,
    this.thumbColor,
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
  }) : assert(max >= min),
       assert(value >= min && value <= max),
       assert(step > 0),
       assert(viewportSize == null || viewportSize >= 0);

  /// Current controlled value.
  final double value;

  /// Inclusive minimum.
  final double min;

  /// Inclusive maximum.
  final double max;

  /// Range represented by the thumb; defaults to ten percent of the range.
  final double? viewportSize;

  /// Track orientation.
  final Axis axis;

  /// Keyboard increment.
  final double step;

  /// Track fill, defaulting to [ThemeData.scrollbarTrack].
  final Color? trackColor;

  /// Thumb fill, defaulting to [ThemeData.accent].
  final Color? thumbColor;

  /// Caller-owned focus node, or null for widget ownership.
  final FocusNode? focusNode;

  /// Whether focus is requested after mounting.
  final bool autofocus;

  /// Receives proposed values; null disables input.
  final ValueChanged<double>? onChanged;

  @override
  State<Slider> createState() => _SliderState();
}

enum _SliderOperation { decrement, increment, pageUp, pageDown, first, last }

final class _SliderIntent extends Intent {
  const _SliderIntent(this.operation);

  final _SliderOperation operation;
}

final class _SliderState extends State<Slider>
    with FocusNodeOwnerStateMixin<Slider> {
  bool _dragging = false;
  final _metrics = _SliderMetrics();

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  bool get _enabled => widget.onChanged != null && widget.max > widget.min;

  @override
  void initState() {
    super.initState();
    _validate(widget);
  }

  @override
  void didUpdateWidget(Slider oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
    _validate(widget);
  }

  void _emit(double value) {
    if (!_enabled) return;
    widget.onChanged!(value.clamp(widget.min, widget.max));
  }

  Map<Type, Action<Intent>> get _actions => <Type, Action<Intent>>{
    _SliderIntent: CallbackAction<_SliderIntent>((intent, context) {
      if (!_enabled) return KeyEventResult.ignored;
      final value = switch (intent.operation) {
        _SliderOperation.decrement => widget.value - widget.step,
        _SliderOperation.increment => widget.value + widget.step,
        _SliderOperation.pageUp => widget.value - _pageSize,
        _SliderOperation.pageDown => widget.value + _pageSize,
        _SliderOperation.first => widget.min,
        _SliderOperation.last => widget.max,
      };
      _emit(value);
      return KeyEventResult.handled;
    }),
  };

  Map<ShortcutActivator, Intent> get _shortcuts {
    final decrement = widget.axis == Axis.horizontal
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowUp;
    final increment = widget.axis == Axis.horizontal
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowDown;
    return <ShortcutActivator, Intent>{
      SingleActivator(decrement): const _SliderIntent(
        _SliderOperation.decrement,
      ),
      SingleActivator(increment): const _SliderIntent(
        _SliderOperation.increment,
      ),
      const SingleActivator(LogicalKeyboardKey.pageUp): const _SliderIntent(
        _SliderOperation.pageUp,
      ),
      const SingleActivator(LogicalKeyboardKey.pageDown): const _SliderIntent(
        _SliderOperation.pageDown,
      ),
      const SingleActivator(LogicalKeyboardKey.home): const _SliderIntent(
        _SliderOperation.first,
      ),
      const SingleActivator(LogicalKeyboardKey.end): const _SliderIntent(
        _SliderOperation.last,
      ),
    };
  }

  double get _pageSize =>
      widget.viewportSize ??
      math.max(widget.step, (widget.max - widget.min) * 0.1);

  void _updateFromPointer(MouseEvent event) {
    if (!_enabled) return;
    final extent = widget.axis == Axis.horizontal
        ? _metrics.width
        : _metrics.height;
    if (extent <= 0) return;
    final position = widget.axis == Axis.horizontal
        ? event.localPosition.dx
        : event.localPosition.dy;
    final ratio = (position / extent).clamp(0.0, 1.0);
    _emit(widget.min + ratio * (widget.max - widget.min));
  }

  void _handleDown(MouseEvent event) {
    if (event.button != MouseButton.left || !_enabled) return;
    if (!focusNode.hasFocus) focusNode.requestFocus();
    _dragging = true;
    _updateFromPointer(event);
  }

  void _handleMove(MouseEvent event) {
    if (_dragging) _updateFromPointer(event);
  }

  void _handleUp(MouseEvent event) {
    if (!_dragging) return;
    _updateFromPointer(event);
    _dragging = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions,
        child: Focus(
          focusNode: focusNode,
          autofocus: widget.autofocus && _enabled,
          canRequestFocus: _enabled,
          child: PointerListener(
            onPointerDown: _handleDown,
            onPointerMove: _handleMove,
            onPointerUp: _handleUp,
            child: _SliderLeaf(
              value: widget.value,
              min: widget.min,
              max: widget.max,
              viewportSize:
                  widget.viewportSize ?? (widget.max - widget.min) * 0.1,
              axis: widget.axis,
              trackColor: widget.trackColor ?? theme.scrollbarTrack,
              thumbColor: _enabled
                  ? widget.thumbColor ?? theme.accent
                  : theme.textMuted,
              metrics: _metrics,
            ),
          ),
        ),
      ),
    );
  }
}

final class _SliderLeaf extends RenderObjectWidget {
  const _SliderLeaf({
    required this.value,
    required this.min,
    required this.max,
    required this.viewportSize,
    required this.axis,
    required this.trackColor,
    required this.thumbColor,
    required this.metrics,
  });

  final double value;
  final double min;
  final double max;
  final double viewportSize;
  final Axis axis;
  final Color trackColor;
  final Color thumbColor;
  final _SliderMetrics metrics;

  @override
  @internal
  RenderObject createRenderObject(BuildContext context) => _RenderSlider(
    value: value,
    min: min,
    max: max,
    viewportSize: viewportSize,
    axis: axis,
    trackColor: trackColor,
    thumbColor: thumbColor,
    metrics: metrics,
  );

  @override
  @internal
  void updateRenderObject(BuildContext context, _RenderSlider render) {
    render
      ..value = value
      ..min = min
      ..max = max
      ..viewportSize = viewportSize
      ..axis = axis
      ..trackColor = trackColor
      ..thumbColor = thumbColor
      ..metrics = metrics;
  }
}

final class _RenderSlider extends RenderBox {
  _RenderSlider({
    required double value,
    required double min,
    required double max,
    required double viewportSize,
    required Axis axis,
    required Color trackColor,
    required Color thumbColor,
    required _SliderMetrics metrics,
  }) : _value = value,
       _min = min,
       _max = max,
       _viewportSize = viewportSize,
       _axis = axis,
       _trackColor = trackColor,
       _thumbColor = thumbColor,
       _metrics = metrics;

  double _value;
  double _min;
  double _max;
  double _viewportSize;
  Axis _axis;
  Color _trackColor;
  Color _thumbColor;
  _SliderMetrics _metrics;

  set value(double value) {
    if (_value == value) return;
    _value = value;
    markNeedsPaint();
  }

  set min(double value) {
    if (_min == value) return;
    _min = value;
    markNeedsPaint();
  }

  set max(double value) {
    if (_max == value) return;
    _max = value;
    markNeedsPaint();
  }

  set viewportSize(double value) {
    if (_viewportSize == value) return;
    _viewportSize = value;
    markNeedsPaint();
  }

  set axis(Axis value) {
    if (_axis == value) return;
    _axis = value;
    markNeedsLayout();
  }

  set trackColor(Color value) {
    if (_trackColor == value) return;
    _trackColor = value;
    markNeedsPaint();
  }

  set thumbColor(Color value) {
    if (_thumbColor == value) return;
    _thumbColor = value;
    markNeedsPaint();
  }

  set metrics(_SliderMetrics value) => _metrics = value;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = _axis == Axis.horizontal
        ? Size(
            constraints.constrainWidth(constraints.maxWidth ?? 20),
            constraints.constrainHeight(1),
          )
        : Size(
            constraints.constrainWidth(1),
            constraints.constrainHeight(constraints.maxHeight ?? 10),
          );
    _metrics
      ..width = size.width
      ..height = size.height;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = offset + Offset(x, y);
    context.canvas.fillRect(origin & size, _trackColor);
    final extent = _axis == Axis.horizontal ? size.width : size.height;
    if (extent <= 0) return;
    final range = _max - _min;
    final viewport = math.max(1, _viewportSize);
    final contentSize = range + viewport;
    final fraction = contentSize <= viewport
        ? 1.0
        : (viewport / contentSize).clamp(0.0, 1.0);
    final thumbExtent = math.max(1, (extent * fraction).ceil());
    final travel = math.max(0, extent - thumbExtent);
    final ratio = range <= 0 ? 0.0 : ((_value - _min) / range).clamp(0.0, 1.0);
    final start = (travel * ratio).round();
    context.canvas.fillRect(
      _axis == Axis.horizontal
          ? Rect.fromLTWH(
              origin.dx + start,
              origin.dy,
              thumbExtent,
              size.height,
            )
          : Rect.fromLTWH(
              origin.dx,
              origin.dy + start,
              size.width,
              thumbExtent,
            ),
      _thumbColor,
    );
  }
}

final class _SliderMetrics {
  int width = 0;
  int height = 0;
}

void _validate(Slider slider) {
  if (!slider.min.isFinite || !slider.max.isFinite || slider.max < slider.min) {
    throw ArgumentError('Slider max must be finite and at least min');
  }
  if (!slider.value.isFinite ||
      slider.value < slider.min ||
      slider.value > slider.max) {
    throw ArgumentError.value(
      slider.value,
      'value',
      'must be within min and max',
    );
  }
  if (!slider.step.isFinite || slider.step <= 0) {
    throw ArgumentError.value(
      slider.step,
      'step',
      'must be finite and positive',
    );
  }
  final viewport = slider.viewportSize;
  if (viewport != null && (!viewport.isFinite || viewport < 0)) {
    throw ArgumentError.value(
      viewport,
      'viewportSize',
      'must be finite and non-negative',
    );
  }
}
