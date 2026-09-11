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

Every image above has a scene in
[`packages/noir/tool/recordings/doc_frames.json`](https://github.com/conceptadev/noir/blob/main/packages/noir/tool/recordings/doc_frames.json)
that names its checkpoint, its input, and the text the lesson promises.
`dart run tool/capture_doc_frames.dart --check`, run from `packages/noir/`,
checks the captured frames,
including cell colors, attributes, and cursor state. It does not update or
approve JPEGs.

`provenance.json` separately records each reviewed JPEG's `imageSha256` and
the matching frame's `sourceSha256` and `visualSha256`. The website generator
and architecture tests reject a mismatch. Recapturing a changed checkpoint
cannot silently approve its old screenshot.

To refresh a screenshot, recapture the frames, then record the same scene with
[`record_noir_demo.dart`](https://github.com/conceptadev/noir/blob/main/packages/noir/tool/record_noir_demo.dart)
at the geometry above and inspect the rendered poster before you replace the
JPEG. Each scene starts from a fresh app; it does not inherit an earlier
lesson's interactive state. After checking the JPEG against the scene, copy
that scene's `sourceSha256` and `visualSha256` from
`website/src/generated/terminal-frames.json` into `provenance.json`, and set
`imageSha256` to the SHA-256 of the reviewed JPEG bytes. Commit the image and
its provenance together. Do not update provenance merely to clear a failed
check: it records a visual review, not automatic pixel equivalence.

The website's `sync-docs.mjs` copies these images into its public assets when
it generates the lesson pages. Edit the source images here.
