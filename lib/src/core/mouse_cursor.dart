/// Mouse pointer shapes requested from terminals supporting OSC 22.
///
/// This controls the desktop pointer, independently of the text caret.
/// Unsupported terminals retain their own pointer appearance.
enum MouseCursor {
  /// Standard arrow pointer.
  basic('default'),

  /// Pointing hand for an enabled action.
  pointer('pointer'),

  /// I-beam for text interaction.
  text('text');

  const MouseCursor(this.name);

  /// Shape name defined by the OSC 22 pointer protocol.
  final String name;
}
