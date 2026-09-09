import { capturedWith, terminalFrames } from '../generated/frames';

const repository = 'https://github.com/conceptadev/noir/blob/main';

interface TerminalFrameProps {
  /** A scene id from `scripts/recordings/doc_frames.json`. */
  id: string;
  /** Overrides the caption when a page needs its own wording. */
  title?: string;
}

/**
 * One captured frame, shown as selectable text beside its producing command.
 *
 * The cells come from the checkpoint the page teaches, so the code and the
 * output can never drift apart. Drive mode is headless: a frame proves layout,
 * painted cells, and parsed input, not that one terminal emulator agrees.
 */
export function TerminalFrame({ id, title }: TerminalFrameProps) {
  const frame = terminalFrames[id];
  if (!frame) {
    throw new Error(
      `Unknown captured frame "${id}". Add the scene to ` +
        'scripts/recordings/doc_frames.json and recapture.',
    );
  }

  return (
    <figure className="terminal-frame">
      <figcaption>
        <span>{title ?? frame.title}</span>
        <a href={`${repository}/${frame.entrypoint}`}>View source</a>
      </figcaption>
      <pre tabIndex={0}>
        <code>{frame.lines.join('\n')}</code>
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
