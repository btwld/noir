# Phase 4 — Display-list painting (the kernel correction)

> **Status:** ✅ DONE — display-list painting landed and verified
> **Cadence:** per-phase review, isolated git worktree (XL — typically the biggest phase)
> **Depends on:** Phase 3 (PipelineOwner + RenderView) complete.

## Goal

Decouple render objects from `Buffer`. Introduce `PaintingContext` and a
supported `TuiCanvas` recording vocabulary backed by private display-list and
compositor machinery, so render objects record paint commands instead of
directly mutating the OpenTUI buffer. Migrate all 8 current `Buffer`-importing
render objects. **The old Buffer-taking paint signature is deleted from
`RenderObject` once the last migration lands.**

## Final P9-038 descendant

The supported surface is `PaintingContext` plus the exact eight-method,
non-constructible paint vocabulary on `TuiCanvas`: `save`, `restore`,
`clipRect`, `fillRect`, `drawText`, `drawBox`, `setCell`, and
`drawTextLayout`. Framework paint passes supply the canvas. The recorder,
display list, command hierarchy, encoder, and compositor are private and
cannot be finalized or committed by package consumers.

## References

- [`GOALS.md`](../GOALS.md) §2 invariant (*"compositor talks to OpenTUI"*); §2 non-negotiable (*"no render-object paint method accepts `Buffer` once Phase 4 lands"*); §6 mechanical guard `no_buffer_in_rendering`
- [`tasks/reference-implementation-plan.md`](./reference-implementation-plan.md) §4.3 (render objects too coupled to Buffer), §7 (painting/compositor review)
- [`READ_HERE.md`](./READ_HERE.md) §10 (fitness functions — `no_buffer_in_rendering` allowlist must reach empty)
- P0.6 deferred from Phase 0: scratch `Renderer` in `lib/src/core/buffer.dart` `_drawTextBufferCells` is **deleted** here; clipping records through the canvas `save()` / `clipRect()` / `restore()` protocol before the private compositor commits.

## Surfaces to introduce

```dart
final class PaintingContext {
  const PaintingContext(this.canvas);
  final TuiCanvas canvas;
  void paintChild(RenderObject child, Offset offset);
}

abstract interface class TuiCanvas {
  void save();
  void restore();
  void clipRect(Rect rect);
  void fillRect(Rect rect, Color color);
  void drawText(
    String text,
    Offset offset,
    Color foreground, {
    Color? background,
    int attributes = 0,
  });
  void drawBox(
    Rect rect,
    BoxOptions options,
    Color borderColor,
    Color backgroundColor,
  );
  void setCell(
    Offset offset,
    String char,
    Color foreground,
    Color background,
    int attributes,
  );
  void drawTextLayout(
    TextLayout layout,
    Offset offset, {
    Rect? sourceRect,
    TextHighlight? selection,
  });
}
```

The private recorder, display list, command hierarchy, encoder, and compositor
translate this vocabulary into existing `Buffer` calls. The **architectural**
decoupling is the deliverable; the optimized backend (batching, frame packets)
is a follow-up.

## Tasks (to be decomposed at architect time)

- [x] **Compatibility drift audit** — recorded to workspace scratch (not retained). Specifically inspect `lib/src/rendering/*.dart`, `lib/src/core/buffer.dart`, `lib/src/widgets/scroll_box.dart` (RenderScrollBox), `lib/src/widgets/text_area.dart` (RenderTextArea).
- [x] **Open worktree** for the migration.
- [x] 4.1 — Add `PaintingContext`, the supported `TuiCanvas` interface, and a private recorder, display list, sealed command hierarchy, encoder, and compositor. If the isolated Phase 4 worktree needs a temporary old/new paint bridge during migration, it is not a compatibility surface and must be deleted by 4.10 before phase closeout.
- [x] 4.2 — Migrate `RenderBox` (`lib/src/rendering/box.dart`) — base class migration; sets the pattern.
- [x] 4.3 — Migrate `RenderProxyBox` (`lib/src/rendering/proxy_box.dart`).
- [x] 4.4 — Migrate `RenderConstrainedBox` (`lib/src/rendering/constrained_box.dart`).
- [x] 4.5 — Migrate `RenderDecoratedBox` (`lib/src/rendering/decorated_box.dart`).
- [x] 4.6 — Migrate `RenderPadding` (`lib/src/rendering/padding.dart`).
- [x] 4.7 — Migrate `RenderPositionedBox` (`lib/src/rendering/positioned_box.dart`).
- [x] 4.8 — Migrate `RenderParagraph` (`lib/src/rendering/paragraph.dart`) — text path; eliminates scratch-renderer P0.6.
- [x] 4.9 — Migrate `RenderObject` base (`lib/src/rendering/object.dart`) + the remaining render-object subclasses (`RenderFlex`, `RenderScrollBox`, `RenderTextArea`).
- [x] 4.10 — **Delete** the Buffer-taking paint signature from `RenderObject`. Delete `_drawTextBufferCells` scratch-renderer code path. Empty the `no_buffer_in_rendering` allowlist.

Each migration removes one entry from `test/architecture/no_buffer_in_rendering_test.dart`'s allowlist.

## Hard-rule application

- The old Buffer-taking paint signature is **deleted** from `RenderObject` once the last migration lands.
- No dual paint contract or wrapper method survives phase closeout.
- P0.6 scratch `Renderer` is **deleted**, not patched.
- Render objects no longer import `lib/src/core/buffer.dart`.

## Audit gate

- [x] Zero entries on the `no_buffer_in_rendering` allowlist.
- [x] Grep for the old Buffer-taking render-object paint signature in `lib/` returns zero hits.
- [x] `Grep "createRenderer\|destroyRenderer" lib/src/rendering/` returns zero hits.
- [x] Existing goldens pass (paint output unchanged — the migration is layer-shift, not behavior-shift).
- [x] No `Renderer` instance is created inside `paint()`.
- [x] `dart format` / `dart analyze --fatal-infos` / `dart test test/architecture/` / `dart test` all green.

## What landed

- Render objects now paint through `PaintingContext` and record commands into `TuiCanvas`.
- The private recorder, display list, command hierarchy, encoder, and compositor route paint to OpenTUI from the app binding and test host.
- `no_buffer_in_rendering` now has an empty allowlist and scans widgets as well as rendering.
- Clipped `TextBuffer` drawing no longer creates scratch `Renderer` instances; it uses Dart-side text-buffer cell metadata for the clipped copy path.
- Visual smoke artifact: workspace-scratch screenshot (not retained).

## Risk note

Phase 4 is XL. The recommended structure is: backend infrastructure first; then 4.2–4.9 in 1–2-PR batches; then 4.10 deletion. **Do not** mix the adapter landing with backend optimization — that's a follow-up phase. The deliverable here is *decoupling*, not throughput.
