interface TerminalFrameProps {
  title: string;
  output: string;
  command?: string;
  sourceHref?: string;
  boundary?: string;
}

export function TerminalFrame({
  title,
  output,
  command,
  sourceHref,
  boundary,
}: TerminalFrameProps) {
  return (
    <figure className="terminal-frame">
      <figcaption>
        <span>{title}</span>
        {sourceHref ? <a href={sourceHref}>View source</a> : null}
      </figcaption>
      <pre aria-label={title}>
        <code>{output.replace(/[ \t]+$/gm, '')}</code>
      </pre>
      {command || boundary ? (
        <div className="terminal-frame-meta">
          {command ? <code>{command}</code> : null}
          {boundary ? <span>{boundary}</span> : null}
        </div>
      ) : null}
    </figure>
  );
}
