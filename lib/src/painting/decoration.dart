import '../render/geometry.dart';
import 'tui_canvas.dart';

/// A description of a box decoration (a decoration applied to a [Rect]).
///
/// This class presents the abstract interface for all decorations.
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

  /// Actually paint the decoration to the given location on the given canvas.
  ///
  /// The [rect] argument gives the location on the buffer where to paint the
  /// decoration.
  void paint(TuiCanvas canvas, Rect rect);

  @override
  String toString() => 'Decoration()';
}
