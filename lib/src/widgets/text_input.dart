// ignore_for_file: avoid_setters_without_getters
import 'package:characters/characters.dart';

import '../core/color.dart';
import '../core/cursor.dart';
import '../core/grapheme_metrics.dart';
import '../foundation/listenable.dart';
import '../foundation/text_editing_controller.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/box.dart';
import '../rendering/object.dart';
import 'actions.dart';
import 'focus.dart';
import 'focus_node_owner_mixin.dart';
import 'pointer_listener.dart';
import 'shortcuts.dart';
import 'text_editing_owner_mixin.dart';
import 'text_input_connection.dart';
import 'theme.dart';

/// A text input widget with cursor support.
///
/// [controller], `value`, `placeholder`, and `onChanged` always hold the
/// user's RAW text — the [obscureText] flag only affects what is painted to
/// the buffer.
class TextInput extends StatefulWidget {
  /// Configures a single-line editor; [controller] and [value] are exclusive.
  const TextInput({
    this.controller,
    this.value,
    this.placeholder,
    this.color,
    this.backgroundColor,
    this.cursorColor,
    this.cursorStyle = CursorStyle.block,
    this.obscureText = false,
    this.obscuringCharacter = '*',
    this.maxLength = 100,
    this.onChanged,
    this.onSubmit,
    this.focusNode,
    this.autofocus = false,
    super.key,
  }) : assert(
         controller == null || value == null,
         'TextInput cannot be given both controller and value.',
       );

  /// The controller that owns this field's text and selection.
  final TextEditingController? controller;

  /// Initial/current value when [controller] is not supplied.
  final String? value;

  /// Dimmed hint text shown when the field is empty.
  final String? placeholder;

  /// Foreground color of the text. Falls back to [ThemeData.text].
  final Color? color;

  /// Fill color painted behind the field. Falls back to [ThemeData.surface]
  /// under a [Theme]; with neither, the field paints no fill. Pass
  /// [Color.transparent] for an explicitly unfilled field inside a themed
  /// subtree.
  final Color? backgroundColor;

  /// Color of the cursor. Falls back to [ThemeData.cursor].
  final Color? cursorColor;

  /// Shape drawn for the cursor. Defaults to [CursorStyle.block].
  final CursorStyle cursorStyle;

  /// When true, paint each grapheme of [value] as [obscuringCharacter]
  /// without modifying the stored text. `onChanged` still receives the
  /// raw user input.
  final bool obscureText;

  /// Single grapheme cluster used to replace each visible cluster when
  /// [obscureText] is true. Defaults to `'*'`.
  final String obscuringCharacter;

  /// Maximum number of characters accepted. Defaults to 100.
  final int maxLength;

  /// Called whenever the text value changes.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits the current text value.
  final VoidCallback? onSubmit;

  /// Focus node controlling this field's focus. One is created if null.
  final FocusNode? focusNode;

  /// Whether the field requests focus when first mounted. Defaults to false.
  final bool autofocus;

  @override
  State<TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<TextInput>
    with
        FocusNodeOwnerStateMixin<TextInput>,
        TextEditingOwnerStateMixin<TextInput> {
  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  TextEditingController? get widgetController => widget.controller;

  @override
  String? get widgetValue => widget.value;

  @override
  void initState() {
    super.initState();
    _validateObscuringCharacter(widget.obscuringCharacter);
    initController();
  }

  @override
  void didUpdateWidget(TextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    _validateObscuringCharacter(widget.obscuringCharacter);
    syncFocusNode(oldWidget.focusNode);
    syncController(oldWidget.controller, oldWidget.value);
  }

  @override
  TextInputConnection get connection => TextInputConnection(
    controller: controller,
    allowNewline: false,
    allowTab: false,
    maxLength: widget.maxLength,
    onChanged: widget.onChanged,
    onSubmit: widget.onSubmit,
  );

  @override
  Widget build(BuildContext context) {
    requireUsableSelectionForBuild();
    final conn = connection;
    final theme = Theme.maybeOf(context);
    final palette = theme ?? ThemeData.dark;
    return Shortcuts(
      shortcuts: conn.shortcuts,
      child: Actions(
        actions: conn.actions,
        child: Focus(
          focusNode: focusNode,
          autofocus: widget.autofocus,
          onFocusChange: handleFocusChange,
          child: PointerListener(
            onPointerDown: handlePointerDown,
            child: _TextInputLeaf(
              value: controller.text,
              placeholder: widget.placeholder,
              color: widget.color ?? palette.text,
              // `theme?.surface`, not `palette.surface`: with no ancestor
              // Theme the field must keep painting no fill at all, which no
              // color can express.
              backgroundColor: widget.backgroundColor ?? theme?.surface,
              cursorColor: widget.cursorColor ?? palette.cursor,
              cursorStyle: widget.cursorStyle,
              cursorPosition: controller.col,
              focused: focusNode.hasFocus,
              obscureText: widget.obscureText,
              obscuringCharacter: widget.obscuringCharacter,
            ),
          ),
        ),
      ),
    );
  }
}

class _TextInputLeaf extends RenderObjectWidget {
  const _TextInputLeaf({
    required this.value,
    required this.color,
    required this.cursorColor,
    required this.cursorStyle,
    required this.cursorPosition,
    required this.focused,
    required this.obscureText,
    required this.obscuringCharacter,
    this.placeholder,
    this.backgroundColor,
  });
  final String value;
  final String? placeholder;
  final Color color;
  final Color? backgroundColor;
  final Color cursorColor;
  final CursorStyle cursorStyle;

