import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

import '../core/color.dart';
import '../core/grapheme_metrics.dart';
import '../core/input.dart';
import '../foundation/selected_text.dart';
import '../foundation/text_index_map.dart';
import '../foundation/text_selection.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/box.dart';
import '../rendering/object.dart';
import '../rendering/text_highlight.dart';
import 'actions.dart';
import 'focus.dart';
import 'focus_node_owner_mixin.dart';
import 'intents.dart';
import 'pointer_listener.dart';
import 'shortcuts.dart';
import 'text_layout.dart';
import 'text_span.dart';
import 'text_style.dart';
import 'theme.dart';

/// Called after an explicit copy attempt from a document selection.
typedef SelectionCopyCallback =
    void Function(SelectedText selection, {required bool success});

/// Selects whether nested document viewports own semantic scroll actions.
@internal
final class DocumentScrollScope extends InheritedWidget {
  /// Configures scrolling ownership for descendant [DocumentView] widgets.
  const DocumentScrollScope({
    required this.handlesScrolling,
    required super.child,
    this.handlesHorizontalScrolling,
    super.key,
  });

  /// Whether descendants register keyboard scroll actions.
  final bool handlesScrolling;

  /// Optional horizontal override when an ancestor owns only vertical scroll.
  final bool? handlesHorizontalScrolling;

  /// Returns the nearest policy, defaulting to standalone scroll ownership.
  static bool handlesScrollingOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DocumentScrollScope>();
    return scope?.handlesScrolling ?? true;
  }

  /// Returns whether descendants own horizontal keyboard scrolling.
  static bool handlesHorizontalScrollingOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DocumentScrollScope>();
    return scope?.handlesHorizontalScrolling ?? scope?.handlesScrolling ?? true;
  }

  @override
  bool updateShouldNotify(DocumentScrollScope oldWidget) =>
      handlesScrolling != oldWidget.handlesScrolling ||
      handlesHorizontalScrolling != oldWidget.handlesHorizontalScrolling;
}

/// Maps selectable descendant blocks into one composed document stream.
@internal
final class DocumentSelectionScope extends InheritedWidget {
  /// Creates a selection scope for one block beginning at [sourceBase].
  const DocumentSelectionScope({
    required this.documentText,
    required this.sourceBase,
    required TextSelection? selection,
    required bool dragging,
    required this.readSelection,
    required this.readDragging,
    required this.onSelectionChanged,
    required this.onDraggingChanged,
    required this.onCopy,
    required super.child,
    super.key,
  }) : _selectionSnapshot = selection,
       _draggingSnapshot = dragging;

  /// Plain text for the complete composed document.
  final String documentText;

  /// UTF-16 offset of this descendant block in [documentText].
  final int sourceBase;

  final TextSelection? _selectionSnapshot;

  final bool _draggingSnapshot;

  /// Reads the current selection before a scheduled rebuild has completed.
  final TextSelection? Function() readSelection;

  /// Reads pointer-drag ownership before a scheduled rebuild has completed.
  final bool Function() readDragging;

  /// Current selection in complete-document coordinates.
  TextSelection? get selection => readSelection();

  /// Whether any descendant block owns the active pointer drag.
  bool get dragging => readDragging();

  /// Replaces the complete-document selection.
  final void Function(TextSelection? selection) onSelectionChanged;

  /// Changes complete-document pointer-drag ownership.
  final void Function({required bool dragging}) onDraggingChanged;

  /// Receives explicit copy results for complete-document selections.
  final SelectionCopyCallback? onCopy;

  /// Returns the nearest composed selection scope, if one exists.
  static DocumentSelectionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DocumentSelectionScope>();

  /// Returns the non-empty complete-document selection and selected text.
  SelectedText? get selectedText {
    final current = selection;
    if (current == null || current.isCollapsed) return null;
    return SelectedText(
      selection: current,
      text: documentText.substring(current.start, current.end),
    );
  }

  /// Returns the selected range intersecting a block of [length] UTF-16 units.
  TextSelection? selectionForBlock(int length) {
    final current = selection;
    if (current == null || current.isCollapsed) return null;
    final start = math.max(current.start, sourceBase);
    final end = math.min(current.end, sourceBase + length);
    if (start >= end) return null;
    return TextSelection(
      baseOffset: start - sourceBase,
      extentOffset: end - sourceBase,
    );
  }

