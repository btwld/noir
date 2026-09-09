# Task-list walkthrough screenshots

These JPEGs show actual Noir-rendered frames from the task-list tutorial's
runnable checkpoints in
[`../../example/tutorials/task_list/`](../../example/tutorials/task_list/) and
[`../../example/task_list.dart`](../../example/task_list.dart). They are
headless drive-mode captures replayed with `asciinema-player`, not
terminal-emulator screenshots.

Each recording is 80×24 cells, 1.6 seconds at 10 fps. The screenshots use its
1.5-second poster, with a steady cursor, Menlo at 16 px, and the player's
start overlay hidden. The app's text, colors, attributes, and cursor come from
the recording. Each JPEG is 745×472 pixels.

| Image | Checkpoint and input | Result |
| --- | --- | --- |
| `01-screen.jpg` | `step_01.dart`; no input. | Title, placeholder, and exit hint. |
| `02-state.jpg` | `step_02.dart`; no input. | Three rows and `2 of 3 remaining`. |
| `03-complete.jpg` | `step_03.dart`; click `task-0`. | First task checked; `1 of 3 remaining`. |
| `04-add.jpg` | `step_04.dart`; type `Ship the guide`, then Enter. | Four rows, cleared draft, `3 of 4 remaining`. |
| `05-filter.jpg` | `task_list.dart`; add `Ship the guide`, click `task-0`, then `hide-completed`. | Two visible rows; `2 of 4 remaining`. |
| `06-clear.jpg` | Repeat the previous sequence, then click `clear-completed`. | Two stored rows; `2 of 2 remaining`, removal disabled. |

To refresh a screenshot, record its checkpoint with the repository's
[`record_noir_demo.dart`](https://github.com/conceptadev/noir/blob/main/scripts/record_noir_demo.dart),
using the same geometry, and inspect the rendered poster before replacing the
JPEG. Each scene starts from a fresh app; it does not inherit an earlier
lesson's interactive state.

The website's `sync-docs.mjs` copies these images into its public assets when
it generates the lesson pages. Edit the source images here.
