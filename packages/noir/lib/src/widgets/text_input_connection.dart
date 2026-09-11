import 'package:characters/characters.dart';

import '../core/input.dart';
import '../foundation/listenable.dart';
import '../foundation/text_editing_controller.dart';
import '../framework/build_context.dart';
import 'actions.dart';
import 'intents.dart';
import 'shortcuts.dart';

/// Applies text-editing shortcuts and intents to a [TextEditingController].
///
/// Built-in text widgets use this helper, and custom editable widgets can
/// compose [shortcuts] with [actions] to get the same editing semantics.
class TextInputConnection {
  /// Applies this editing policy to a caller-owned [controller].
  TextInputConnection({
    required this.controller,
    this.readOnly = false,
    this.allowNewline = true,
    this.allowTab = true,
    this.maxLength,
    this.tabSize = 2,
    this.onChanged,
    this.onSubmit,
  });

  /// Controller that owns text and selection.
  final TextEditingController controller;

  /// Whether editing commands should be ignored.
  final bool readOnly;

  /// Whether inserted text may contain newlines.
  final bool allowNewline;

  /// Whether tab intents insert indentation.
  final bool allowTab;

  /// Maximum grapheme length.
  final int? maxLength;

  /// Spaces inserted by [InsertTabIntent].
  final int tabSize;

  /// Called when text changes.
  final void Function(String value)? onChanged;

  /// Called for submit intents.
  final VoidCallback? onSubmit;

