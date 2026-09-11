import 'renderer.dart';

/// OSC 52 clipboard selection targeted by terminal copy and clear operations.
enum TerminalClipboardTarget {
  /// The ordinary system clipboard.
  clipboard,

  /// The terminal's primary selection.
  primary,

  /// The terminal's select buffer.
  select,

  /// The terminal's secondary selection.
  secondary,
}

/// Low-level OSC 52 clipboard operations owned by a live [Renderer].
extension ClipboardSupport on Renderer {
  /// Requests an explicit copy of [text], reporting whether OpenTUI wrote it.
  bool copyToClipboard(
    String text, {
    TerminalClipboardTarget target = TerminalClipboardTarget.clipboard,
  }) {
    if (text.isEmpty) return false;
    return bindings.copyToClipboardOSC52(handle, target.index, text);
  }

  /// Requests that [target] be cleared, reporting whether OpenTUI wrote it.
  bool clearClipboard({
    TerminalClipboardTarget target = TerminalClipboardTarget.clipboard,
  }) => bindings.clearClipboardOSC52(handle, target.index);
}
