'use client';

import type { Player } from 'asciinema-player';
import { useEffect, useId, useRef, useState } from 'react';

interface TerminalRecordingProps {
  title: string;
  command: string;
  sourceHref: string;
}

const basePath = process.env.NEXT_PUBLIC_NOIR_BASE_PATH ?? '';

export function TerminalRecording({
  title,
  command,
  sourceHref,
}: TerminalRecordingProps) {
  const descriptionId = useId();
  const playerContainer = useRef<HTMLDivElement>(null);
  const [loadFailed, setLoadFailed] = useState(false);

  useEffect(() => {
    const container = playerContainer.current;
    if (!container) return;

    let disposed = false;
    let player: Player | undefined;

    void import('asciinema-player')
      .then((AsciinemaPlayer) => {
        if (disposed) return;
        const prefersReducedMotion = window.matchMedia(
          '(prefers-reduced-motion: reduce)',
        ).matches;
        player = AsciinemaPlayer.create(
          `${basePath}/demos/counter.cast`,
          container,
          {
            autoplay: false,
            controls: true,
            cursorMode: 'steady',
            fit: 'width',
            loop: !prefersReducedMotion,
            poster: 'npt:0:00.1',
            terminalFontFamily:
              'SFMono-Regular, Menlo, Monaco, Consolas, monospace',
          },
        );
      })
      .catch(() => {
        if (!disposed) setLoadFailed(true);
      });

    return () => {
      disposed = true;
      player?.dispose();
    };
  }, []);

  return (
    <figure className="terminal-recording" aria-describedby={descriptionId}>
      <figcaption>
        <span>{title}</span>
        <a href={sourceHref}>View source</a>
      </figcaption>
      <div aria-label={title} ref={playerContainer} />
      {loadFailed ? (
        <p className="terminal-recording-error" role="alert">
          The player could not load.{' '}
          <a href={`${basePath}/demos/counter.cast`}>Download the recording</a>.
        </p>
      ) : null}
      <div className="terminal-recording-meta" id={descriptionId}>
        <code>{command}</code>
        <span>
          Recorded at 64×18 through NoirDriver (NOIR_DRIVE=1). Play to see the
          real rendered cells respond to parsed input.
        </span>
      </div>
    </figure>
  );
}
