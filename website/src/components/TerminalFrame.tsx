import type { CSSProperties } from 'react';

import {
  capturedWith,
  terminalFrames,
  type TerminalRun,
} from '../generated/frames';

const repository = 'https://github.com/conceptadev/noir/blob/main';

// OpenTUI attribute bits, as `packages/noir/tool/capture_doc_frames.dart`
// records them.
// Blink has no meaning in a still frame, so it is not drawn.
const bold = 1 << 0;
const dim = 1 << 1;
const italic = 1 << 2;
const underline = 1 << 3;
const reverse = 1 << 5;
const strike = 1 << 6;

/** Styles one run. Unstyled cells keep the site's terminal ink and surface. */
function runStyle({ fg, bg, attrs = 0 }: TerminalRun) {
  if (fg === undefined && bg === undefined && attrs === 0) return undefined;
  const swapped = (attrs & reverse) !== 0;
  const decorations = [
    attrs & underline ? 'underline' : '',
    attrs & strike ? 'line-through' : '',
  ]
    .filter(Boolean)
    .join(' ');
  return {
    backgroundColor: swapped ? (fg ?? 'var(--terminal-ink)') : bg,
    color: swapped ? (bg ?? 'var(--terminal-screen)') : fg,
    fontStyle: attrs & italic ? 'italic' : undefined,
    fontWeight: attrs & bold ? 700 : undefined,
    opacity: attrs & dim ? 0.6 : undefined,
    textDecorationLine: decorations || undefined,
  } satisfies CSSProperties;
}

interface TerminalFrameProps {
  /** A scene id from `packages/noir/tool/recordings/doc_frames.json`. */
  id: string;
  /** Overrides the caption when a page needs its own wording. */
  title?: string;
}

/**
 * One captured frame, shown as selectable text beside its producing command.
 *
 * The cells come from the checkpoint the page teaches, so the code and the
 * output can never drift apart. The screen keeps the captured grid size and
 * every color and attribute the app painted. Drive mode is headless: a frame
 * proves layout, painted cells, and parsed input, not that one terminal
 * emulator agrees.
 */
export function TerminalFrame({ id, title }: TerminalFrameProps) {
  const frame = terminalFrames[id];
  if (!frame) {
    throw new Error(
      `Unknown captured frame "${id}". Add the scene to ` +
        'packages/noir/tool/recordings/doc_frames.json and recapture.',
    );
  }
  const grid = {
    '--columns': frame.width,
    '--rows': frame.height,
  } as CSSProperties;

  return (
    <figure className="terminal-frame">
      <figcaption>
        <span>{title ?? frame.title}</span>
        <a href={`${repository}/${frame.entrypoint}`}>View source</a>
      </figcaption>
      <pre tabIndex={0}>
        <code style={grid}>
          {frame.runs.map((row, y) => (
            <span key={y}>
              {row.map((run, x) => (
                <span key={x} style={runStyle(run)}>
                  {run.text}
                </span>
              ))}
              {y < frame.runs.length - 1 ? '\n' : null}
            </span>
          ))}
        </code>
      </pre>
      <div className="terminal-frame-meta">
        <code>{frame.command}</code>
        <span>
          {frame.interaction} Captured at {frame.width}×{frame.height} through{' '}
          {capturedWith}.
        </span>
      </div>
    </figure>
  );
}
