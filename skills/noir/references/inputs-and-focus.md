# Noir reference: interactive widgets, focus & input

Everything that responds to the keyboard or mouse: the four interactive widgets,
the focus system they plug into, raw key/mouse events, and the
`Shortcuts`/`Actions`/`Intent` layer for declarative keybindings.

## Contents

- [How a key reaches your code](#how-a-key-reaches-your-code)
- [The value-vs-controller rule](#the-value-vs-controller-rule)
- [TextInput](#textinput) · [TextArea](#textarea) · [Select](#select) · [ScrollBox](#scrollbox)
- [Focus: Focus / FocusScope / FocusNode](#focus)
- [Raw input: KeyEvent / MouseEvent](#raw-input)
- [PointerListener](#pointerlistener)
- [Shortcuts / Actions / Intents](#shortcuts--actions--intents)

---

## How a key reaches your code

Read this before writing any key handler — most "my handler never fires" and
"my text field ate the shortcut" bugs are an ordering misunderstanding, not a
wiring mistake.

Every `KeyEvent` is dispatched through one pipeline. The first handler that
returns `KeyEventResult.handled` (or calls `event.consume()`) stops the walk;
`KeyEventResult.ignored` lets it continue.

| # | Stage | Registered by |
|---|---|---|
| 1 | App-priority handlers | `app.onKey(...)` on the `TuiApp` handle |
| 2 | `Shortcuts` lookup from the focused element upward → `Intent` → nearest `Actions` | `Shortcuts` + `Actions` widgets |
| 3 | Printable character → `InsertTextIntent` | how `TextInput`/`TextArea` receive typing |
| 4 | `onKeyEvent` on the focused `FocusNode`, then each ancestor node | `Focus`, `FocusScope`, or a bare `FocusNode` |
| 5 | Default Tab / Shift+Tab traversal | built in; runs only if 1–4 all ignored |
| 6 | Ctrl+C terminal-session fallback | built in; runs only if 1–5 all ignored |

Practical consequences:

- **Tab traversal is free.** Stage 5 asks the enclosing scope's
  `FocusTraversalPolicy` for the next/previous focusable node — the nearest
  `FocusScope`, or the root scope when you haven't added one. A form with two
  `TextInput`s already tabs between them with no key handling of your own.
  Writing your own Tab branch at stage 4 pre-empts the policy — correct only
  when you want traversal the policy wouldn't produce (e.g. conditionally
  skipping a field).
- **App-level bindings outrank the focused widget.** A plain `q` registered
  through `app.onKey` fires before a focused `TextInput` sees it, so the letter
  becomes untypable. Give app-level bindings a modifier (`Ctrl+Q`), or express
  them as `Shortcuts` inside the subtree where they should apply.
- **A focused text field consumes ordinary characters at stage 3**, so an
  ancestor `Focus.onKeyEvent` will not see them. Non-character keys (Escape,
  function keys, arrows the field ignores) still bubble to stage 4.
- **Stage 4 bubbles**, so a `FocusScope` near the root is the right place for
  form-wide keys such as Enter-to-submit, and it sees them regardless of which
  field is focused.
- **Ctrl+C is a final fallback, not an unconditionally reserved key.** Consume
  it at stages 1–4 when the application needs different behavior; otherwise
  the terminal session restores its modes and exits with interrupt status 130.

---

## The value-vs-controller rule

`TextInput` and `TextArea` accept **either** `controller` **or** `value`, never
both (it's an assertion):

- `value: String` — simplest path; noir owns the text. Pair with `onChanged` to
  observe edits and store them in your `State`.
- `controller: TextEditingController` — you own the text and selection
  programmatically (set `.text`, move the cursor, read `.selection`). Use this
  when you need to mutate the field from code or share it across widgets.

Both widgets are focus-owning: give them a `FocusNode` you create and `dispose`,
or set `autofocus: true`.

---

## TextInput

Single-line field with a rendered caret.

```dart
const TextInput({
  TextEditingController? controller,    // XOR value
  String? value,
  String? placeholder,                  // dimmed hint when empty
  Color color = Color.white,
  Color? backgroundColor,
  Color cursorColor = Color.white,
  CursorStyle cursorStyle = CursorStyle.block,   // block | underline | bar
  bool obscureText = false,             // mask as obscuringCharacter; callbacks still get raw text
  String obscuringCharacter = '*',
  int maxLength = 100,
  ValueChanged<String>? onChanged,      // void Function(String)
  VoidCallback? onSubmit,               // fired on Enter
  FocusNode? focusNode,
  bool autofocus = false,
  Key? key,
})
```

```dart
TextInput(
  focusNode: _nameFocus,
  value: _name,
  placeholder: 'Jane Doe',
  cursorColor: Color.cyan,
  maxLength: 40,
  onChanged: (v) => setState(() => _name = v),
  onSubmit: _save,
)
```

## TextArea

Multi-line editor backed by a `TextEditingController` internally. **Enter inserts
a newline; a reported `Ctrl+Enter` fires `onSubmit`.** Some terminals encode
Ctrl+Enter as ordinary Enter even after keyboard enhancement is requested, so
bind a second control key at an ancestor `Focus` when submission must work
there. The shipped multiline examples use Ctrl+D.

```dart
const TextArea({
  TextEditingController? controller,    // XOR value
  String? value,
  String? placeholder,
  int height = 5,                       // visible rows
  int? width,                           // null = expand to available
  bool readOnly = false,
  int tabSize = 2,
  Color color = Color.white,
  Color? backgroundColor,
  Color cursorColor = Color.white,
  CursorStyle cursorStyle = CursorStyle.block,
  int? maxLength,                       // null = unlimited
  void Function(String)? onChanged,
  void Function()? onSubmit,            // reported Ctrl+Enter
  FocusNode? focusNode,
  bool autofocus = false,
  Key? key,
})
```

Built-in keys: arrows + Home/End + Ctrl+Home/End move the caret; Backspace/Delete
edit and join lines. Physical Tab and Shift+Tab move focus through the traversal
policy (stage 5 above) and do not insert text — indent deliberately by
dispatching an `InsertTabIntent`, which inserts `tabSize` spaces.

## Select

Scrollable single-choice list over typed options. **Remember the callback
split:** `onChanged` fires as the highlight moves; `onSelect` fires on confirm
(Enter or left-click).

```dart
const SelectOption<T>({ required String name, String? description, T? value })

const Select<T>({
  required List<SelectOption<T>> options,
  int selectedIndex = 0,
  int height = 8,                       // max visible rows
  bool showScrollIndicator = false,
  Color color = Color.white,
  Color? backgroundColor,
  Color selectedBackgroundColor = const Color(0.2, 0.4, 0.8),
  Color selectedTextColor = Color.white,
  Color descriptionColor = const Color(0.6, 0.6, 0.6),
  FocusNode? focusNode,
  bool autofocus = false,
  SelectChanged<T>? onChanged,          // void Function(int index, SelectOption<T> option)
  SelectConfirmed<T>? onSelect,         // void Function(int index, SelectOption<T> option)
  Key? key,
})
```

```dart
Select<String>(
  focusNode: _focusNode,
  autofocus: true,
  height: 6,
  options: const [
    SelectOption(name: 'Apple', description: 'crunchy', value: 'apple'),
    SelectOption(name: 'Banana', description: 'soft', value: 'banana'),
  ],
  onChanged: (i, opt) => setState(() => _status = 'Highlight: ${opt.name}'),
  onSelect: (i, opt) => setState(() => _picked = opt.value),
)
```

Keys: ↑/↓ (or `k`/`j`) move; PageUp/Down by a viewport; Home/End to bounds;
Enter / left-click confirms.

## ScrollBox

Wraps content that may overflow and adds keyboard + wheel scrolling and an
optional scrollbar. Drive or observe position with a `ScrollController`.

```dart
const ScrollBox({
  required Widget child,
  ScrollController? controller,         // created internally if null
  Axis scrollDirection = Axis.vertical, // or Axis.horizontal
  bool showScrollbar = true,
  Color scrollbarColor = const Color(0.7, 0.7, 0.7),
  Color trackColor = const Color(0.2, 0.2, 0.2),
  FocusNode? focusNode,
  bool autofocus = false,
  void Function(double offset)? onScroll,
  Key? key,
})

// ScrollController:
ScrollController({ double initialOffset = 0 })
//   .offset, .maxScrollExtent, .viewportExtent, .jumpTo(target), .pageUp(), .pageDown()
```

Keys: arrows by 1 line/cell; PageUp/Down by a viewport; Home/End to bounds.
Mouse wheel input follows the configured axis. Holding Shift rotates vertical
directions to horizontal and horizontal directions to vertical.

---

## Focus

Keyboard input is routed through a focus tree. Wrap interactive regions in
`Focus` (single node) or `FocusScope` (a group with traversal), and own your
`FocusNode`s.

```dart
const Focus({
  required Widget child,
  FocusNode? focusNode,
  bool autofocus = false,
  bool canRequestFocus = true,
  void Function(bool hasFocus)? onFocusChange,
  FocusOnKeyEvent? onKeyEvent,          // KeyEventResult Function(FocusNode, KeyEvent)
  Key? key,
})

const FocusScope({
  required Widget child,
  FocusScopeNode? node,
  FocusTraversalPolicy? traversalPolicy,
  bool autofocus = false,
  bool canRequestFocus = true,
  void Function(bool hasFocus)? onFocusChange,
  FocusOnKeyEvent? onKeyEvent,
  Key? key,
})
```

`FocusNode` lifecycle — create in the field initializer or `initState`, listen if
you need to repaint on focus change, and **always `dispose`**:

```dart
final FocusNode _node = FocusNode();          // FocusNode({String? debugLabel, ...})
// _node.requestFocus();  _node.hasFocus;  _node.unfocus();
// _node.addListener(_onFocusChange);
@override void dispose() { _node.dispose(); super.dispose(); }
```

`onKeyEvent` returns a `KeyEventResult`:
- `handled` — consumed; stop propagation.
- `ignored` — not interested; let it bubble.
- `skipRemainingHandlers` — stop the chain without marking handled.

```dart
KeyEventResult _onKey(FocusNode node, KeyEvent event) {
  if (!event.isPress) return KeyEventResult.ignored;
  if (event.logicalKey == LogicalKeyboardKey.tab) {
    (_emailFocus.hasFocus ? _nameFocus : _emailFocus).requestFocus();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}
```

> `FocusNodeOwnerStateMixin` is not exported: a
> repository-contributor implementation rule reserves it for framework
> widgets. Application code must not import `package:noir/src/**`; compose the
> exported `Focus`, `FocusScope`, and `FocusNode` instead.

---

## Raw input

### KeyEvent

```dart
event.logicalKey        // LogicalKeyboardKey
event.character         // String? printable char, if any
event.isPress           // bool — true on key-down (false on release)
event.isRepeat          // bool — auto-repeat
event.modifiers         // int bitmask
event.isControlPressed  // also isShiftPressed / isAltPressed / isMetaPressed
event.keyCode           // int
```

`LogicalKeyboardKey` constants you'll use most: `tab`, `enter`, `escape`,
`space`, `backspace`, `delete`, `insert`,
`arrowUp`/`arrowDown`/`arrowLeft`/`arrowRight`, `home`, `end`, `pageUp`,
`pageDown`, `keyA`–`keyZ`, `digit0`–`digit9`, `f1`–`f12`.
For dynamic matching: `LogicalKeyboardKey.forCharacter('q')`.

Tip: to catch a plain letter, compare `event.character == 'q'` (simplest) or
`event.logicalKey == LogicalKeyboardKey.keyA`.

### MouseEvent

```dart
event.type           // MouseEventType: down | up | move | scroll
event.button         // MouseButton: left | middle | right
event.localPosition  // Offset — position relative to the listening widget (use this for hit logic)
event.x, event.y     // absolute terminal cell coords
event.scroll?.direction // MouseScrollDirection: up | down | left | right
event.scroll?.magnitude // positive int tick count
```

Mouse reporting must be turned on once at startup. Click and wheel handling use
`runTuiApp(app)..enableMouse()`. Pass `enableMovement: true` only when the app
needs hover, drag, or other pointer-move events.

---

## PointerListener

Attach mouse callbacks to a subtree. Use `event.localPosition` for hit-testing —
do not recompute absolute origins yourself.

```dart
const PointerListener({
  Widget? child,
  MouseEventHandler? onPointerDown,     // void Function(MouseEvent)
  MouseEventHandler? onPointerUp,
  MouseEventHandler? onPointerMove,
  MouseEventHandler? onPointerScroll,
  Key? key,
})
```

---

## Shortcuts / Actions / Intents

For app-wide or scoped keybindings, prefer the declarative trio over hand-written
`onKeyEvent` branches: `Shortcuts` maps key combos to semantic `Intent`s;
`Actions` maps `Intent` types to handlers.

```dart
Shortcuts(
  shortcuts: {
    const SingleActivator(LogicalKeyboardKey.keyS, control: true): const SaveIntent(),
    const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
  },
  child: Actions(
    actions: {
      SaveIntent: CallbackAction<SaveIntent>((intent, context) {
        _save();
        return KeyEventResult.handled;
      }),
    },
    child: child,
  ),
)
```

Activators:
```dart
const SingleActivator(LogicalKeyboardKey trigger, { bool control = false, bool shift = false, bool alt = false, bool meta = false, bool includeRepeats = true })
const CharacterActivator(String character, { bool control = false, bool alt = false, bool meta = false, bool includeRepeats = true })
```

Built-in `Intent`s (all `const`, exported from `package:noir/noir.dart`) cover
focus (`ActivateIntent`, `DismissIntent`, `NextFocusIntent`,
`PreviousFocusIntent`), list selection (`MoveSelectionUp/DownIntent`,
`…PageUp/Down`, `…First/Last`), scrolling (`ScrollUp/Down/Left/RightIntent`,
`…PageUp/Down`, `…ToStart/EndIntent`), and text editing
(`InsertTextIntent(String)`, `DeleteBackward/ForwardIntent`,
`MoveCaret…Intent`, `SubmitTextIntent`, `InsertTabIntent`). Define your own by
extending `Intent` for app-specific commands.