  /// Copies the current complete-document selection through the owner.
  KeyEventResult copySelection(BuildContext context) {
    final selected = selectedText;
    if (selected == null) return KeyEventResult.ignored;
    final success = context.owner.copyToClipboard(selected.text);
    onCopy?.call(selected, success: success);
    return KeyEventResult.handled;
  }

  @override
  bool updateShouldNotify(DocumentSelectionScope oldWidget) =>
      documentText != oldWidget.documentText ||
      sourceBase != oldWidget.sourceBase ||
      _selectionSnapshot != oldWidget._selectionSnapshot ||
      _draggingSnapshot != oldWidget._draggingSnapshot ||
      !identical(readSelection, oldWidget.readSelection) ||
      !identical(readDragging, oldWidget.readDragging) ||
      !identical(onSelectionChanged, oldWidget.onSelectionChanged) ||
      !identical(onDraggingChanged, oldWidget.onDraggingChanged) ||
      !identical(onCopy, oldWidget.onCopy);
}

/// Supplies complete-document selection shortcuts around composed content.
///
/// Descendant document leaves may override these actions with layout-aware
/// behavior. When a custom renderer supplies no selectable leaf, this owner
/// remains the focus and semantic selection fallback.
@internal
final class DocumentSelectionControls extends StatelessWidget {
  /// Creates selection controls for [documentText].
  const DocumentSelectionControls({
    required this.documentText,
    required this.selectable,
    required this.readSelection,
    required this.onSelectionChanged,
    required this.onCopy,
    required this.focusNode,
    required this.child,
    super.key,
  });

  /// Complete semantic text selected and copied by these controls.
  final String documentText;

  /// Whether selection commands are enabled.
  final bool selectable;

  /// Reads the latest complete-document selection.
  final TextSelection? Function() readSelection;

  /// Replaces the complete-document selection.
  final void Function(TextSelection? selection) onSelectionChanged;

  /// Receives explicit copy results.
  final SelectionCopyCallback? onCopy;

  /// Focus attached by a descendant viewport or focus boundary.
  final FocusNode focusNode;

  /// Composed document content.
  final Widget child;

  void _extendSelection(_SelectionMove move) {
    final selection = readSelection();
    final base = selection?.baseOffset ?? 0;
    final extent = selection?.extentOffset ?? base;
    final next = switch (move) {
      _SelectionMove.previous => _previousTextBoundary(documentText, extent),
      _SelectionMove.next => _nextTextBoundary(documentText, extent),
      _SelectionMove.up => _previousSourceLine(documentText, extent),
      _SelectionMove.down => _nextSourceLine(documentText, extent),
    };
    onSelectionChanged(
      TextSelection(baseOffset: base, extentOffset: next, isDirectional: true),
    );
  }

  bool _focusIsWithinDocument(BuildContext context) {
    var current = context.owner.focusManager.primaryFocus;
    while (current != null) {
      if (identical(current, focusNode)) return true;
      current = current.parent;
    }
    return false;
  }

  void _handlePointerDown(BuildContext context, MouseEvent event) {
    if (event.button != MouseButton.left || _focusIsWithinDocument(context)) {
      return;
    }
    focusNode.requestFocus();
  }

  Map<Type, Action<Intent>> get _actions => <Type, Action<Intent>>{
    _SelectAllIntent: CallbackAction<_SelectAllIntent>((intent, context) {
      if (!selectable) return KeyEventResult.ignored;
      if (documentText.isNotEmpty) {
        onSelectionChanged(
          TextSelection(baseOffset: 0, extentOffset: documentText.length),
        );
      }
      return KeyEventResult.handled;
    }),
    _CopySelectionIntent: CallbackAction<_CopySelectionIntent>((
      intent,
      context,
    ) {
      if (!selectable) return KeyEventResult.ignored;
      final selection = readSelection();
      if (selection == null || selection.isCollapsed) {
        return KeyEventResult.ignored;
      }
      final selected = SelectedText(
        selection: selection,
        text: documentText.substring(selection.start, selection.end),
      );
      final success = context.owner.copyToClipboard(selected.text);
      onCopy?.call(selected, success: success);
      return KeyEventResult.handled;
    }),
    DismissIntent: CallbackAction<DismissIntent>((intent, context) {
      final selection = readSelection();
      if (!selectable || selection == null || selection.isCollapsed) {
        return KeyEventResult.ignored;
      }
      onSelectionChanged(null);
      return KeyEventResult.handled;
    }),
    _ExtendSelectionIntent: CallbackAction<_ExtendSelectionIntent>((
      intent,
      context,
    ) {
      if (!selectable || documentText.isEmpty) {
        return KeyEventResult.ignored;
      }
      _extendSelection(intent.move);
      return KeyEventResult.handled;
    }),
  };

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: _documentSelectionShortcuts,
    child: Actions(
      actions: _actions,
      child: PointerListener(
        onPointerDown: (event) => _handlePointerDown(context, event),
        child: child,
      ),
    ),
  );
}

