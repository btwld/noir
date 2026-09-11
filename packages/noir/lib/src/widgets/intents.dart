/// Base class for semantic input commands.
abstract class Intent {
  /// Adds no base payload; action lookup keys concrete intents by runtime type.
  const Intent();
}

/// Activates the currently focused control.
class ActivateIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const ActivateIntent();
}

/// Dismisses the current interaction.
class DismissIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const DismissIntent();
}

/// Moves focus to the next focusable node.
class NextFocusIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const NextFocusIntent();
}

/// Moves focus to the previous focusable node.
class PreviousFocusIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const PreviousFocusIntent();
}

/// Moves a selection one item up.
class MoveSelectionUpIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const MoveSelectionUpIntent();
}

/// Moves a selection one item down.
class MoveSelectionDownIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const MoveSelectionDownIntent();
}

/// Moves a selection by one page up.
class MoveSelectionPageUpIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const MoveSelectionPageUpIntent();
}

/// Moves a selection by one page down.
class MoveSelectionPageDownIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const MoveSelectionPageDownIntent();
}

/// Moves a selection to the first item.
class MoveSelectionFirstIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const MoveSelectionFirstIntent();
}

/// Moves a selection to the last item.
class MoveSelectionLastIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const MoveSelectionLastIntent();
}

/// Scrolls up.
class ScrollUpIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const ScrollUpIntent();
}

/// Scrolls down.
class ScrollDownIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const ScrollDownIntent();
}

/// Scrolls left.
class ScrollLeftIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const ScrollLeftIntent();
}

/// Scrolls right.
class ScrollRightIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const ScrollRightIntent();
}

/// Scrolls one page up.
class ScrollPageUpIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const ScrollPageUpIntent();
}

/// Scrolls one page down.
class ScrollPageDownIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const ScrollPageDownIntent();
}

/// Scrolls to the beginning.
class ScrollToStartIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const ScrollToStartIntent();
}

/// Scrolls to the end.
class ScrollToEndIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const ScrollToEndIntent();
}

/// Inserts text into an editable control.
class InsertTextIntent extends Intent {
  /// Carries the exact [text] requested for insertion.
  const InsertTextIntent(this.text);

  /// Text to insert.
  final String text;
}

/// Deletes the character before the cursor.
class DeleteBackwardIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const DeleteBackwardIntent();
}

/// Deletes the character after the cursor.
class DeleteForwardIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const DeleteForwardIntent();
}

/// Moves the caret left.
class MoveCaretLeftIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const MoveCaretLeftIntent();
}

/// Moves the caret right.
class MoveCaretRightIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const MoveCaretRightIntent();
}

/// Moves the caret up.
class MoveCaretUpIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const MoveCaretUpIntent();
}

/// Moves the caret down.
class MoveCaretDownIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const MoveCaretDownIntent();
}

/// Moves the caret to the current line start.
class MoveCaretLineStartIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const MoveCaretLineStartIntent();
}

/// Moves the caret to the current line end.
class MoveCaretLineEndIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const MoveCaretLineEndIntent();
}

/// Moves the caret to the document start.
class MoveCaretDocumentStartIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const MoveCaretDocumentStartIntent();
}

/// Moves the caret to the document end.
class MoveCaretDocumentEndIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const MoveCaretDocumentEndIntent();
}

/// Submits an editable control.
class SubmitTextIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const SubmitTextIntent();
}

/// Inserts a tab/indentation into an editable control.
class InsertTabIntent extends Intent {
  /// Carries no payload; action lookup resolves it by runtime type.
  const InsertTabIntent();
}
