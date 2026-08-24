import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../core/color.dart';
import '../core/grapheme_metrics.dart';
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
import 'intents.dart';
import 'pointer_listener.dart';
import 'select.dart';
import 'shortcuts.dart';
import 'theme.dart';

/// A horizontal, focusable selector over typed [SelectOption] values.
class TabSelect<T> extends StatefulWidget {
  /// Configures fixed-cell tabs with optional underline and description rows.
  const TabSelect({
    required this.options,
    super.key,
    this.selectedIndex = 0,
    this.tabWidth = 20,
    this.showScrollArrows = true,
    this.showDescription = true,
    this.showUnderline = true,
    this.wrapSelection = false,
    this.color,
    this.backgroundColor,
    this.selectedBackgroundColor,
    this.selectedTextColor,
    this.descriptionColor,
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.onSelect,
  }) : assert(tabWidth > 0);

  /// Tabs in document order.
  final List<SelectOption<T>> options;

  /// Initially selected tab, or a replacement selection when this changes.
  final int selectedIndex;

  /// Width reserved for each visible tab in cells.
  final int tabWidth;

  /// Whether overflow arrows are painted at the row edges.
  final bool showScrollArrows;

  /// Whether the selected option's description gets its own row.
  final bool showDescription;

  /// Whether a selected-tab underline row is painted.
  final bool showUnderline;

  /// Whether navigation wraps between the first and last tab.
  final bool wrapSelection;

  /// Unselected tab foreground.
  final Color? color;

  /// Optional background fill.
  final Color? backgroundColor;

  /// Selected tab fill.
  final Color? selectedBackgroundColor;

  /// Selected tab and underline foreground.
  final Color? selectedTextColor;

  /// Selected description foreground.
  final Color? descriptionColor;

  /// Caller-owned focus node, or null for widget ownership.
  final FocusNode? focusNode;

  /// Whether focus is requested after mounting.
  final bool autofocus;

  /// Called when navigation changes the selected index.
  final SelectChanged<T>? onChanged;

  /// Called when Enter or a pointer confirms the selected tab.
  final SelectConfirmed<T>? onSelect;

  @override
  State<TabSelect<T>> createState() => _TabSelectState<T>();
}

final class _TabSelectMetrics {
  int scrollOffset = 0;
  int visibleTabs = 1;
}

final class _MoveTabIntent extends Intent {
  const _MoveTabIntent(this.delta);

  final int delta;
}

