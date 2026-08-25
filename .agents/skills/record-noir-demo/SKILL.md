---
name: record-noir-demo
description: Capture and validate real Noir example animations or scripted interactions as local asciicast `.cast` recordings for documentation and design review. Use when a user asks to record, replay, animate, export, or locally save a Noir terminal demo, create a terminal example for a docs site, or prepare a GIF/video fallback from a Noir example.
---

# Record Noir Demo

Capture the actual cells painted by a shipped Noir example through the existing
drive-mode client. Default to the non-terminal path: it preserves characters,
24-bit colors, attributes, cursor state, and production-parser input without a
TTY or raw mode.

## Workflow

1. Read `TODO.md`, `GOALS.md`, the target file under `example/`, and its nearest
   focused test before choosing the visible sequence.
2. Define one message and one proof. Prefer a 3–8 second recording with one
   interaction or one complete animation cycle.
3. Create a versioned JSON recipe. Read [references/recipes.md](references/recipes.md)
   for its schema and action forms.
4. Save local review output under `.context/demos/`. Use a tracked
   `website/public/demos/` destination only when the website exists and the user
   has asked to publish the artifact.
5. Run:

   ```sh
   dart run scripts/record_noir_demo.dart --recipe <recipe.json>
   ```

   The recorder refuses to overwrite an existing artifact. Pass `--force` only
   when replacement is explicitly intended.
6. Parse every line of the result as JSON. Confirm an asciicast v2 header, the
   expected geometry and duration, more than one changed output frame for an
   animation, and visible text unique to the example.
7. Report the recipe and artifact paths, dimensions, duration, frame/event
   counts, and capture boundary.

## Choose the output path

- Use asciicast for the documentation site. It stays cell-sharp, carries timing
  and input, and can be self-hosted with `asciinema-player`.
- Generate GIF only as a compatibility fallback through `agg` when the user
  needs an image-only destination. Set `--fps-cap` above the recipe cadence
  (for example, cap a 30 fps cast at 60) because equal rounded timestamps can
  otherwise merge source frames.
- Use VHS for WebM/MP4 or an actual terminal-emulator recording only when the
  user explicitly authorizes PTY/raw-terminal capture. Name that stronger proof
  separately; do not silently substitute it for drive mode.

## Preserve the evidence boundary

- Drive-mode output is real Noir rendering from OpenTUI's non-terminal testing
  renderer. It is not evidence of raw-mode cleanup or a named terminal emulator.
- The asciicast command header must name `NoirDriver (NOIR_DRIVE=1)` so a
  replay cannot be mistaken for a real shell or terminal-emulator capture.
- It does not prove Kitty, Sixel, OSC52, tmux, or Screen behavior.
- Do not import repository test helpers or invent another harness. Compose the
  existing `scripts/driver/noir_driver.dart` client.
- Do not include secrets, personal data, shell history, or unrelated output.
- Keep autoplay off in documentation. Provide a static poster and honor reduced
  motion.

## Review the artifact

Treat a successful process exit as necessary but insufficient. Inspect the cast
metadata and content. When a web player is available, play the entire loop and
check cell geometry, pacing, colors, cursor behavior, legibility, and cleanup.
For a GIF fallback, also decode it and check frame count plus frame delays
against the cast; the conversion exit code does not prove preserved timing.
Keep one recording active on a page; additional examples should be click-to-play.