  /// Grapheme-cluster index into [value] where the cursor sits.
  final int cursorPosition;
  final bool focused;
  final bool obscureText;
  final String obscuringCharacter;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderTextInput(
    cursorController: context.owner.cursorController,
    value: value,
    placeholder: placeholder,
    color: color,
    backgroundColor: backgroundColor,
    cursorColor: cursorColor,
    cursorStyle: cursorStyle,
    cursorPosition: cursorPosition,
    focused: focused,
    obscureText: obscureText,
    obscuringCharacter: obscuringCharacter,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderTextInput renderObject,
  ) {
    renderObject
      ..value = value
      ..placeholder = placeholder
      ..color = color
      ..backgroundColor = backgroundColor
      ..cursorColor = cursorColor
      ..cursorStyle = cursorStyle
      ..cursorPosition = cursorPosition
      ..focused = focused
      ..obscureText = obscureText
      ..obscuringCharacter = obscuringCharacter;
  }
}

/// RenderBox for [TextInput]'s leaf. Paints text/placeholder into the buffer
/// and drives cursor visibility through the shared [CursorController].
///
/// When `obscureText` is true, each grapheme cluster in the raw value is
/// painted as `obscuringCharacter`. Cursor X is computed from the raw
/// text width in cells, but since masking replaces each cluster with a
/// single 1-cell character, the cursor lands at a column counted in
/// painted cells (one per cluster) — this matches user expectation for
/// a password field where each input "becomes" one star.
class RenderTextInput extends RenderBox {
  /// Initializes a text leaf from an editing snapshot and borrowed cursor controller.
  RenderTextInput({
    required CursorController cursorController,
    required String value,
    required Color color,
    required Color cursorColor,
    required CursorStyle cursorStyle,
    required int cursorPosition,
    required bool focused,
    required bool obscureText,
    required String obscuringCharacter,
    String? placeholder,
    Color? backgroundColor,
  }) : _cursorController = cursorController,
       _value = value,
       _placeholder = placeholder,
       _color = color,
       _backgroundColor = backgroundColor,
       _cursorColor = cursorColor,
       _cursorStyle = cursorStyle,
       _cursorPosition = cursorPosition,
       _focused = focused,
       _obscureText = obscureText,
       _obscuringCharacter = obscuringCharacter {
    _validateObscuringCharacter(_obscuringCharacter);
  }

  final CursorController _cursorController;
  String _value;
  String? _placeholder;
  Color _color;
  Color? _backgroundColor;
  Color _cursorColor;
  CursorStyle _cursorStyle;
  int _cursorPosition;
  bool _focused;
  bool _obscureText;
  String _obscuringCharacter;

  set value(String v) {
    if (_value == v) return;
    _value = v;
    markNeedsLayout();
  }

  set placeholder(String? v) {
    if (_placeholder == v) return;
    _placeholder = v;
    markNeedsLayout();
  }

  set color(Color v) {
    if (_color == v) return;
    _color = v;
    markNeedsPaint();
  }

  set backgroundColor(Color? v) {
    if (_backgroundColor == v) return;
    _backgroundColor = v;
    markNeedsPaint();
  }

  set cursorColor(Color v) {
    if (_cursorColor == v) return;
    _cursorColor = v;
    markNeedsPaint();
  }

  set cursorStyle(CursorStyle v) {
    if (_cursorStyle == v) return;
    _cursorStyle = v;
    markNeedsPaint();
  }

  set cursorPosition(int v) {
    if (_cursorPosition == v) return;
    _cursorPosition = v;
    markNeedsPaint();
  }

  set focused(bool v) {
    if (_focused == v) return;
    _focused = v;
    markNeedsPaint();
  }

  set obscureText(bool v) {
    if (_obscureText == v) return;
    _obscureText = v;
    markNeedsLayout();
  }