  /// Default text-editing shortcuts for this connection's editing policy.
  Map<ShortcutActivator, Intent> get shortcuts => {
    const SingleActivator(LogicalKeyboardKey.backspace):
        const DeleteBackwardIntent(),
    const SingleActivator(LogicalKeyboardKey.delete):
        const DeleteForwardIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowLeft):
        const MoveCaretLeftIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        const MoveCaretRightIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        const MoveCaretUpIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        const MoveCaretDownIntent(),
    const SingleActivator(LogicalKeyboardKey.home):
        const MoveCaretLineStartIntent(),
    const SingleActivator(LogicalKeyboardKey.end):
        const MoveCaretLineEndIntent(),
    const SingleActivator(LogicalKeyboardKey.home, control: true):
        const MoveCaretDocumentStartIntent(),
    const SingleActivator(LogicalKeyboardKey.end, control: true):
        const MoveCaretDocumentEndIntent(),
    const SingleActivator(LogicalKeyboardKey.enter): allowNewline
        ? const InsertTextIntent('\n')
        : const SubmitTextIntent(),
    if (allowNewline)
      const SingleActivator(LogicalKeyboardKey.enter, control: true):
          const SubmitTextIntent(),
  };

  /// Actions handled by this connection.
  Map<Type, Action<Intent>> get actions => {
    InsertTextIntent: CallbackAction<InsertTextIntent>(_insertText),
    InsertTabIntent: CallbackAction<InsertTabIntent>(_insertTab),
    DeleteBackwardIntent: CallbackAction<DeleteBackwardIntent>(_deleteBackward),
    DeleteForwardIntent: CallbackAction<DeleteForwardIntent>(_deleteForward),
    MoveCaretLeftIntent: CallbackAction<MoveCaretLeftIntent>(_moveLeft),
    MoveCaretRightIntent: CallbackAction<MoveCaretRightIntent>(_moveRight),
    MoveCaretUpIntent: CallbackAction<MoveCaretUpIntent>(_moveUp),
    MoveCaretDownIntent: CallbackAction<MoveCaretDownIntent>(_moveDown),
    MoveCaretLineStartIntent: CallbackAction<MoveCaretLineStartIntent>(
      _moveLineStart,
    ),
    MoveCaretLineEndIntent: CallbackAction<MoveCaretLineEndIntent>(
      _moveLineEnd,
    ),
    MoveCaretDocumentStartIntent: CallbackAction<MoveCaretDocumentStartIntent>(
      _moveDocumentStart,
    ),
    MoveCaretDocumentEndIntent: CallbackAction<MoveCaretDocumentEndIntent>(
      _moveDocumentEnd,
    ),
    SubmitTextIntent: CallbackAction<SubmitTextIntent>(_submit),
  };

  /// Inserts [text] using the connection's editing policy.
  KeyEventResult insertText(String text) {
    if (readOnly) return KeyEventResult.ignored;
    _requireUsableSelection();
    if (!_underLimit(text)) return KeyEventResult.ignored;
    return _applyEdit(
      () => controller.insert(text, allowNewline: allowNewline),
    );
  }

  KeyEventResult _insertText(InsertTextIntent intent, BuildContext context) =>
      insertText(intent.text);

  // Tab indentation is plain-space insertion: the newline policy flags are
  // unobservable for a spaces-only replacement, so the shared insertText
  // path applies the identical readOnly / selection / limit sequence.
  KeyEventResult _insertTab(InsertTabIntent intent, BuildContext context) =>
      allowTab ? insertText(' ' * tabSize) : KeyEventResult.ignored;

  KeyEventResult _deleteBackward(
    DeleteBackwardIntent intent,
    BuildContext context,
  ) {
    if (readOnly) return KeyEventResult.ignored;
    return _applyEdit(controller.deleteBack);
  }

  KeyEventResult _deleteForward(
    DeleteForwardIntent intent,
    BuildContext context,
  ) {
    if (readOnly) return KeyEventResult.ignored;
    return _applyEdit(controller.deleteForward);
  }

  KeyEventResult _moveLeft(MoveCaretLeftIntent intent, BuildContext context) =>
      _move(controller.moveCursorLeft);

  KeyEventResult _moveRight(
    MoveCaretRightIntent intent,
    BuildContext context,
  ) => _move(controller.moveCursorRight);

  KeyEventResult _moveUp(MoveCaretUpIntent intent, BuildContext context) =>
      _move(controller.moveCursorUp);

  KeyEventResult _moveDown(MoveCaretDownIntent intent, BuildContext context) =>
      _move(controller.moveCursorDown);

  KeyEventResult _moveLineStart(
    MoveCaretLineStartIntent intent,
    BuildContext context,
  ) => _move(controller.moveLineStart);

  KeyEventResult _moveLineEnd(
    MoveCaretLineEndIntent intent,
    BuildContext context,
  ) => _move(controller.moveLineEnd);

  KeyEventResult _moveDocumentStart(
    MoveCaretDocumentStartIntent intent,
    BuildContext context,
  ) => _move(controller.moveDocumentStart);

  KeyEventResult _moveDocumentEnd(
    MoveCaretDocumentEndIntent intent,
    BuildContext context,
  ) => _move(controller.moveDocumentEnd);

  KeyEventResult _submit(SubmitTextIntent intent, BuildContext context) {
    onSubmit?.call();
    return KeyEventResult.handled;
  }

  KeyEventResult _applyEdit(bool Function() edit) {
    _requireUsableSelection();
    final before = controller.text;
    if (!edit()) return KeyEventResult.ignored;
    if (controller.text != before) {
      onChanged?.call(controller.text);
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _move(VoidCallback move) {
    _requireUsableSelection();
    final before = controller.selection;
    move();
    if (controller.selection == before) return KeyEventResult.ignored;
    return KeyEventResult.handled;
  }

  void _requireUsableSelection() {
    if (controller.selectionWithinText) {
      return;
    }
    throw StateError(
      'TextInputConnection requires an in-range controller selection.',
    );
  }

  bool _underLimit(String replacement) {
    final limit = maxLength;
    if (limit == null) return true;
    if (!allowNewline && replacement.contains('\n')) return false;
    final selection = controller.selection;
    final selectedLength = selection
        .textInside(controller.text)
        .characters
        .length;
    final nextLength =
        controller.text.characters.length -
        selectedLength +
        replacement.characters.length;
    return nextLength <= limit;
  }
}
