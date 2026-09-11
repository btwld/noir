import '../render/geometry.dart';
import 'tui_canvas.dart';

/// A description of a box decoration (a decoration applied to a [Rect]).
///
/// See [BoxDecoration] for the supported solid background and border
/// implementation.
///
/// Decorations paint within the supplied terminal-cell rectangle.
abstract class Decoration {
  /// Initializes fields for subclasses.
  const Decoration();

  /// Returns the insets to apply when using this decoration.
  ///
  /// For example, if the decoration draws a border, the padding would return
  /// the width of the border on each side.
  ///
  /// This is used by [Container] to automatically provide padding that accounts
  /// for the border.
  EdgeInsets? get padding => null;

  /// Paints the decoration on [canvas] within the terminal-cell [rect].
  void paint(TuiCanvas canvas, Rect rect);

  @override
  String toString() => 'Decoration()';
}
