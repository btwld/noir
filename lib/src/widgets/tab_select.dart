import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../core/color.dart';
import '../core/grapheme_metrics.dart';
import '../core/input.dart';
import '../core/mouse_cursor.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/box.dart';
import '../rendering/object.dart';
import 'actions.dart';
import 'focus.dart';
import 'focus_node_owner_mixin.dart';
import 'icons.dart';
import 'intents.dart';
import 'pointer_listener.dart';
import 'select.dart';
import 'shortcuts.dart';
import 'theme.dart';

/// A horizontal, focusable selector over typed [SelectOption] values.
class TabSelect<T> extends StatefulWidget {
  /// Configures horizontal tabs with optional underline and description rows.
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
    this.selectedTextAttributes = 0,
    this.descriptionColor,
    this.focusNode,
    this.autofocus = false,
    this.requestFocusOnPointer = true,
    this.onChanged,
    this.onSelect,
  }) : assert(tabWidth == null || tabWidth > 0);

  /// Tabs in document order.
  final List<SelectOption<T>> options;

  /// Initially selected tab, or a replacement selection when this changes.
  final int selectedIndex;

  /// Width reserved for each visible tab in cells.
  ///
  /// When null, each tab uses its label's terminal-cell width plus two cells
  /// of horizontal padding.
  final int? tabWidth;

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

  /// Terminal attributes applied to the selected tab label.
  final int selectedTextAttributes;

  /// Selected description foreground.
  final Color? descriptionColor;

  /// Caller-owned focus node, or null for widget ownership.
  final FocusNode? focusNode;

  /// Whether focus is requested after mounting.
  final bool autofocus;

  /// Whether a primary-button pointer press requests focus.
  ///
  /// Disable this for a navigation strip that should leave an adjacent
  /// content view focused after pointer selection.
  final bool requestFocusOnPointer;

  /// Called when navigation changes the selected index.
  final SelectChanged<T>? onChanged;

  /// Called when Enter or a pointer confirms the selected tab.
  final SelectConfirmed<T>? onSelect;

  @override
  State<TabSelect<T>> createState() => _TabSelectState<T>();
}

final class _TabSelectMetrics {
  int scrollOffset = 0;
  List<int> visibleWidths = const <int>[];

  int get visibleTabs => visibleWidths.length;

  int? indexAt(int x) {
    if (x < 0) return null;
    var left = 0;
    for (var visible = 0; visible < visibleWidths.length; visible++) {
      left += visibleWidths[visible];
      if (x < left) return scrollOffset + visible;
    }
    return null;
  }
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
    if (widget.requestFocusOnPointer && !focusNode.hasFocus) {
      focusNode.requestFocus();
    }
    final index = _metrics.indexAt(event.localPosition.dx);
    if (index == null) return;
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
              selectedTextAttributes: widget.selectedTextAttributes,
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
    required this.selectedTextAttributes,
    required this.descriptionColor,
    required this.metrics,
  });

  final List<SelectOption<T>> options;
  final int selectedIndex;
  final int? tabWidth;
  final bool showScrollArrows;
  final bool showDescription;
  final bool showUnderline;
  final Color color;
  final Color? backgroundColor;
  final Color selectedBackgroundColor;
  final Color selectedTextColor;
  final int selectedTextAttributes;
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
    selectedTextAttributes: selectedTextAttributes,
    descriptionColor: descriptionColor,
    metrics: metrics,
  );

  @override
  @internal
  void updateRenderObject(BuildContext context, _RenderTabSelect<T> render) {
    render.updateFrom(this);
  }
}