/// Internal imperative scroll seam shared by composed document widgets.
@internal
final class DocumentViewportController {
  void Function(int line)? _jump;
  int? _pendingLine;

  /// Scrolls to a zero-based visual [line] when a viewport is attached.
  void jumpToLine(int line) {
    if (line < 0) {
      throw ArgumentError.value(line, 'line', 'must be non-negative');
    }
    final jump = _jump;
    if (jump == null) {
      _pendingLine = line;
    } else {
      jump(line);
    }
  }

  void _attach(void Function(int line) jump) {
    _jump = jump;
    final pending = _pendingLine;
    _pendingLine = null;
    if (pending != null) jump(pending);
  }

  void _detach(void Function(int line) jump) {
    if (_jump == jump) _jump = null;
  }
}

/// Shared selectable, scrollable viewport used by document components.
@internal
final class DocumentView extends StatefulWidget {
  /// Configures a rich-text document viewport.
  const DocumentView({
    required this.text,
    required this.plainText,
    super.key,
    this.wrap = true,
    this.selectable = true,
    this.showLineNumbers = false,
    this.lineNumberStyle = const TextStyle(color: Color.darkGray),
    this.selectionForegroundColor,
    this.selectionBackgroundColor = const Color(0.3, 0.5, 0.9, 0.5),
    this.focusNode,
    this.autofocus = false,
    this.onSelectionChanged,
    this.onCopy,
    this.onPointerDownOffset,
    this.onVisibleLineChanged,
    this.controller,
  });

  /// Rich content whose plain text matches [plainText].
  final InlineSpan text;

  /// UTF-16 source text used by selection callbacks and copying.
  final String plainText;

  /// Whether long lines soft-wrap.
  final bool wrap;

  /// Whether pointer and keyboard selection are enabled.
  final bool selectable;

  /// Whether a source-line gutter is painted.
  final bool showLineNumbers;

  /// Gutter text style.
  final TextStyle lineNumberStyle;

  /// Selected text foreground override.
  final Color? selectionForegroundColor;

  /// Selected text background.
  final Color selectionBackgroundColor;

  /// Caller-owned focus node, or null for widget ownership.
  final FocusNode? focusNode;

  /// Whether the viewport requests focus after mounting.
  final bool autofocus;

  /// Receives null for no non-empty selection.
  final void Function(SelectedText? selection)? onSelectionChanged;

  /// Receives the result of each explicit Ctrl+C copy attempt.
  final SelectionCopyCallback? onCopy;

  /// Receives the UTF-16 source offset activated by a left pointer press.
  final void Function(int offset)? onPointerDownOffset;

  /// Receives the first visible zero-based visual line after scrolling.
  final void Function(int line)? onVisibleLineChanged;

  /// Optional internal scroll coordinator for composed document views.
  final DocumentViewportController? controller;

  @override
  State<DocumentView> createState() => _DocumentViewState();
}

final class _DocumentMetrics {
  TextLayout? layout;
  int gutterWidth = 0;
  int viewportWidth = 0;
  int viewportHeight = 0;
  int maxScrollX = 0;
  int maxScrollY = 0;

  int sourceOffsetAt(Offset position, int scrollX, int scrollY) {
    final current = layout;
    if (current == null || current.lines.isEmpty) return 0;
    final lineIndex = (position.dy + scrollY).clamp(
      0,
      current.lines.length - 1,
    );
    final line = current.lines[lineIndex];
    final targetCell = math.max(0, position.dx - gutterWidth + scrollX);
    var cell = 0;
    for (final run in line.runs) {
      var sourceOffset = run.sourceStart;
      for (final grapheme in run.text.characters) {
        final width = terminalCellWidth(grapheme);
        if (targetCell < cell + math.max(1, width)) return sourceOffset;
        cell += width;
        sourceOffset += grapheme.length;
      }
    }
    return line.runs.isEmpty ? 0 : line.runs.last.sourceEnd;
  }

