import type { ReactNode } from 'react';

import { TerminalDemo } from './TerminalDemo';

interface DemoDetails {
  castUrl: string;
  cols: number;
  id: string;
  poster: string;
  rows: number;
  title: string;
}

interface ExampleSectionProps {
  children: ReactNode;
  controls: string;
  demo?: DemoDetails;
  guideHref: string;
  id: string;
  run: string;
  sourceHref: string;
  testHref: string;
  title: string;
  proves: string;
}

export function ExampleSection({
  children,
  controls,
  demo,
  guideHref,
  id,
  proves,
  run,
  sourceHref,
  testHref,
  title,
}: ExampleSectionProps) {
  return (
    <section className="example-section" id={id}>
      <header className="example-section-header">
        <h2>{title}</h2>
        <p>{proves}</p>
      </header>
      <div className="example-brief">
        <div className="example-run">
          <p className="example-label">Run</p>
          <pre>
            <code>{run}</code>
          </pre>
        </div>
        <div className="example-controls">
          <p className="example-label">Controls</p>
          <p>{controls}</p>
        </div>
      </div>
      <div className="example-how-it-works">
        <h3>How it works</h3>
        {children}
      </div>
      <nav className="example-links" aria-label={`${title} resources`}>
        <a href={sourceHref}>View source</a>
        <a href={testHref}>Read the test</a>
        <a href={guideHref}>Open the guide</a>
      </nav>
      {demo ? (
        <div className="example-watch">
          <TerminalDemo {...demo} />
        </div>
      ) : null}
    </section>
  );
}
