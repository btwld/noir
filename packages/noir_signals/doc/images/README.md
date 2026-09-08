# Task-list walkthrough screenshots

These JPEGs show actual Noir-rendered frames from the complete checkpoints in
[`../getting-started.md`](../getting-started.md). They are headless drive-mode
captures replayed with `asciinema-player`, not terminal-emulator screenshots.

Each recording is 80×24 cells, 1.6 seconds at 10 fps. The screenshots use its
1.5-second poster, with a steady cursor, Menlo at 16 px, and the player's
start overlay hidden. The app's text, colors, attributes, and cursor come from
the recording. Each JPEG is 745×472 pixels.

| Image | Checkpoint and input | Result |
| --- | --- | --- |
| `01-screen.jpg` | Step 1; no input. | Title, placeholder, and exit hint. |
| `02-state.jpg` | Step 2; no input. | Three rows and `2 of 3 remaining`. |
| `03-complete.jpg` | Step 3; click `task-0`. | First task checked; `1 of 3 remaining`. |
| `04-add.jpg` | Step 4; type `Ship the guide`, then Enter. | Four rows, cleared draft, `3 of 4 remaining`. |
| `05-filter.jpg` | Step 5; add `Ship the guide`, click `task-0`, then `hide-completed`. | Two visible rows; `2 of 4 remaining`. |
| `06-clear.jpg` | Repeat the previous sequence, then click `clear-completed`. | Two stored rows; `2 of 2 remaining`, removal disabled. |

To refresh a screenshot, copy its complete checkpoint into a local Dart file
in the checkout and capture the sequence with the repository's
[`record_noir_demo.dart`](https://github.com/conceptadev/noir/blob/main/scripts/record_noir_demo.dart).
Use the same geometry and inspect the rendered poster before replacing the
JPEG. Each scene starts from a fresh app; it does not inherit earlier steps'
interactive state.

The website's `sync-signals-guide.mjs` copies these images into its public
assets when syncing the guide. Edit the source images here.