final class _RenderTabSelect<T> extends RenderBox implements MouseCursorTarget {
  _RenderTabSelect({
    required List<SelectOption<T>> options,
    required int selectedIndex,
    required int? tabWidth,
    required bool showScrollArrows,
    required bool showDescription,
    required bool showUnderline,
    required Color color,
    required Color? backgroundColor,
    required Color selectedBackgroundColor,
    required Color selectedTextColor,
    required int selectedTextAttributes,
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
       _selectedTextAttributes = selectedTextAttributes,
       _descriptionColor = descriptionColor,
       _metrics = metrics;

  List<SelectOption<T>> _options;
  int _selectedIndex;
  int? _tabWidth;
  bool _showScrollArrows;
  bool _showDescription;
  bool _showUnderline;
  Color _color;
  Color? _backgroundColor;
  Color _selectedBackgroundColor;
  Color _selectedTextColor;
  int _selectedTextAttributes;
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
    _selectedTextAttributes = widget.selectedTextAttributes;
    _descriptionColor = widget.descriptionColor;
    _metrics = widget.metrics;
    markNeedsLayout();
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final widths = <int>[
      for (final option in _options)
        _tabWidth ?? terminalStringWidth(option.name) + 2,
    ];
    final tabWidth = _tabWidth;
    final naturalWidth = tabWidth == null
        ? math.max(1, widths.fold<int>(0, (total, width) => total + width))
        : math.max(tabWidth, tabWidth * _options.length);
    final rows = 1 + (_showUnderline ? 1 : 0) + (_showDescription ? 1 : 0);
    size = Size(
      constraints.constrainWidth(constraints.maxWidth ?? naturalWidth),
      constraints.constrainHeight(rows),
    );
    if (tabWidth != null) {
      _layoutFixedTabs(tabWidth);
    } else {
      _layoutContentSizedTabs(widths);
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  MouseCursor mouseCursorAt(Offset position) {
    final index = _metrics.indexAt(position.dx);
    return position.dy == 0 &&
            index != null &&
            index >= 0 &&
            index < _options.length
        ? MouseCursor.pointer
        : MouseCursor.basic;
  }

  @override
  void handleEvent(MouseEvent event, HitTestEntry entry) {
    // The ancestor PointerListener owns focus and tab activation.
  }

  void _layoutFixedTabs(int tabWidth) {
    final capacity = math.max(1, size.width ~/ tabWidth);
    final half = capacity ~/ 2;
    final scrollOffset = math.max(
      0,
      math.min(_selectedIndex - half, math.max(0, _options.length - capacity)),
    );
    final visibleWidths = <int>[];
    final count = math.min(capacity, _options.length - scrollOffset);
    for (var visible = 0; visible < count; visible++) {
      final width = math.min(tabWidth, size.width - visible * tabWidth);
      if (width <= 0) break;
      visibleWidths.add(width);
    }
    _metrics
      ..scrollOffset = scrollOffset
      ..visibleWidths = visibleWidths;
  }

  void _layoutContentSizedTabs(List<int> widths) {
    if (widths.isEmpty || size.width <= 0) {
      _metrics
        ..scrollOffset = 0
        ..visibleWidths = const <int>[];
      return;
    }

    final selected = _selectedIndex.clamp(0, widths.length - 1);
    var scrollOffset = 0;
    var selectedRangeWidth = 0;
    for (var index = 0; index <= selected; index++) {
      selectedRangeWidth += widths[index];
    }
    while (scrollOffset < selected && selectedRangeWidth > size.width) {
      selectedRangeWidth -= widths[scrollOffset];
      scrollOffset++;
    }

    final visibleWidths = <int>[];
    var remaining = size.width;
    for (var index = scrollOffset; index < widths.length; index++) {
      final width = widths[index];
      if (width > remaining) {
        if (index == selected && remaining > 0) visibleWidths.add(remaining);
        break;
      }
      visibleWidths.add(width);
      remaining -= width;
    }
    _metrics
      ..scrollOffset = scrollOffset
      ..visibleWidths = visibleWidths;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = offset + Offset(x, y);
    if (_backgroundColor case final background?) {
      context.canvas.fillRect(origin & size, background);
    }
    var left = 0;
    for (var index = 0; index < _metrics.visibleTabs; index++) {
      final actual = _metrics.scrollOffset + index;
      final width = _metrics.visibleWidths[index];
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
        attributes: selected ? _selectedTextAttributes : 0,
      );
      if (selected && _showUnderline && size.height > 1) {
        context.canvas.drawText(
          List<String>.filled(width, '▬').join(),
          Offset(origin.dx + left, origin.dy + 1),
          _selectedTextColor,
        );
      }
      left += width;
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
        context.canvas.drawText(Icons.chevronLeft, origin, _descriptionColor);
      }
      if (_metrics.scrollOffset + _metrics.visibleTabs < _options.length) {
        context.canvas.drawText(
          Icons.chevronRight,
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
  if (cells == 1) return Icons.ellipsis;
  return '${sliceByCells(value, cells - 1)}${Icons.ellipsis}';
}

void _validateTabWidth(int? value) {
  if (value != null && value <= 0) {
    throw ArgumentError.value(value, 'tabWidth', 'must be positive');
  }
}
