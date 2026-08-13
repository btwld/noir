import '../render/geometry.dart';
import 'box.dart';
import 'object.dart';

/// Internal root render object for terminal-sized frames.
final class RenderView extends RenderBox with RenderObjectWithSingleChild {
  /// Creates a render view with an initial terminal size.
  RenderView({int width = 0, int height = 0})
    : _width = _validateExtent(width, 'width'),
      _height = _validateExtent(height, 'height');

  int _width;
  int _height;

  /// Tight constraints matching the current terminal size.
  BoxConstraints get terminalConstraints =>
      BoxConstraints.tight(width: _width, height: _height);

  /// Update the terminal size used for root layout.
  void updateTerminalSize(int width, int height) {
    _validateExtent(width, 'width');
    _validateExtent(height, 'height');
    if (_width == width && _height == height) {
      return;
    }
    _width = width;
    _height = height;
    markNeedsLayout();
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    super.performBoxLayout(constraints);

    final child = this.child;
    if (child == null) {
      return;
    }

    child.layout(constraints);
    if (child is RenderBox) {
      child
        ..x = 0
        ..y = 0;
    }
  }

  static int _validateExtent(int value, String name) {
    if (value < 0) {
      throw ArgumentError.value(value, name, 'must be non-negative');
    }
    return value;
  }
}