  int? offsetOneVisualLine(int offset, int delta) {
    final current = layout;
    if (current == null || current.lines.isEmpty) return null;
    var lineIndex = current.lines.indexWhere(
      (line) => line.runs.any(
        (run) => offset >= run.sourceStart && offset <= run.sourceEnd,
      ),
    );
    if (lineIndex < 0) lineIndex = delta < 0 ? current.lines.length - 1 : 0;
    final target = lineIndex + delta;
    if (target < 0 || target >= current.lines.length) return null;
    final line = current.lines[target];
    return line.runs.isEmpty ? null : line.runs.first.sourceStart;
  }
}

enum _SelectionMove { previous, next, up, down }

final class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}

final class _CopySelectionIntent extends Intent {
  const _CopySelectionIntent();
}

final class _ExtendSelectionIntent extends Intent {
  const _ExtendSelectionIntent(this.move);

  final _SelectionMove move;
}

const Map<ShortcutActivator, Intent> _documentSelectionShortcuts =
    <ShortcutActivator, Intent>{
      CharacterActivator('a', control: true): _SelectAllIntent(),
      CharacterActivator('a', meta: true): _SelectAllIntent(),
      CharacterActivator('c', control: true): _CopySelectionIntent(),
      CharacterActivator('c', meta: true): _CopySelectionIntent(),
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
          _ExtendSelectionIntent(_SelectionMove.previous),
      SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
          _ExtendSelectionIntent(_SelectionMove.next),
      SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
          _ExtendSelectionIntent(_SelectionMove.up),
      SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
          _ExtendSelectionIntent(_SelectionMove.down),
    };