final class _TabSelectState<T> extends State<TabSelect<T>>
    with FocusNodeOwnerStateMixin<TabSelect<T>> {
  late int _selected;
  bool _focused = false;
  final _metrics = _TabSelectMetrics();

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  int get _maxIndex => widget.options.isEmpty ? 0 : widget.options.length - 1;

  @override
  void initState() {
    super.initState();
    _validateTabWidth(widget.tabWidth);
    _selected = widget.selectedIndex.clamp(0, _maxIndex);
  }

  @override
  void didUpdateWidget(TabSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
    _validateTabWidth(widget.tabWidth);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _selected = widget.selectedIndex.clamp(0, _maxIndex);
    } else if (widget.options.length != oldWidget.options.length) {
      _selected = _selected.clamp(0, _maxIndex);
    }
  }

  void _move(int delta) {
    if (widget.options.isEmpty) return;
    var next = _selected + delta;
    if (widget.wrapSelection) {
      next %= widget.options.length;
    } else {
      next = next.clamp(0, _maxIndex);
    }
    if (next == _selected) return;
    setState(() => _selected = next);
    widget.onChanged?.call(next, widget.options[next]);
  }

  void _confirm() {
    if (widget.options.isEmpty) return;
    widget.onSelect?.call(_selected, widget.options[_selected]);
  }

  Map<Type, Action<Intent>> get _actions => <Type, Action<Intent>>{
    _MoveTabIntent: CallbackAction<_MoveTabIntent>((intent, context) {
      _move(intent.delta);
      return KeyEventResult.handled;
    }),
    ActivateIntent: CallbackAction<ActivateIntent>((intent, context) {
      _confirm();
      return KeyEventResult.handled;
    }),
  };

  Map<ShortcutActivator, Intent> get _shortcuts => const {
    SingleActivator(LogicalKeyboardKey.arrowLeft): _MoveTabIntent(-1),
    CharacterActivator('['): _MoveTabIntent(-1),
    SingleActivator(LogicalKeyboardKey.arrowRight): _MoveTabIntent(1),
    CharacterActivator(']'): _MoveTabIntent(1),
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  };

  void _handlePointer(MouseEvent event) {
    if (event.button != MouseButton.left || event.localPosition.dy != 0) return;
    if (!focusNode.hasFocus) focusNode.requestFocus();
    final visible = event.localPosition.dx ~/ widget.tabWidth;
    if (visible < 0 || visible >= _metrics.visibleTabs) return;
    final index = _metrics.scrollOffset + visible;
    if (index < 0 || index >= widget.options.length) return;
    if (index != _selected) {
      setState(() => _selected = index);
      widget.onChanged?.call(index, widget.options[index]);
    }
    _confirm();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.maybeOf(context);
    final palette = theme ?? ThemeData.dark;
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions,
        child: Focus(
          focusNode: focusNode,
          autofocus: widget.autofocus,
          onFocusChange: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          child: PointerListener(
            onPointerDown: _handlePointer,
            child: _TabSelectLeaf<T>(
              options: widget.options,
              selectedIndex: _selected,
              tabWidth: widget.tabWidth,
              showScrollArrows: widget.showScrollArrows,
              showDescription: widget.showDescription,
              showUnderline: widget.showUnderline,
              color:
                  widget.color ?? (_focused ? palette.text : palette.textMuted),
              backgroundColor: widget.backgroundColor ?? theme?.surface,
              selectedBackgroundColor:
                  widget.selectedBackgroundColor ?? palette.selectedBackground,
              selectedTextColor:
                  widget.selectedTextColor ?? palette.selectedForeground,
              descriptionColor: widget.descriptionColor ?? palette.textMuted,
              metrics: _metrics,
            ),
          ),
        ),
      ),
    );
  }
}

final class _TabSelectLeaf<T> extends RenderObjectWidget {
  const _TabSelectLeaf({
    required this.options,
    required this.selectedIndex,
    required this.tabWidth,
    required this.showScrollArrows,
    required this.showDescription,
    required this.showUnderline,
    required this.color,
    required this.backgroundColor,
    required this.selectedBackgroundColor,
    required this.selectedTextColor,
    required this.descriptionColor,
    required this.metrics,
  });

  final List<SelectOption<T>> options;
  final int selectedIndex;
  final int tabWidth;
  final bool showScrollArrows;
  final bool showDescription;
  final bool showUnderline;
  final Color color;
  final Color? backgroundColor;
  final Color selectedBackgroundColor;
  final Color selectedTextColor;
  final Color descriptionColor;
  final _TabSelectMetrics metrics;

  @override
  @internal
  RenderObject createRenderObject(BuildContext context) => _RenderTabSelect<T>(
    options: options,
    selectedIndex: selectedIndex,
    tabWidth: tabWidth,
    showScrollArrows: showScrollArrows,
    showDescription: showDescription,
    showUnderline: showUnderline,
    color: color,
    backgroundColor: backgroundColor,
    selectedBackgroundColor: selectedBackgroundColor,
    selectedTextColor: selectedTextColor,
    descriptionColor: descriptionColor,
    metrics: metrics,
  );

  @override
  @internal
  void updateRenderObject(BuildContext context, _RenderTabSelect<T> render) {
    render.updateFrom(this);
  }
}

final class _RenderTabSelect<T> extends RenderBox {
  _RenderTabSelect({
    required List<SelectOption<T>> options,
    required int selectedIndex,
    required int tabWidth,
    required bool showScrollArrows,
    required bool showDescription,
    required bool showUnderline,
    required Color color,
    required Color? backgroundColor,
    required Color selectedBackgroundColor,
    required Color selectedTextColor,
    required Color descriptionColor,
    required _TabSelectMetrics metrics,
  }) : _options = options,
       _selectedIndex = selectedIndex,
       _tabWidth = tabWidth,
       _showScrollArrows = showScrollArrows,
       _showDescription = showDescription,
       _showUnderline = showUnderline,
       _color = color,
       _backgroundColor = backgroundColor,
       _selectedBackgroundColor = selectedBackgroundColor,
       _selectedTextColor = selectedTextColor,
       _descriptionColor = descriptionColor,
       _metrics = metrics;

