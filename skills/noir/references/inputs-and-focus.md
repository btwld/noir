# Noir reference: interactive widgets, focus & input

Everything that responds to the keyboard or mouse: the interactive widgets,
the focus system they plug into, raw key/mouse events, and the
`Shortcuts`/`Actions`/`Intent` layer for declarative keybindings.

## Contents

- [How a key reaches your code](#how-a-key-reaches-your-code)
- [The value-vs-controller rule](#the-value-vs-controller-rule)
- [TextInput](#textinput) · [Autocomplete](#autocomplete) · [TextArea](#textarea) · [Select](#select) · [ListView](#listview) · [TreeView](#treeview) · [DataTable](#datatable) · [Checkbox](#checkbox) · [Switch](#switch) · [Button](#button) · [ScrollBox](#scrollbox)
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
  Color? color,                         // ThemeData.text
  Color? backgroundColor,               // ThemeData.surface when a Theme is present; else no fill
  Color? cursorColor,                   // ThemeData.cursor
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

## Autocomplete

A controlled `TextInput` with one attached suggestion or status surface. The
caller owns the required `TextEditingController`, options, status, selection,
and any debounce, filtering, or asynchronous request freshness. `Autocomplete`
owns only focus, keyboard and pointer interaction, and presentation.

```dart
const Autocomplete<T>({
  required TextEditingController controller,
  required List<T> options,
  required AutocompleteStatus status, // idle | loading | ready | empty | error
  required AutocompleteOptionBuilder<T> optionBuilder,
  required ValueChanged<String> onChanged,
  required ValueChanged<T> onSelected,
  required VoidCallback onDismiss,
  FocusNode? focusNode,
  FocusNode? optionsFocusNode,
  String? placeholder,
  bool autofocus = false,
  int maxOptionsHeight = 5,
  bool showScrollIndicator = false,
  WidgetBuilder? loadingBuilder,
  WidgetBuilder? emptyBuilder,
  WidgetBuilder? errorBuilder,
  Color? inputBackgroundColor,
  Color? optionsBackgroundColor,
  Color? selectedBackgroundColor,
  Key? key,
})
```

```dart
Autocomplete<String>(
  controller: _queryController,
  status: _status,
  options: _matches,
  autofocus: true,
  optionBuilder: (context, option, highlighted) => Text(option),
  onChanged: _search,
  onSelected: _choose,
  onDismiss: _hideSuggestions,
)
```

`ready` requires at least one option. Tab follows normal traversal from the
field into the attached list; arrows move its highlight. Enter in either focus
role and a primary click select through the same callback. Escape dismisses a
visible presentation and restores field focus; while `idle`, Escape remains
unhandled for an ancestor. Omitted focus nodes are owned by the component;
supplied nodes and the controller remain caller-owned.

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
  Color? color,                         // ThemeData.text
  Color? backgroundColor,               // ThemeData.surface when a Theme is present; else no fill
  Color? cursorColor,                   // ThemeData.cursor
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
  Color? color,                         // ThemeData.text
  Color? backgroundColor,               // ThemeData.surface when a Theme is present; else no fill
  Color? selectedBackgroundColor,       // ThemeData.selectedBackground while focused
  Color? selectedTextColor,             // ThemeData.selectedForeground
  Color? descriptionColor,              // ThemeData.textMuted
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
Enter / left-click confirms. The highlight uses `selectedBackground` only
while focused and mutes to `ThemeData.surfaceVariant` otherwise.

## ListView

A windowed builder over `itemCount` rows. Only visible rows are built.
Pass `selectedIndex` (and typically `onChanged` / `onSelect`) for a
highlight; omit `selectedIndex` for plain scroll — Enter is then left
unhandled so an ancestor can act on it. The builder always takes three
arguments; `selected` is true only for the highlighted row.

```dart
typedef ListViewItemBuilder =
    Widget Function(BuildContext context, int index, bool selected);

const ListView({
  required this.itemCount,
  required this.itemBuilder,
  Key? key,
  this.itemExtent = 1,
  this.height = 8,
  this.controller,                      // ViewportController; created internally if null
  this.selectedIndex,                   // null = plain scroll
  this.showScrollIndicator = false,
  this.backgroundColor,                 // ThemeData.surface when a Theme is present; else no fill
  this.selectedBackgroundColor,         // ThemeData.selectedBackground while focused
  this.focusNode,
  this.autofocus = false,
  this.onChanged,                       // ValueChanged<int>; never in plain-scroll mode
  this.onSelect,                        // ValueChanged<int>; never in plain-scroll mode
})
```

```dart
ListView(
  itemCount: items.length,
  height: 12,
  selectedIndex: _index,
  itemBuilder: (context, index, selected) => Text(items[index]),
  onChanged: (i) => setState(() => _index = i),
  onSelect: (i) => _open(items[i]),
)
```

Give a stateful row `key: ValueKey(id)` so its `State` survives scrolling.
The mouse wheel scrolls the window in both modes without moving the
highlight.

## TreeView

A virtualized hierarchy over stable caller-provided equality keys. The
controller owns roots, expanded IDs, and selected ID; the widget composes
`ListView` and owns only focus/viewport resources that the caller omits.

```dart
TreeNode<T>.leaf({required Object id, required T value})
TreeNode<T>.branch({
  required Object id,
  required T value,
  Iterable<TreeNode<T>> children = const [],
})

TreeViewController<T>({
  required List<TreeNode<T>> roots,
  Iterable<Object> initiallyExpanded = const [],
  Object? initialSelection,
})

const TreeView<T>({
  required TreeViewController<T> controller,
  required TreeViewItemBuilder<T> itemBuilder,
  int height = 8,
  int indentation = 2,
  ViewportController? viewportController,
  FocusNode? focusNode,
  bool autofocus = false,
  bool showScrollIndicator = false,
  Color? backgroundColor,
  Color? selectedBackgroundColor,
  ValueChanged<TreeNode<T>>? onSelectionChanged,
  ValueChanged<TreeNode<T>>? onActivate,
  Key? key,
})
```

```dart
final tree = TreeViewController<String>(
  roots: [
    TreeNode<String>.branch(
      id: 'docs',
      value: 'Docs',
      children: [
        TreeNode<String>.leaf(id: 'docs/readme', value: 'README.md'),
      ],
    ),
  ],
);

TreeView<String>(
  controller: tree,
  autofocus: true,
  itemBuilder: (context, node, selected) => Text(
    node.value,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  ),
  onActivate: (node) => open(node.id),
)
```

IDs must be unique across the complete tree. `leaf` and an empty `branch` are
different states, and node child/root collections are snapshotted. Up/Down
move through visible rows; Right expands; Left collapses or selects the
visible parent. Enter and a primary click select through the same route,
toggle branches, and call `onActivate` for leaves. A null `onActivate` keeps
leaf activation safely disabled and consumed while selection still works.

`updateRoots` validates before mutation, prunes expansion that no longer names
a branch, and repairs selection to a visible ancestor or clamped row. Direct
controller changes do not call `onSelectionChanged`; that callback reports
user input only. Supplied controller/focus/viewport objects stay caller-owned.
`height` and `indentation` must be non-negative. Use `dispose()` on the
controller when its owner unmounts.

## DataTable

Aligned header plus a `ListView` body. The same `columns` list sizes the
header and every body row — that is the alignment mechanism. Sorting is
presentational: `onSort` fires and an arrow is painted; reordering data is
the caller's job. Header activation is mouse-only.

```dart
const DataColumn({
  required this.label,
  this.flex = 1,
  this.width,                           // exact cells; wins over flex
  this.alignment = Alignment.centerLeft,
  this.sortable = false,
})

const DataTable({
  required this.columns,
  required this.rowCount,
  required this.cellBuilder,            // (context, row, column)
  Key? key,
  this.height = 10,                     // including the header; must be >= 2
  this.columnSpacing = 1,
  this.controller,
  this.selectedIndex,
  this.sortColumnIndex,
  this.sortAscending = true,
  this.onSort,                          // void Function(int columnIndex, bool ascending)
  this.headerColor,
  this.selectedBackgroundColor,
  this.showScrollIndicator = false,
  this.focusNode,
  this.autofocus = false,
  this.onChanged,
  this.onSelect,
})
```

Clamp cell overflow (`Text(maxLines: 1, softWrap: false, overflow:
TextOverflow.ellipsis)`). A right-aligned numeric column needs
`columnSpacing` (default 1) so its header does not abut the next label.

## Checkbox

Two-state box (`Icons.squareOutline`/`Icons.square`, not ballot-box glyphs —
`☑` carries the Unicode `Emoji` property and `☐` does not, so some environments
can give only the checked one a two-cell emoji presentation).
Caller-owned value. Null `onChanged` disables it.

```dart
const Checkbox({
  required this.value,
  Key? key,
  this.onChanged,
  this.label,
  this.color,                           // ThemeData.text
  this.checkedColor,                    // ThemeData.accent
  this.focusNode,
  this.autofocus = false,
})
```

## Switch

Same contract as `Checkbox`; pick by meaning (on/off vs marked item).
Glyphs are `○`/`●`.

```dart
const Switch({
  required this.value,
  Key? key,
  this.onChanged,
  this.label,
  this.color,                           // ThemeData.text
  this.activeColor,                     // ThemeData.success
  this.focusNode,
  this.autofocus = false,
})
```

## Button

Solid fill, one row tall. Null `onPressed` disables it. Focused label is
bold. Space, Enter, or a left click activate.

```dart
const Button({
  required this.label,
  Key? key,
  this.onPressed,
  this.color,                           // ThemeData.accent
  this.textColor,                       // ThemeData.accentForeground
  this.padding = const EdgeInsets.symmetric(horizontal: 1),
  this.focusNode,
  this.autofocus = false,
})
```

## ScrollBox

Wraps content that may overflow and adds keyboard + wheel scrolling and an
optional scrollbar. Drive or observe position with a `ScrollController`.

```dart
const ScrollBox({
  required Widget child,
  ScrollController? controller,         // created internally if null
  Axis scrollDirection = Axis.vertical, // or Axis.horizontal
  bool showScrollbar = true,
  Color? scrollbarColor,                // ThemeData.scrollbarThumb
  Color? trackColor,                    // ThemeData.scrollbarTrack
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
  if (event.logicalKey == LogicalKeyboardKey.enter && _emailFocus.hasFocus) {
    _submit();
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
`event.logicalKey == LogicalKeyboardKey.keyQ`.

### MouseEvent

```dart
event.type           // MouseEventType: down | up | move | scroll
event.button         // MouseButton: left | middle | right
event.localPosition  // Offset — position relative to the listening widget (use this for hit logic)
event.x, event.y     // absolute terminal cell coords
event.scroll?.direction // MouseScrollDirection: up | down | left | right
event.scroll?.magnitude // positive int tick count
```

Mouse reporting must be turned on once at startup:

```dart
void main() => runTuiApp(app, enableMouse: true);
```

Use the handle's `enableMouse(enableMovement: true)` only when the app needs
hover, drag, or other pointer-move events.

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
