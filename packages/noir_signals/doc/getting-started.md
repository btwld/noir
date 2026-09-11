# Build a task list: create the screen

Build a terminal task list you can add to, complete, filter, and clear. Five
lessons take you from an empty screen to the shipped example. Each lesson gives
you one change, the command to run, the result to expect, and a complete
runnable checkpoint.

<figure>

![The finished task list: a New task field, an Add button, a summary line, a Hide completed checkbox, two open tasks, and a disabled Clear completed button.](./images/06-clear.jpg)

<figcaption>

The finished app after lesson 5.

</figcaption>

</figure>

You need Dart 3.10 or later and a checkout of the Noir repository.
`noir_signals` requires Noir 0.0.2. You will build inside the checkout, which
resolves both packages from the same revision. To add the published packages
to an application of your own instead, use the
[install instructions](../README.md).

This tutorial starts from an empty file. It does not require the first-app
tutorial, the hooks guide, or the Signals guide.

## Lessons in this tutorial

1. <a id="step-1-create-the-screen"></a> **Create the screen** — you are here.
   `SignalWidget`, cell layout, and `Expanded`.
2. <a id="step-2-own-the-task-signal-and-derive-the-count"></a>
   [Store tasks and derive the count](./tutorials/task-list/store-tasks.md) —
   `useSignal`, `useComputed`, and named records.
3. <a id="step-3-complete-tasks-by-replacing-the-list"></a>
   [Complete a task](./tutorials/task-list/complete-a-task.md) — controlled
   values, stable IDs, and list replacement.
4. <a id="step-4-retain-a-draft-and-add-tasks"></a>
   [Add a task](./tutorials/task-list/add-a-task.md) —
   `useTextEditingController` and `useRef`.
5. <a id="step-5-filter-the-view-and-remove-completed-tasks"></a>
   <a id="continue-with-your-app"></a>
   [Filter and clear completed tasks](./tutorials/task-list/filter-and-clear.md)
   — `useSignal`, a computed view, and a disabled action.

## Set up the learner project

<a id="run-the-examples"></a>

From the **repository root**, resolve the packages and open the companion
directory:

```sh
dart pub get
cd packages/noir_signals
```

Every command in this tutorial runs from `packages/noir_signals/`. Create an
empty `example/my_task_list.dart` in your editor. That is the file you will
edit in every lesson.

Restart the app between lessons, because each lesson adds or reorders hooks.
Once the hook order stops changing, `dart run noir:run example/my_task_list.dart`
reloads ordinary build edits and keeps the current state.

To see the finished program before you build it, run the shipped
[task-list example](../example/task_list.dart) with
`dart run example/task_list.dart`.

## Write the first screen

`SignalWidget` is the host that retains our hooks. The two imports separate
Noir widgets from the optional hooks and Signals integration. `runTuiApp`
mounts the screen and owns terminal cleanup. `enableMouse: true` lets the later
buttons and checkboxes receive clicks.

The screen uses integer cell insets and theme colors. `Column` stacks the
children. `Expanded` gives the task area the spare rows and keeps the footer at
the bottom. `const` marks widget configurations that never change.

Put this complete file in `example/my_task_list.dart`:

<!-- noir:file -->

```dart
import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';

void main() => runTuiApp(const TaskListApp(), enableMouse: true);

class TaskListApp extends SignalWidget {
  const TaskListApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 1,
        children: [
          const Text(
            'Task list',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Expanded(child: Text('Your tasks will appear here.')),
          Text('Ctrl+C exits', style: TextStyle(color: theme.textMuted)),
        ],
      ),
    );
  }
}
```

<!-- /noir:file -->

## Run it

```sh
dart run example/my_task_list.dart
```

You should see the title, the placeholder, and the exit hint. Ctrl+C exits
through Noir's normal cleanup.

<figure>

![Lesson 1: the Task list title, a Your tasks will appear here placeholder, and the Ctrl+C exits hint.](./images/01-screen.jpg)

<figcaption>

Lesson 1 — the screen is mounted. It has no task state yet.

</figcaption>

</figure>

The screen has no hooks yet, so nothing changes while it runs. The next lesson
gives the same widget its own state.

Next: [Store tasks and derive the count](./tutorials/task-list/store-tasks.md).
