# Phase 5 — Text system (TextSpan, RichText, TextIndexMap, Unicode-correct)

> **Status:** ✅ DONE
> **Cadence:** per-phase review (L)
> **Depends on:** Phase 4 (display-list painting) complete — `TextLayout` is a display-list operand.

## Goal

Replace the single-style `Text` widget plus ad-hoc string indexing with a Flutter-style `TextSpan` / `RichText` / `TextLayout` / `TextIndexMap` system that is Unicode-correct end-to-end. **Every visual-text path stops using `String.length` and `text[i]`.**

## References

- [`GOALS.md`](../GOALS.md) §2 non-negotiable (*"no `String.length` or `text[i]` on visual-text paths"*); §6 unicode guard
- [`tasks/reference-implementation-plan.md`](./reference-implementation-plan.md) §8 (text review)
- [`READ_HERE.md`](./READ_HERE.md) §10 (unicode_guard_test fitness function lands here)

## Surfaces to introduce

```dart
abstract class InlineSpan {}
final class TextSpan extends InlineSpan {
  const TextSpan({this.text, this.style, this.children = const []});
  final String? text;
  final TextStyle? style;
  final List<InlineSpan> children;
}

final class TextLayout {
  // result of laying out spans against constraints
}

final class TextLayoutEngine {
  TextLayout layout(InlineSpan root, BoxConstraints constraints);
}

final class TextIndexMap {
  TextIndexMap(String text);
  int utf16ToGrapheme(int utf16Offset);
  int graphemeToUtf16(int graphemeIndex);
}

// The cell and native-byte axes originally sketched here were removed in the
// Phase 9 round-3 simplification review: cell math is owned by
// grapheme_metrics.dart, and no consumer ever read the native-byte axis.

final class PersistentUtf8Text {
  // arena-allocated, reusable across frames
}
```

## Tasks (to be decomposed at architect time)

- [x] **Compatibility drift audit** — recorded to workspace scratch (not retained). Specifically inspect: `lib/src/core/text_buffer.dart`, `lib/src/core/grapheme_metrics.dart`, `lib/src/widgets/text.dart` (and `:9` re-export of `TextOverflow`), `lib/src/widgets/input.dart`, `lib/src/widgets/text_area.dart`, `lib/src/widgets/select.dart`.
- [x] 5.1 — `TextSpan` + `RichText` + `InlineSpan` base.
- [x] 5.2 — `TextLayout` + `TextLayoutEngine` (lays out spans against constraints; returns a layout object the compositor can render).
- [x] 5.3 — `TextIndexMap` value type with grapheme/cell/UTF-16 mappings; tests for emoji, CJK, combining marks, ZWJ.
- [x] 5.4 — `PersistentUtf8Text` for arena-allocated reusable text.
- [x] 5.5 — Refactor `RenderParagraph` to use `TextLayout` (instead of direct `TextBuffer`).
- [x] 5.6 — Refactor `TextInput` and `TextArea` cursor movement + selection through `TextIndexMap`.
- [x] 5.7 — Refactor `Select` widget option rendering off `name.length` / `description.length`.
- [x] 5.8 — Refactor `TextBuffer.setCell` to stop using `char.codeUnitAt(0)`.
- [x] 5.9 — Resolve `lib/src/widgets/text.dart:9` re-export of `TextOverflow` (lives with the new layout primitives now).
- [x] 5.10 — Land `test/architecture/unicode_guard_test.dart` with an initial allowlist of files that still index by code unit; shrink to zero by 5.11.
- [x] 5.11 — Unicode test suite: cursor movement across emoji/CJK/combining/ZWJ; selection across multi-cell graphemes; paste multiline Unicode; `obscureText` mask grapheme-correct. Unicode editing tests drive multi-byte input through the integration harness (`mockInput.typeText`) rather than synthetic `KeyEvent` injection, so the UTF-8 path is exercised.

## Hard-rule application

- Old single-style `Text(String, ...)` constructor is replaced by `Text.rich(TextSpan)` or a `Text(String)` convenience that internally delegates to a single-child `TextSpan`. **No legacy adapter retained.**
- No visual width or cursor movement uses `String.length` / `text[i]`.

## Audit gate

- [x] `unicode_guard_test.dart` allowlist empty.
- [x] Emoji + CJK + combining + ZWJ + multiline-selection tests pass.
- [x] `lib/src/widgets/text.dart:9` re-export resolved.
- [x] `dart format` / `dart analyze --fatal-infos` / `dart test test/architecture/` / `dart test` all green.

## What landed

- `RenderParagraph` now records `TextLayout` through the display list instead of owning a native `TextBuffer`.
- `TextLayout` carries wrapped lines, style runs, size, `TextIndexMap`, and source-to-buffer offset mapping for compositor materialization.
- `Text`, `RichText`, text editing widgets, and `Select` use grapheme/cell-aware layout or index helpers for visual width, cursor, selection, paste, and `obscureText` behavior.
- Unicode integration tests cover emoji, CJK, combining marks, ZWJ, multiline paste, selection replacement, and grapheme-correct masking through the parser path.
