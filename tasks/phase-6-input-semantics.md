# Phase 6 — Input semantics (Shortcuts / Actions / Intents)

> **Status:** ✅ DONE
> **Cadence:** per-phase review (M)
> **Depends on:** Phase 3 (InputDispatcher) complete.

## Goal

Stop widgets from parsing raw key strings. Introduce Flutter-style `LogicalKeyboardKey` / `ShortcutActivator` / `Shortcuts` / `Actions` / `Intent` so widgets receive *semantic intents* and key parsing lives only in the input driver. **Hardcoded key-string parsing is deleted from widget classes.**

## References

- [`GOALS.md`](../GOALS.md) §2 (semantic correctness — Flutter parity for input semantics)
- [`tasks/reference-implementation-plan.md`](./reference-implementation-plan.md) §10.3 (focus is good MVP but missing traversal/actions)

## Surfaces to introduce

- `LogicalKeyboardKey` — logical key constants (e.g., `arrowDown`, `enter`, `pageDown`).
- `KeyEvent.logicalKey` + printable `character` — parser output moves from raw key-name strings to semantic key values.
- `ShortcutActivator` — abstract; `SingleActivator`, `CharacterActivator`, etc.
- `Shortcuts` — inherited widget mapping activators → intents.
- `Intent` — abstract semantic verb (`MoveSelectionUpIntent`, `ActivateIntent`, `DismissIntent`, `NextFocusIntent`, `PreviousFocusIntent`).
- `Action<T extends Intent>` — handles an intent.
- `Actions` — inherited widget mapping intent types → actions.
- `FocusTraversalPolicy` — Tab / Shift+Tab traversal.
- `KeyEventResult` (or an equivalent explicit dispatch result) — separates
  handled, ignored, and traversal-deferral outcomes so raw bool callbacks do
  not remain the built-in widget behavior contract.
- `TextInputConnection` — owns text-editing intent application against `TextEditingController` / `TextEditingValue`; no duplicate cursor model.

## Tasks (to be decomposed at architect time)

- [x] **Compatibility drift audit** — recorded to workspace scratch (not retained). Specifically inspect: `lib/src/widgets/select.dart` (hardcodes arrow keys, `j`/`k`, `PageUp`/`PageDown`, `Home`/`End`, `Enter`); `lib/src/widgets/input.dart`; `lib/src/widgets/text_area.dart`; `lib/src/widgets/scroll_box.dart`.
- [x] 6.1 — `LogicalKeyboardKey` constants + `KeyEvent.logicalKey` / printable `character`; parser maps raw ANSI bytes to logical keys in `lib/src/core/stdin_input_driver.dart`.
- [x] 6.2 — Replace or rewrite architecture guards that currently forbid `Shortcuts`, `Actions`, and `Intent`; add positive ownership guards proving semantic input APIs live outside `TuiBinding` lifecycle ownership; update `lib/noir.dart` public API allowlist for the new semantic input surface.
- [x] 6.3 — `Intent` base + concrete intents (`MoveSelection*`, `Scroll*`, `Activate`, `Dismiss`, `NextFocus`, `PreviousFocus`, text-editing intents).
- [x] 6.4 — `ShortcutActivator` + `Shortcuts` widget.
- [x] 6.5 — `Action` + `Actions` widget.
- [x] 6.6 — `FocusTraversalPolicy` + `KeyEventResult`/dispatch-result semantics; remove `FocusManager`'s raw `event.key == 'Tab'` global traversal branch or narrow it behind semantic traversal dispatch so Tab / Shift+Tab route through policy.
- [x] 6.7 — Refactor `Select` widget to consume `MoveSelectionUpIntent` etc. instead of raw key strings.
- [x] 6.8 — Refactor `ScrollBox` widget to consume scroll intents instead of raw key strings.
- [x] 6.9 — Refactor `TextInput` / `TextArea` to use `TextInputConnection` for editing intents against `TextEditingController` / `TextEditingValue`.

## Hard-rule application

- Widgets stop parsing raw key strings — the parsing code is **deleted** from widget classes (not retained as a fallback).
- Raw byte / key-name parsing lives only in `lib/src/core/stdin_input_driver.dart`; widget/framework code works from `LogicalKeyboardKey`, `ShortcutActivator`, and semantic intents.
- Existing raw `FocusNode.onKeyEvent` / global key handler paths must not remain a parallel shortcut/traversal system for built-in widgets. If user-facing raw hooks survive, they are advanced/raw event hooks and cannot own built-in Tab traversal or widget behavior.

## Audit gate

- [x] `Grep` shows no widget file contains raw-key-string matches like `event.key == 'ArrowDown'`.
- [x] `Grep` shows built-in widget/framework code does not switch on raw key-name strings for built-in behavior; parser/test helpers are the only raw-name construction points.
- [x] Architecture tests no longer forbid Phase 6 surfaces and instead guard correct ownership boundaries.
- [x] Tab / Shift+Tab moves focus via traversal policy (not via per-widget intercepts).
- [x] `Select` consumes intents.
- [x] `ScrollBox` consumes intents.
- [x] `TextInput` and `TextArea` editing goes through `TextInputConnection` and does not duplicate cursor/editing ownership outside `TextEditingController`.
- [x] Parser → `InputDispatcher` → `ShortcutActivator` → `Intent` → `Action` verified end-to-end via `createTuiTestApp` / `mockInput` real ANSI byte sequences, not only synthetic `KeyEvent` construction.
- [x] `lib/noir.dart` and `test/architecture/public_api_test.dart` expose only the intended new public semantic input types.
- [x] `dart format` / `dart analyze --fatal-infos` / `dart test test/architecture/` / `dart test` all green.

## What landed

- `KeyEvent` now carries `logicalKey`, printable `character`, modifier flags,
  press/repeat/release state, and explicit `KeyEventResult` dispatch outcomes.
- `StdinInputDriver` maps ANSI, CSI modifiers, Shift+Tab, SGR mouse, paste,
  and Kitty CSI-u bytes to semantic key events, including repeat/release and
  shifted/associated text handling.
- `Shortcuts`, `ShortcutActivator`, `Actions`, `Intent`, concrete widget/text
  intents, `FocusTraversalPolicy`, and `TextInputConnection` are public
  semantic input surfaces guarded by the public API architecture test.
- `Select` and `ScrollBox` consume semantic intents, not raw key strings.
- `TextInput` and `TextArea` route editing through `TextInputConnection`; text
  widgets no longer own duplicated edit transaction logic.
- Parser-backed integration tests cover shortcut/action dispatch, traversal,
  TextArea Tab/Shift+Tab traversal, Select, ScrollBox, key releases, and Kitty
  shifted printable semantics.
