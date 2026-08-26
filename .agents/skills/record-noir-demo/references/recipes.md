# Recording recipes

Use one JSON object per recording:

```json
{
  "version": 1,
  "entrypoint": "example/counter.dart",
  "output": ".context/demos/counter.cast",
  "title": "Noir · Counter",
  "width": 80,
  "height": 24,
  "durationMs": 3200,
  "fps": 12,
  "actions": [
    {"atMs": 900, "key": "up"},
    {"atMs": 1700, "key": "space"},
    {"atMs": 2500, "clickKey": "increment"}
  ]
}
```

## Fields

- `version`: `1`.
- `entrypoint`: existing Dart entry point, relative to the repository root.
- `output`: local `.cast` path. Prefer `.context/demos/` for review.
- `title`: factual recording title shown by compatible players.
- `width`, `height`: emulated terminal cells. Start from the example's focused
  test geometry or 80×24.
- `durationMs`: `100`–`60000`.
- `fps`: `1`–`60`; use 12 for cell animation unless faster sampling is visibly
  necessary. Sample fine-grained progress or particles at 30 fps. If exporting
  a GIF with `agg`, choose a cap above this value and verify decoded timing.
- `actions`: optional ordered or unordered inputs. The recorder sorts them by
  `atMs`.

Each action has `atMs` plus exactly one operation:

- `key`: any name accepted by `scripts/driver/ansi_keys.dart`, except `ctrl-c`.
- `type`: UTF-8 text sent through Noir's production input parser.
- `clickKey`: exact `ValueKey<String>` resolved through render-tree hit testing.

## Selection guidance

- Automatic animation: no actions; record at least one full forward/reverse
  cycle.
- Button or counter: show the initial state, one keyboard action, then the
  visible result.
- Form or select: show focus arrival, editing or selection, and confirmation.
- Mouse-specific proof: use `clickKey`, not hard-coded coordinates.

Keep recipes short. A docs recording is evidence for one behavior, not a tour
of every control.
