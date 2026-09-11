/// Mouse pointer shapes requested from terminals supporting OSC 22.
///
/// This controls the desktop pointer, independently of the text caret.
/// Unsupported terminals retain their own pointer appearance.
enum MouseCursor {
  /// Standard arrow pointer.
  basic,

  /// Pointing hand for an enabled action.
  pointer,

  /// I-beam for text interaction.
  text,
}
