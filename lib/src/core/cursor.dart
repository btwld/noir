import '../foundation/disposable.dart';
import 'color.dart';
import 'renderer.dart';

/// Cursor styles supported by terminals
enum CursorStyle {
  /// Block cursor shape.
  block(0),

  /// Underline cursor shape.
  underline(2),

  /// Vertical bar cursor shape.
  bar(1);

  const CursorStyle(this.value);

  /// Canonical OpenTUI cursor-style tag.
  final int value;
}

/// Cursor-management methods added to [Renderer].
extension CursorManagement on Renderer {
  /// Set cursor position and visibility.
  ///
  /// Dart render coordinates are zero-based terminal cells. OpenTUI's native
  /// cursor API follows ANSI cursor coordinates and is one-based, so convert
  /// at this boundary.
  void setCursorPosition(int x, int y, {bool visible = true}) {
    bindings.setCursorPosition(handle, x + 1, y + 1, visible);
  }

  /// Sets the cursor [style] and whether it blinks.
  void setCursorStyle(CursorStyle style, {bool blinking = false}) {
    bindings.setCursorStyle(handle, style.value, blinking);
  }

  /// Sets the terminal cursor color.
  void setCursorColor(Color color) {
    bindings.setCursorColor(handle, color);
  }

  /// Hides the cursor by setting it invisible at position (0, 0).
  void hideCursor() {
    setCursorPosition(0, 0, visible: false);
  }
}

/// Centralised cursor coordination for focusable widgets.
class CursorController implements Disposable {
  Renderer? _renderer;
  Object? _owner;
  int _x = 0;
  int _y = 0;
  CursorStyle _style = CursorStyle.block;
  Color _color = Color.white;

  bool _blinking = true;
  bool _visible = false;

  /// Attaches [renderer] so subsequent cursor updates are forwarded to it.
  void attachRenderer(Renderer renderer) {
    _renderer = renderer;
    if (_visible) {
      _applyCursor();
    }
  }

  /// Detaches the current renderer and hides the cursor.
  void detachRenderer() {
    _hideCursor();
    _renderer = null;
  }

  /// Shows the cursor at (x, y) on behalf of [owner], applying style, color, and blinking.
  void showCursor(
    Object owner,
    int x,
    int y, {
    CursorStyle style = CursorStyle.block,
    Color? color,
    bool blinking = true,
  }) {
    _owner = owner;
    _x = x;
    _y = y;
    _style = style;
    if (color != null) {
      _color = color;
    }
    _blinking = blinking;
    _visible = true;
    _applyCursor();
  }

  /// Hides the cursor if [owner] currently owns it; ignores the call otherwise.
  void hideCursorFor(Object owner) {
    if (_owner == owner) {
      _hideCursor();
      _owner = null;
    }
  }

  /// Hides the cursor unconditionally, regardless of owner.
  void hideCursor() {
    _hideCursor();
    _owner = null;
  }

  /// Updates the cursor position to (x, y) if [owner] currently owns the cursor.
  void updatePosition(Object owner, int x, int y) {
    if (_owner != owner) return;
    _x = x;
    _y = y;
    if (_visible) {
      _applyCursor();
    }
  }

  /// Whether the cursor is currently visible.
  bool get isVisible => _visible;

  /// The object that currently owns the cursor, or null when no owner has claimed it.
  Object? get owner => _owner;

  /// Current cursor column (zero-based).
  int get x => _x;

  /// Current cursor row (zero-based).
  int get y => _y;

  /// Active cursor shape.
  CursorStyle get style => _style;

  /// Active cursor color.
  Color get color => _color;

  /// Whether the cursor is set to blink.
  bool get blinking => _blinking;

  @override
  void dispose() {
    hideCursor();
    detachRenderer();
  }

  void _applyCursor() {
    final renderer = _renderer;
    if (renderer == null) return;
    renderer.setCursorStyle(_style, blinking: _blinking);
    renderer.setCursorColor(_color);
    renderer.setCursorPosition(_x, _y);
  }

  void _hideCursor() {
    if (!_visible) return;
    _renderer?.hideCursor();
    _visible = false;
  }
}
