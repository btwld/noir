# Build a task list with hooks and Signals

The [task-list example](../example/task_list.dart) combines editable text,
completion checkboxes, a visibility filter, and a derived remaining count.
Everything is in memory; restarting the app restores its three sample tasks.

## Run the examples

The companion targets `noir 0.0.1-alpha.5` and `noir_signals 0.0.1-alpha.0`.
These candidates are not published yet. From a Noir repository checkout with
Dart 3.10 or later, resolve the Pub workspace and run the task list:

```sh
dart pub get
dart run packages/noir_signals/example/task_list.dart
```

For hot reload, use
`dart run noir:run packages/noir_signals/example/task_list.dart`.

The screen starts with **2 of 3 remaining**. Type a task and press Enter, or
click Add. Tab and Shift+Tab move focus; Space or Enter toggles a checkbox.
Hide completed filters the view without deleting tasks. Clear completed
removes finished tasks. The list has its own focus stop for scrolling with
PageUp and PageDown. Ctrl+C exits through Noir's normal cleanup.

Start smaller or explore shared state with the other two examples:

| Source | Run from the repository root | Learn |
| --- | --- | --- |
| [Counter](../example/counter.dart) | `dart run packages/noir_signals/example/counter.dart` | `HookWidget` and `useState` for a local value. |
| [Task list](../example/task_list.dart) | `dart run packages/noir_signals/example/task_list.dart` | Hook-owned signals, computed state, controllers, and immutable list updates. |
| [File search](../example/file_search.dart) | `dart run packages/noir_signals/example/file_search.dart` | A separate Signals model, borrowed observation, and `SignalValueBuilder`. |

## Give each value an owner

Import both public entrypoints:

```dart
import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
```

`TaskListApp` extends `HookWidget`. Its `build` starts with these hooks, in the
same order on every build:

```dart
final draft = useTextEditingController();
final tasks = useSignal(<({int id, String title, bool done})>[
  (id: 0, title: 'Read the hooks guide', done: false),
  (id: 1, title: 'Run the counter example', done: true),
  (id: 2, title: 'Build a Signals app', done: false),
]);
final remaining = useComputed(
  () => tasks.value.where((task) => !task.done).length,
  keys: [tasks],
);
final hideCompleted = useState(false);
final nextId = useRef(3);
```

| Hook | Responsibility here |
| --- | --- |
| `useTextEditingController` | Retains the field's text, selection, and caret across rebuilds; disposes the controller on unmount. |
| `useSignal` | Owns and observes the task list, requesting a host rebuild when its value changes. |
| `useComputed` | Owns and observes the remaining count; Signals tracks the task signal read inside the callback. |
| `useState` | Owns and observes a `ValueNotifier<bool>` for the local visibility filter. |
| `useRef` | Retains the next task ID without requesting a rebuild when it changes. |

The hooks dispose what they create. Do not manually dispose these values or
enable upstream `autoDispose` on a hook-owned signal or computed. Stable task
IDs become `ValueKey<String>('task-${task.id}')` on checkboxes, preserving
identity when a different row is filtered out or removed.

## Change state from input callbacks

Both `TextInput.onSubmit` and `Button.onPressed` call this local function:

```dart
void addTask() {
  final title = draft.text.trim();
  if (title.isEmpty) return;
  tasks.value = [
    ...tasks.value,
    (id: nextId.value++, title: title, done: false),
  ];
  draft.clear();
}
```

Assign a replacement list instead of calling `tasks.value.add(...)` or
mutating a task in place. Completion and removal follow the same pattern.
The controller stays mounted when the signal changes, so a draft survives
checkbox clicks, filtering, and resize. A successful add clears it explicitly.

## Derive values instead of synchronizing copies

The count is read directly from the computed:

```dart
Text('${remaining.value} of ${tasks.value.length} remaining')
```

There is no separate count to update in every callback. `useComputed` tracks
the `.value` reads inside its callback. `keys: [tasks]` captures the signal's
identity; it does not need to change when the signal's contents change.

Ordinary captured Dart values are different. If a computation captures a
constructor property, include that property in `keys` so a changed property
replaces the stored closure. The creation callback is retained while the keys
stay equal. Do not put `tasks.value` in the key list just to trigger updates:
Signals already tracks that value, and such keys would recreate the computed.

`useState` is sufficient for the filter because it is only local presentation
state. A signal is useful when other computations need to depend on it.

## Observe a model that someone else owns

The [file-search model](../example/models/file_search_model.dart) shows the
next step: a plain Dart object owns its signals and computeds. Its screen
retains one model and registers its cleanup:

```dart
final model = useMemoized(() => FileSearchModel(files));
useOnDispose(model.dispose);
final visible = useSignalValue(model.visibleFiles);
```

Here `files` is a fixed input list. `useMemoized` alone does not dispose the
model. The disposal hook supplies that ownership, while `useSignalValue`
owns only its subscription. If a parent supplies the model, the parent keeps
ownership; the child observes it without registering `model.dispose`.

For a small observer subtree, use a builder:

```dart
SignalValueBuilder<int>(
  signal: model.visibleCount,
  builder: (context, count) => Text('$count files'),
)
```

This builder subscribes only to its supplied signal and never disposes it.
Changes observed here request this subtree's rebuild. A parent rebuild can
still update the builder, and Noir still performs its ordinary layout and
paint work. Reading some other signal inside the builder does not subscribe
to that signal. There is no automatic whole-build tracking.

## Use effects for external work

The task list needs no effect: all changes come from input, and the count is
derived. `useEffect` acquires an external resource and returns its cleanup;
its key list controls replacement. `useSignalEffect` also owns cleanup, but
Signals tracks reads inside its callback and reruns it when those values
change. Use it for work such as synchronizing a separate service, not for
copying a computed value into another observed signal.

Effects install synchronously. Installation and lifecycle cleanup must not
request a hook rebuild, including a rebuild in a different hook widget. Put
user-driven changes in input callbacks. Later timer, future, and stream
callbacks may update state after the effect has returned. See the
[effects contract](signals.md#effects) for rerun timing and error behavior.

Call hooks unconditionally at the top of `build` or a top-level custom
`use...` function. Never call them from a branch, loop, input callback, effect,
or cleanup. Conditional widget children are fine after the hooks have run.

## Continue

- [Hooks guide](hooks.md): ordering, custom hooks, effects, and resource cleanup.
- [Signals guide](signals.md): ownership, observation, replacement, and captured values.
- [Task-list source](../example/task_list.dart): the complete runnable app.
- [Task-list tests](https://github.com/conceptadev/noir/blob/main/packages/noir_signals/test/example/task_list_test.dart): headless keyboard,
  pointer, filtering, and resize checks in the repository checkout.
