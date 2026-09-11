# noir_signals examples

This directory contains the companion package's runnable examples. Use
`counter.dart` for a first hook, `task_list.dart` for derived reactive state,
and `file_search.dart` for a separate Signals model.

From the **Noir repository root**, resolve the workspace and enter the
companion package:

```sh
dart pub get
cd packages/noir_signals
```

Run the commands below from **`packages/noir_signals/`**, the package directory
containing this `example/` directory:

| Source | Command | What to try |
| --- | --- | --- |
| [Counter](counter.dart) | `dart run example/counter.dart` | Press Enter or Space to increment `useState`. |
| [Task list](task_list.dart) | `dart run example/task_list.dart` | Add tasks, complete them, hide completed rows, and remove completed records. |
| [File search](file_search.dart) | `dart run example/file_search.dart` | Type `lib/src` to filter a model observed through `SignalValueBuilder`. |

Follow the task-list tutorial, which begins at
[Build a task list](../doc/getting-started.md), to build the app one lesson at
a time, with exact code changes and screenshots. Its lesson checkpoints are
runnable too:

| Lesson | Checkpoint | Command |
| --- | --- | --- |
| 1. Create the screen | [step_01.dart](tutorials/task_list/step_01.dart) | `dart run example/tutorials/task_list/step_01.dart` |
| 2. Store tasks and derive the count | [step_02.dart](tutorials/task_list/step_02.dart) | `dart run example/tutorials/task_list/step_02.dart` |
| 3. Complete a task | [step_03.dart](tutorials/task_list/step_03.dart) | `dart run example/tutorials/task_list/step_03.dart` |
| 4. Add a task | [step_04.dart](tutorials/task_list/step_04.dart) | `dart run example/tutorials/task_list/step_04.dart` |
| 5. Filter and clear completed tasks | [task_list.dart](task_list.dart) | `dart run example/task_list.dart` |

Lesson 5 has no separate file: the shipped `task_list.dart` is its checkpoint,
so the tutorial and the example never drift apart.

The [file-search model](models/file_search_model.dart) shows how to move
reactive state out of a widget while keeping ownership explicit.

For hot reload, replace `dart run` with `dart run noir:run`, for example
`dart run noir:run example/task_list.dart`. Ctrl+C exits each app through
Noir's cleanup. These examples keep their data in memory.

The companion is not published yet and requires Noir 0.0.2. The commands above
use the repository's Pub workspace to resolve both packages.
