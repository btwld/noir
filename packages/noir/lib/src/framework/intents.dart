// Payload-free constructors have no separate contract: the class doc names
// the command, and Intent documents lookup by runtime type.
// ignore_for_file: public_member_api_docs

/// Base class for semantic input commands.
abstract class Intent {
  /// Adds no base payload; action lookup keys concrete intents by runtime type.
  const Intent();
}

/// Activates the currently focused control.
class ActivateIntent extends Intent {
  const ActivateIntent();
}

/// Dismisses the current interaction.
class DismissIntent extends Intent {
  const DismissIntent();
}

/// Moves focus to the next focusable node.
class NextFocusIntent extends Intent {
  const NextFocusIntent();
}

/// Moves focus to the previous focusable node.
class PreviousFocusIntent extends Intent {
  const PreviousFocusIntent();
}

/// Moves a selection one item up.
class MoveSelectionUpIntent extends Intent {
  const MoveSelectionUpIntent();
}

/// Moves a selection one item down.
class MoveSelectionDownIntent extends Intent {
  const MoveSelectionDownIntent();
}

/// Moves a selection by one page up.
class MoveSelectionPageUpIntent extends Intent {
  const MoveSelectionPageUpIntent();
}

/// Moves a selection by one page down.
class MoveSelectionPageDownIntent extends Intent {
  const MoveSelectionPageDownIntent();
}

/// Moves a selection to the first item.
class MoveSelectionFirstIntent extends Intent {
  const MoveSelectionFirstIntent();
}

/// Moves a selection to the last item.
class MoveSelectionLastIntent extends Intent {
  const MoveSelectionLastIntent();
}

/// Scrolls up.
class ScrollUpIntent extends Intent {
  const ScrollUpIntent();
}

/// Scrolls down.
class ScrollDownIntent extends Intent {
  const ScrollDownIntent();
}

/// Scrolls left.
class ScrollLeftIntent extends Intent {
  const ScrollLeftIntent();
}

/// Scrolls right.
class ScrollRightIntent extends Intent {
  const ScrollRightIntent();
}

/// Scrolls one page up.
class ScrollPageUpIntent extends Intent {
  const ScrollPageUpIntent();
}

/// Scrolls one page down.
class ScrollPageDownIntent extends Intent {
  const ScrollPageDownIntent();
}

/// Scrolls to the beginning.
class ScrollToStartIntent extends Intent {
  const ScrollToStartIntent();
}

/// Scrolls to the end.
class ScrollToEndIntent extends Intent {
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
  const DeleteBackwardIntent();
}

/// Deletes the character after the cursor.
class DeleteForwardIntent extends Intent {
  const DeleteForwardIntent();
}

/// Moves the caret left.
class MoveCaretLeftIntent extends Intent {
  const MoveCaretLeftIntent();
}

/// Moves the caret right.
class MoveCaretRightIntent extends Intent {
  const MoveCaretRightIntent();
}

/// Moves the caret up.
class MoveCaretUpIntent extends Intent {
  const MoveCaretUpIntent();
}

/// Moves the caret down.
class MoveCaretDownIntent extends Intent {
  const MoveCaretDownIntent();
}

/// Moves the caret to the current line start.
class MoveCaretLineStartIntent extends Intent {
  const MoveCaretLineStartIntent();
}

/// Moves the caret to the current line end.
class MoveCaretLineEndIntent extends Intent {
  const MoveCaretLineEndIntent();
}

/// Moves the caret to the document start.
class MoveCaretDocumentStartIntent extends Intent {
  const MoveCaretDocumentStartIntent();
}

/// Moves the caret to the document end.
class MoveCaretDocumentEndIntent extends Intent {
  const MoveCaretDocumentEndIntent();
}

/// Submits an editable control.
class SubmitTextIntent extends Intent {
  const SubmitTextIntent();
}

/// Inserts a tab/indentation into an editable control.
class InsertTabIntent extends Intent {
  const InsertTabIntent();
}