  List<SelectOption<T>> _options;
  int _selectedIndex;
  int _tabWidth;
  bool _showScrollArrows;
  bool _showDescription;
  bool _showUnderline;
  Color _color;
  Color? _backgroundColor;
  Color _selectedBackgroundColor;
  Color _selectedTextColor;
  Color _descriptionColor;
  _TabSelectMetrics _metrics;

  void updateFrom(_TabSelectLeaf<T> widget) {
    _options = widget.options;
    _selectedIndex = widget.selectedIndex;
    _tabWidth = widget.tabWidth;
    _showScrollArrows = widget.showScrollArrows;
    _showDescription = widget.showDescription;
    _showUnderline = widget.showUnderline;
    _color = widget.color;
    _backgroundColor = widget.backgroundColor;
    _selectedBackgroundColor = widget.selectedBackgroundColor;
    _selectedTextColor = widget.selectedTextColor;
    _descriptionColor = widget.descriptionColor;
    _metrics = widget.metrics;
    markNeedsLayout();
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final naturalWidth = math.max(_tabWidth, _tabWidth * _options.length);
    final rows = 1 + (_showUnderline ? 1 : 0) + (_showDescription ? 1 : 0);
    size = Size(
      constraints.constrainWidth(constraints.maxWidth ?? naturalWidth),
      constraints.constrainHeight(rows),
    );
    final visible = math.max(1, size.width ~/ _tabWidth);
    final half = visible ~/ 2;
    _metrics
      ..visibleTabs = visible
      ..scrollOffset = math.max(
        0,
        math.min(_selectedIndex - half, math.max(0, _options.length - visible)),
      );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = offset + Offset(x, y);
    if (_backgroundColor case final background?) {
      context.canvas.fillRect(origin & size, background);
    }
    final visible = math.min(
      _metrics.visibleTabs,
      _options.length - _metrics.scrollOffset,
    );
    for (var index = 0; index < visible; index++) {
      final actual = _metrics.scrollOffset + index;
      final left = index * _tabWidth;
      final width = math.min(_tabWidth, size.width - left);
      if (width <= 0) break;
      final selected = actual == _selectedIndex;
      if (selected) {
        context.canvas.fillRect(
          Rect.fromLTWH(origin.dx + left, origin.dy, width, 1),
          _selectedBackgroundColor,
        );
      }
      final label = _truncate(_options[actual].name, math.max(0, width - 2));
      context.canvas.drawText(
        label,
        Offset(origin.dx + left + 1, origin.dy),
        selected ? _selectedTextColor : _color,
      );
      if (selected && _showUnderline && size.height > 1) {
        context.canvas.drawText(
          List<String>.filled(width, '▬').join(),
          Offset(origin.dx + left, origin.dy + 1),
          _selectedTextColor,
        );
      }
    }
    if (_showDescription && _options.isNotEmpty) {
      final row = _showUnderline ? 2 : 1;
      if (row < size.height) {
        context.canvas.drawText(
          _truncate(
            _options[_selectedIndex].description ?? '',
            math.max(0, size.width - 2),
          ),
          Offset(origin.dx + 1, origin.dy + row),
          _descriptionColor,
        );
      }
    }
    if (_showScrollArrows && _options.length > _metrics.visibleTabs) {
      if (_metrics.scrollOffset > 0) {
        context.canvas.drawText('‹', origin, _descriptionColor);
      }
      if (_metrics.scrollOffset + _metrics.visibleTabs < _options.length) {
        context.canvas.drawText(
          '›',
          Offset(origin.dx + size.width - 1, origin.dy),
          _descriptionColor,
        );
      }
    }
  }
}

String _truncate(String value, int cells) {
  if (cells <= 0) return '';
  if (terminalStringWidth(value) <= cells) return value;
  if (cells == 1) return '…';
  return '${sliceByCells(value, cells - 1)}…';
}

void _validateTabWidth(int value) {
  if (value <= 0) {
    throw ArgumentError.value(value, 'tabWidth', 'must be positive');
  }
}
