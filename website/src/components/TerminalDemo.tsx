'use client';

import type { Player } from 'asciinema-player';
import { useEffect, useId, useRef, useState } from 'react';

const deactivateEvent = 'noir-terminal-demo:deactivate';

interface TerminalDemoProps {
  castUrl: string;
  cols: number;
  id: string;
  poster: string;
  rows: number;
  title: string;
}

interface DeactivateEvent extends Event {
  detail: string;
}

export function TerminalDemo({
  castUrl,
  cols,
  id,
  poster,
  rows,
  title,
}: TerminalDemoProps) {
  const [active, setActive] = useState(false);
  const [failed, setFailed] = useState(false);
  const [reducedMotion, setReducedMotion] = useState(false);
  const playerRef = useRef<Player | null>(null);
  const hostRef = useRef<HTMLDivElement | null>(null);
  const titleId = useId();

  function disposePlayer() {
    playerRef.current?.dispose();
    playerRef.current = null;
  }

  useEffect(() => {
    const media = window.matchMedia('(prefers-reduced-motion: reduce)');
    const update = () => setReducedMotion(media.matches);
    update();
    media.addEventListener('change', update);
    return () => media.removeEventListener('change', update);
  }, []);

  useEffect(() => {
    const handleDeactivate = (event: Event) => {
      const detail = (event as DeactivateEvent).detail;
      if (detail === id) return;
      disposePlayer();
      setActive(false);
      setFailed(false);
    };
    window.addEventListener(deactivateEvent, handleDeactivate);
    return () => {
      window.removeEventListener(deactivateEvent, handleDeactivate);
      disposePlayer();
    };
  }, [id]);

  useEffect(() => {
    if (!active || failed || !hostRef.current) return;

    let cancelled = false;
    const host = hostRef.current;

    async function mountPlayer() {
      try {
        const asciinema = await import('asciinema-player');
        if (cancelled) return;
        const player = asciinema.create(castUrl, host, {
          autoplay: false,
          cols,
          controls: true,
          cursorMode: 'steady',
          fit: 'width',
          idleTimeLimit: 2,
          loop: false,
          preload: false,
          rows,
        });
        if (cancelled) {
          player.dispose();
          return;
        }
        playerRef.current = player;
        await player.play();
      } catch {
        if (!cancelled) {
          setFailed(true);
        }
      }
    }

    void mountPlayer();
    return () => {
      cancelled = true;
      disposePlayer();
    };
  }, [active, castUrl, cols, failed, rows]);

  function activate() {
    window.dispatchEvent(new CustomEvent(deactivateEvent, { detail: id }));
    setFailed(false);
    setActive(true);
  }

  return (
    <figure className="terminal-demo" data-demo-id={id}>
      <figcaption id={titleId}>
        <span>{title}</span>
        <span className="terminal-demo-caption">
          Recorded headlessly with NoirDriver
        </span>
      </figcaption>
      {!active || failed ? (
        <pre className="terminal-poster" aria-labelledby={titleId}>
          {poster}
        </pre>
      ) : (
        <div
          className="terminal-player"
          ref={hostRef}
          aria-labelledby={titleId}
        />
      )}
      <div className="terminal-demo-actions">
        {!active || failed ? (
          <button type="button" onClick={activate}>
            {failed ? 'Try playback again' : 'Play recording'}
          </button>
        ) : (
          <button
            type="button"
            onClick={() => {
              disposePlayer();
              setActive(false);
            }}
          >
            Return to poster
          </button>
        )}
        <a href={castUrl}>Download .cast</a>
      </div>
      {reducedMotion ? (
        <p className="terminal-demo-note">
          Reduced motion is enabled. This recording remains still until you
          choose Play.
        </p>
      ) : null}
      {failed ? (
        <p className="terminal-demo-note" role="status">
          Playback could not load. The poster, run command, and source links
          remain available.
        </p>
      ) : null}
    </figure>
  );
}