final class _DocumentViewState extends State<DocumentView>
    with FocusNodeOwnerStateMixin<DocumentView> {
  final _metrics = _DocumentMetrics();
  TextSelection? _selection;
  int _scrollX = 0;
  int _scrollY = 0;
  bool _dragging = false;

  void _jumpToLine(int line) {
    final target = _metrics.layout == null
        ? line
        : line.clamp(0, _metrics.maxScrollY);
    if (target == _scrollY) return;
    setState(() => _scrollY = target);
    widget.onVisibleLineChanged?.call(target);
  }

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(_jumpToLine);
  }

  @override
  void didUpdateWidget(DocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller?._detach(_jumpToLine);
      widget.controller?._attach(_jumpToLine);
    }
    if (widget.plainText != oldWidget.plainText) {
      final selection = _selection;
      if (selection != null && selection.end > widget.plainText.length) {
        _setSelection(null);
      }
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(_jumpToLine);
    super.dispose();
  }

  SelectedText? get _selectedText {
    final selection = _selection;
    if (selection == null || selection.isCollapsed) return null;
    return SelectedText(
      selection: selection,
      text: widget.plainText.substring(selection.start, selection.end),
    );
  }

  void _setSelection(TextSelection? selection) {
    if (_selection == selection) return;
    setState(() => _selection = selection);
    widget.onSelectionChanged?.call(_selectedText);
  }

  bool _scrollTo({int? x, int? y}) {
    final nextX = (x ?? _scrollX).clamp(0, _metrics.maxScrollX);
    final nextY = (y ?? _scrollY).clamp(0, _metrics.maxScrollY);
    if (nextX == _scrollX && nextY == _scrollY) return false;
    final visibleLineChanged = nextY != _scrollY;
    setState(() {
      _scrollX = nextX;
      _scrollY = nextY;
    });
    if (visibleLineChanged) widget.onVisibleLineChanged?.call(nextY);
    return true;
  }

  KeyEventResult _scrollResult({int? x, int? y}) =>
      _scrollTo(x: x, y: y) ? KeyEventResult.handled : KeyEventResult.ignored;

  void _extendSelection(
    DocumentSelectionScope? scope,
    int Function(int offset) move,
  ) {
    final selection = scope?.selection ?? _selection;
    final base = selection?.baseOffset ?? scope?.sourceBase ?? 0;
    final extent = selection?.extentOffset ?? base;
    final textLength = scope?.documentText.length ?? widget.plainText.length;
    _setEffectiveSelection(
      scope,
      TextSelection(
        baseOffset: base,
        extentOffset: move(extent).clamp(0, textLength),
        isDirectional: true,
      ),
    );
  }

  SelectedText? _selectedTextFor(DocumentSelectionScope? scope) =>
      scope?.selectedText ?? _selectedText;

  void _setEffectiveSelection(
    DocumentSelectionScope? scope,
    TextSelection? selection,
  ) {
    if (scope == null) {
      _setSelection(selection);
    } else {
      scope.onSelectionChanged(selection);
    }
  }

  Map<Type, Action<Intent>> _actions({
    required bool handlesScrolling,
    required bool handlesHorizontalScrolling,
    required DocumentSelectionScope? selectionScope,
  }) => <Type, Action<Intent>>{
    _SelectAllIntent: CallbackAction<_SelectAllIntent>((intent, context) {
      if (!widget.selectable) return KeyEventResult.ignored;
      final text = selectionScope?.documentText ?? widget.plainText;
      if (text.isNotEmpty) {
        _setEffectiveSelection(
          selectionScope,
          TextSelection(baseOffset: 0, extentOffset: text.length),
        );
      }
      return KeyEventResult.handled;
    }),
    _CopySelectionIntent: CallbackAction<_CopySelectionIntent>((
      intent,
      context,
    ) {
      if (!widget.selectable) return KeyEventResult.ignored;
      if (selectionScope != null) {
        return selectionScope.copySelection(context);
      }
      final selected = _selectedTextFor(selectionScope);
      if (selected == null) return KeyEventResult.ignored;
      final success = context.owner.copyToClipboard(selected.text);
      widget.onCopy?.call(selected, success: success);
      return KeyEventResult.handled;
    }),
    DismissIntent: CallbackAction<DismissIntent>((intent, context) {
      if (!widget.selectable) return KeyEventResult.ignored;
      if (_selectedTextFor(selectionScope) == null) {
        return KeyEventResult.ignored;
      }
      _setEffectiveSelection(selectionScope, null);
      return KeyEventResult.handled;
    }),
    _ExtendSelectionIntent: CallbackAction<_ExtendSelectionIntent>((
      intent,
      context,
    ) {
      if (!widget.selectable) return KeyEventResult.ignored;
      final text = selectionScope?.documentText ?? widget.plainText;
      switch (intent.move) {
        case _SelectionMove.previous:
          _extendSelection(
            selectionScope,
            (offset) => _previousTextBoundary(text, offset),
          );
        case _SelectionMove.next:
          _extendSelection(
            selectionScope,
            (offset) => _nextTextBoundary(text, offset),
          );
        case _SelectionMove.up:
          _extendSelection(selectionScope, (offset) {
            final sourceBase = selectionScope?.sourceBase ?? 0;
            final local = (offset - sourceBase).clamp(
              0,
              widget.plainText.length,
            );
            final moved = _metrics.offsetOneVisualLine(local, -1);
            if (moved != null) return sourceBase + moved;
            return selectionScope == null
                ? offset
                : _previousSourceLine(text, offset);
          });
        case _SelectionMove.down:
          _extendSelection(selectionScope, (offset) {
            final sourceBase = selectionScope?.sourceBase ?? 0;
            final local = (offset - sourceBase).clamp(
              0,
              widget.plainText.length,
            );
            final moved = _metrics.offsetOneVisualLine(local, 1);
            if (moved != null) return sourceBase + moved;
            return selectionScope == null
                ? offset
                : _nextSourceLine(text, offset);
          });
      }
      return KeyEventResult.handled;
    }),
    if (handlesScrolling) ...<Type, Action<Intent>>{
      ScrollUpIntent: CallbackAction<ScrollUpIntent>(
        (intent, context) => _scrollResult(y: _scrollY - 1),
      ),
      ScrollDownIntent: CallbackAction<ScrollDownIntent>(
        (intent, context) => _scrollResult(y: _scrollY + 1),
      ),
      ScrollPageUpIntent: CallbackAction<ScrollPageUpIntent>(
        (intent, context) =>
            _scrollResult(y: _scrollY - math.max(1, _metrics.viewportHeight)),
      ),
      ScrollPageDownIntent: CallbackAction<ScrollPageDownIntent>(
        (intent, context) =>
            _scrollResult(y: _scrollY + math.max(1, _metrics.viewportHeight)),
      ),
      ScrollToStartIntent: CallbackAction<ScrollToStartIntent>(
        (intent, context) => _scrollResult(x: 0, y: 0),
      ),
      ScrollToEndIntent: CallbackAction<ScrollToEndIntent>(
        (intent, context) => _scrollResult(y: _metrics.maxScrollY),
      ),
    },
    if (handlesHorizontalScrolling) ...<Type, Action<Intent>>{
      ScrollLeftIntent: CallbackAction<ScrollLeftIntent>((intent, context) {
        if (widget.wrap) return KeyEventResult.ignored;
        return _scrollResult(x: _scrollX - 1);
      }),
      ScrollRightIntent: CallbackAction<ScrollRightIntent>((intent, context) {
        if (widget.wrap) return KeyEventResult.ignored;
        return _scrollResult(x: _scrollX + 1);
      }),
    },
  };

  Map<ShortcutActivator, Intent> _shortcuts({
    required bool handlesScrolling,
    required bool handlesHorizontalScrolling,
  }) => <ShortcutActivator, Intent>{
    ..._documentSelectionShortcuts,
    if (handlesScrolling) ...const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.arrowUp): ScrollUpIntent(),
      SingleActivator(LogicalKeyboardKey.arrowDown): ScrollDownIntent(),
      SingleActivator(LogicalKeyboardKey.pageUp): ScrollPageUpIntent(),
      SingleActivator(LogicalKeyboardKey.pageDown): ScrollPageDownIntent(),
      SingleActivator(LogicalKeyboardKey.home): ScrollToStartIntent(),
      SingleActivator(LogicalKeyboardKey.end): ScrollToEndIntent(),
    },
    if (handlesHorizontalScrolling) ...const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.arrowLeft): ScrollLeftIntent(),
      SingleActivator(LogicalKeyboardKey.arrowRight): ScrollRightIntent(),
    },
  };

  void _pointerDown(MouseEvent event, DocumentSelectionScope? selectionScope) {
    if (event.button != MouseButton.left) return;
    if (!focusNode.hasFocus) focusNode.requestFocus();
    final offset = _metrics.sourceOffsetAt(
      event.localPosition,
      _scrollX,
      _scrollY,
    );
    widget.onPointerDownOffset?.call(offset);
    if (!widget.selectable) return;
    if (selectionScope == null) {
      _dragging = true;
    } else {
      selectionScope.onDraggingChanged(dragging: true);
    }
    _setEffectiveSelection(
      selectionScope,
      TextSelection.collapsed(
        offset: offset + (selectionScope?.sourceBase ?? 0),
      ),
    );
  }

  void _pointerMove(MouseEvent event, DocumentSelectionScope? selectionScope) {
    if (!(_dragging || (selectionScope?.dragging ?? false)) ||
        !widget.selectable) {
      return;
    }
    final selection = selectionScope?.selection ?? _selection;
    if (selection == null) return;
    final offset = _metrics.sourceOffsetAt(
      event.localPosition,
      _scrollX,
      _scrollY,
    );
    _setEffectiveSelection(
      selectionScope,
      TextSelection(
        baseOffset: selection.baseOffset,
        extentOffset: offset + (selectionScope?.sourceBase ?? 0),
        isDirectional: true,
      ),
    );
  }

  void _pointerUp(MouseEvent event, DocumentSelectionScope? selectionScope) {
    if (!(_dragging || (selectionScope?.dragging ?? false))) return;
    _pointerMove(event, selectionScope);
    if (selectionScope == null) {
      _dragging = false;
    } else {
      selectionScope.onDraggingChanged(dragging: false);
    }
  }

  void _pointerScroll(MouseEvent event) {
    final scroll = event.scroll;
    if (event.type != MouseEventType.scroll || scroll == null) return;
    final delta = scroll.direction == MouseScrollDirection.up ? -1 : 1;
    if (scroll.direction == MouseScrollDirection.up ||
        scroll.direction == MouseScrollDirection.down) {
      if (_scrollTo(y: _scrollY + delta * scroll.magnitude)) {
        event.consume();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectionScope = DocumentSelectionScope.maybeOf(context);
    final selection = selectionScope == null
        ? _selection
        : selectionScope.selectionForBlock(widget.plainText.length);
    final handlesScrolling = DocumentScrollScope.handlesScrollingOf(context);
    final handlesHorizontalScrolling =
        DocumentScrollScope.handlesHorizontalScrollingOf(context);
    return Shortcuts(
      shortcuts: _shortcuts(
        handlesScrolling: handlesScrolling,
        handlesHorizontalScrolling: handlesHorizontalScrolling,
      ),
      child: Actions(
        actions: _actions(
          handlesScrolling: handlesScrolling,
          handlesHorizontalScrolling: handlesHorizontalScrolling,
          selectionScope: selectionScope,
        ),
        child: Focus(
          focusNode: focusNode,
          autofocus: widget.autofocus,
          child: PointerListener(
            onPointerDown: (event) => _pointerDown(event, selectionScope),
            onPointerMove: (event) => _pointerMove(event, selectionScope),
            onPointerUp: (event) => _pointerUp(event, selectionScope),
            onPointerScroll: _pointerScroll,
            child: _DocumentLeaf(
              text: widget.text,
              plainText: widget.plainText,
              wrap: widget.wrap,
              showLineNumbers: widget.showLineNumbers,
              lineNumberStyle: widget.lineNumberStyle,
              selection: selection == null || selection.isCollapsed
                  ? null
                  : TextHighlight(
                      start: selection.start,
                      end: selection.end,
                      foregroundColor: widget.selectionForegroundColor,
                      backgroundColor: widget.selectionBackgroundColor,
                    ),
              scrollX: _scrollX,
              scrollY: _scrollY,
              metrics: _metrics,
              backgroundColor: theme.surface,
            ),
          ),
        ),
      ),
    );
  }
}

int _previousTextBoundary(String text, int offset) {
  final indexMap = TextIndexMap(text);
  final end = indexMap.graphemeToUtf16(indexMap.graphemeCount);
  final clamped = offset.clamp(0, end);
  if (clamped <= 0) return 0;
  final index = indexMap.utf16ToGrapheme(clamped);
  if (indexMap.graphemeToUtf16(index) == clamped) {
    return indexMap.graphemeToUtf16(index - 1);
  }
  return indexMap.graphemeToUtf16(index);
}

int _nextTextBoundary(String text, int offset) {
  final indexMap = TextIndexMap(text);
  final end = indexMap.graphemeToUtf16(indexMap.graphemeCount);
  final clamped = offset.clamp(0, end);
  if (clamped >= end) return end;
  return indexMap.graphemeToUtf16(indexMap.utf16ToGrapheme(clamped) + 1);
}

int _sourceLineStart(String text, int offset) {
  final clamped = offset.clamp(0, text.length);
  if (clamped == 0) return 0;
  if (clamped > 0 && text.codeUnitAt(clamped - 1) == 0x0a) return clamped;
  return text.lastIndexOf('\n', clamped - 1) + 1;
}

int _previousSourceLine(String text, int offset) {
  final currentStart = _sourceLineStart(text, offset);
  if (currentStart <= 1) return 0;
  return text.lastIndexOf('\n', currentStart - 2) + 1;
}

int _nextSourceLine(String text, int offset) {
  final currentStart = _sourceLineStart(text, offset);
  final newline = text.indexOf('\n', currentStart);
  return newline < 0 ? text.length : newline + 1;
}

final class _DocumentLeaf extends RenderObjectWidget {
  const _DocumentLeaf({
    required this.text,
    required this.plainText,
    required this.wrap,
    required this.showLineNumbers,
    required this.lineNumberStyle,
    required this.selection,
    required this.scrollX,
    required this.scrollY,
    required this.metrics,
    required this.backgroundColor,
  });

  final InlineSpan text;
  final String plainText;
  final bool wrap;
  final bool showLineNumbers;
  final TextStyle lineNumberStyle;
  final TextHighlight? selection;
  final int scrollX;
  final int scrollY;
  final _DocumentMetrics metrics;
  final Color backgroundColor;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderDocument(
    text: text,
    plainText: plainText,
    wrap: wrap,
    showLineNumbers: showLineNumbers,
    lineNumberStyle: lineNumberStyle,
    selection: selection,
    scrollX: scrollX,
    scrollY: scrollY,
    metrics: metrics,
    backgroundColor: backgroundColor,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderDocument renderObject) {
    renderObject.updateFrom(this);
  }
}

final class _RenderDocument extends RenderBox {
  _RenderDocument({
    required InlineSpan text,
    required String plainText,
    required bool wrap,
    required bool showLineNumbers,
    required TextStyle lineNumberStyle,
    required TextHighlight? selection,
    required int scrollX,
    required int scrollY,
    required _DocumentMetrics metrics,
    required Color backgroundColor,
  }) : _text = snapshotInlineSpan(text),
       _plainText = plainText,
       _wrap = wrap,
       _showLineNumbers = showLineNumbers,
       _lineNumberStyle = lineNumberStyle,
       _selection = selection,
       _scrollX = scrollX,
       _scrollY = scrollY,
       _metrics = metrics,
       _backgroundColor = backgroundColor;

  InlineSpan _text;
  String _plainText;
  bool _wrap;
  bool _showLineNumbers;
  TextStyle _lineNumberStyle;
  TextHighlight? _selection;
  int _scrollX;
  int _scrollY;
  _DocumentMetrics _metrics;
  Color _backgroundColor;
  late TextLayout _layout;

  void updateFrom(_DocumentLeaf widget) {
    _text = snapshotInlineSpan(widget.text);
    _plainText = widget.plainText;
    _wrap = widget.wrap;
    _showLineNumbers = widget.showLineNumbers;
    _lineNumberStyle = widget.lineNumberStyle;
    _selection = widget.selection;
    _scrollX = widget.scrollX;
    _scrollY = widget.scrollY;
    _metrics = widget.metrics;
    _backgroundColor = widget.backgroundColor;
    markNeedsLayout();
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final sourceLines = math.max(1, '\n'.allMatches(_plainText).length + 1);
    final gutter = _showLineNumbers ? sourceLines.toString().length + 2 : 0;
    final availableWidth = constraints.maxWidth == null
        ? null
        : math.max(1, constraints.maxWidth! - gutter);
    _layout = const TextLayoutEngine().layout(
      _text,
      BoxConstraints(maxWidth: _wrap ? availableWidth : null),
    );
    final naturalWidth = gutter + _layout.maxLineWidth;
    final naturalHeight = _layout.lineCount;
    size = Size(
      constraints.constrainWidth(constraints.maxWidth ?? naturalWidth),
      constraints.constrainHeight(constraints.maxHeight ?? naturalHeight),
    );
    _metrics
      ..layout = _layout
      ..gutterWidth = gutter
      ..viewportWidth = math.max(0, size.width - gutter)
      ..viewportHeight = size.height
      ..maxScrollX = math.max(0, _layout.maxLineWidth - (size.width - gutter))
      ..maxScrollY = math.max(0, _layout.lineCount - size.height);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = offset + Offset(x, y);
    context.canvas.fillRect(origin & size, _backgroundColor);
    final scrollY = _scrollY.clamp(0, _metrics.maxScrollY);
    final scrollX = _scrollX.clamp(0, _metrics.maxScrollX);
    if (_showLineNumbers) {
      _paintGutter(context, origin, scrollY);
    }
    final gutter = _metrics.gutterWidth;
    context.canvas.drawTextLayout(
      _layout,
      Offset(origin.dx + gutter, origin.dy),
      sourceRect: Rect.fromLTWH(
        scrollX,
        scrollY,
        math.max(0, size.width - gutter),
        size.height,
      ),
      selection: _selection,
    );
  }

  void _paintGutter(PaintingContext context, Offset origin, int scrollY) {
    var previousSourceLine = -1;
    for (var viewportY = 0; viewportY < size.height; viewportY++) {
      final visualLine = scrollY + viewportY;
      if (visualLine >= _layout.lines.length) break;
      final line = _layout.lines[visualLine];
      final offset = line.runs.isEmpty ? 0 : line.runs.first.sourceStart;
      final sourceLine = '\n'
          .allMatches(_plainText.substring(0, offset))
          .length;
      final label = sourceLine == previousSourceLine
          ? ''
          : '${sourceLine + 1}'.padLeft(_metrics.gutterWidth - 1);
      previousSourceLine = sourceLine;
      context.canvas.drawText(
        '$label ',
        Offset(origin.dx, origin.dy + viewportY),
        _lineNumberStyle.color,
        background: _lineNumberStyle.backgroundColor,
        attributes: _lineNumberStyle.computedAttributes,
      );
    }
  }
}