  set obscuringCharacter(String v) {
    _validateObscuringCharacter(v);
    if (_obscuringCharacter == v) return;
    _obscuringCharacter = v;
    markNeedsPaint();
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    // Desired width is the painted cell-width of the text plus one cell of
    // cursor space. When obscured we paint one grapheme per cluster, so
    // the painted width is the cluster count.
    final isEmpty = _value.isEmpty;
    final displayText = isEmpty ? (_placeholder ?? '') : _value;
    final paintedCells = _obscureText && !isEmpty
        ? displayText.characters.length
        : terminalStringWidth(displayText);
    final desiredWidth = paintedCells + 1; // +1 for cursor space
    final w = constraints.constrainWidth(desiredWidth);
    final h = constraints.constrainHeight(1);
    size = Size(w, h);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final targetX = offset.dx + x;
    final targetY = offset.dy + y;
    final canvas = context.canvas;

    final isEmpty = _value.isEmpty;
    final displayRaw = isEmpty ? (_placeholder ?? '') : _value;

    final textColor = !isEmpty
        ? _color
        : Color(_color.r * 0.5, _color.g * 0.5, _color.b * 0.5, _color.a);

    if (_backgroundColor != null) {
      canvas.fillRect(
        Rect.fromLTWH(targetX, targetY, width, height),
        _backgroundColor!,
      );
    }

    // Determine the on-screen sequence of clusters. For password input each
    // user grapheme becomes a single obscuring character (typically 1 cell).
    final visibleClusters = _obscureText && !isEmpty
        ? List<String>.filled(displayRaw.characters.length, _obscuringCharacter)
        : displayRaw.characters.toList();

    // Bring the cursor into the viewport when text overflows. We never
    // animate; we just shift the visible window so the cursor cell stays
    // <= viewport width - 1 (we reserve one cell for the cursor itself).
    // Compute how many clusters to skip from the start so the cursor's
    // painted column ends up within [0, width - 1].
    final cursorCluster = isEmpty ? 0 : _cursorPosition;
    final skipClusters = _computeHorizontalScroll(
      visibleClusters,
      cursorCluster,
      width,
    );

    var paintedCol = 0;
    for (var i = skipClusters; i < visibleClusters.length; i++) {
      final cluster = visibleClusters[i];
      final cw = _obscureText ? 1 : terminalCellWidth(cluster);
      if (paintedCol + cw > width) break;
      // drawText encodes the whole cluster; setCell keeps only its first
      // scalar, which truncates a ZWJ sequence.
      canvas.drawText(
        cluster,
        Offset(targetX + paintedCol, targetY),
        textColor,
        background: _backgroundColor,
      );
      paintedCol += cw;
    }

    if (_focused) {
      // Compute the painted column of the cursor.
      var cursorCol = 0;
      for (
        var i = skipClusters;
        i < cursorCluster && i < visibleClusters.length;
        i++
      ) {
        cursorCol += _obscureText ? 1 : terminalCellWidth(visibleClusters[i]);
      }
      final cursorX = targetX + cursorCol;
      _cursorController.showCursor(
        this,
        cursorX,
        targetY,
        style: _cursorStyle,
        color: _cursorColor,
      );
    } else {
      _cursorController.hideCursorFor(this);
    }
  }

  /// Compute how many clusters to skip from the left so [cursorCluster]
  /// lands within `[0, viewportCells - 1]` after painting. Returns 0 when
  /// the text already fits.
  int _computeHorizontalScroll(
    List<String> clusters,
    int cursorCluster,
    int viewportCells,
  ) {
    if (viewportCells <= 1) return 0;
    if (clusters.isEmpty) return 0;
    // Painted column up to (but not including) cursorCluster.
    var rawCursorCol = 0;
    for (var i = 0; i < cursorCluster && i < clusters.length; i++) {
      rawCursorCol += _obscureText ? 1 : terminalCellWidth(clusters[i]);
    }
    if (rawCursorCol <= viewportCells - 1) return 0;
    // Walk forward from the left until the cursor column fits within
    // viewportCells - 1. Reserve 1 cell for the cursor itself.
    var skip = 0;
    var dropped = 0;
    for (var i = 0; i < cursorCluster && i < clusters.length; i++) {
      final cw = _obscureText ? 1 : terminalCellWidth(clusters[i]);
      if (rawCursorCol - dropped <= viewportCells - 1) break;
      dropped += cw;
      skip++;
    }
    return skip;
  }

  @override
  void detach() {
    _cursorController.hideCursorFor(this);
    super.detach();
  }
}

void _validateObscuringCharacter(String value) {
  if (value.characters.length == 1 && terminalStringWidth(value) == 1) {
    return;
  }
  throw ArgumentError.value(
    value,
    'obscuringCharacter',
    'must be exactly one single-cell grapheme cluster',
  );
}

/// Signature for callbacks that receive a changed value of type [T].
typedef ValueChanged<T> = void Function(T value);
