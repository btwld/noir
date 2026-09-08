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
| [File search](file_search.dart) | `dart run example/file_search.dart` | Type `lib/src` to filter a model observed through `useSignalValue` and `SignalValueBuilder`. |

Follow the [task-list walkthrough](../doc/getting-started.md) to build the app
step by step, with code changes, complete checkpoints, and screenshots. The
[file-search model](models/file_search_model.dart) shows how to move reactive
state out of a widget while keeping ownership explicit.

For hot reload, replace `dart run` with `dart run noir:run`, for example
`dart run noir:run example/task_list.dart`. Ctrl+C exits each app through
Noir's cleanup. These examples keep their data in memory.

The companion and its required Noir alpha.5 are currently unpublished
candidates; the commands above use the repository's Pub workspace.
