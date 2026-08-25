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
      <header>
        <h2>{title}</h2>
        <h3>What it proves</h3>
        <p>{proves}</p>
      </header>
      <div className="example-run">
        <h3>Run it</h3>
        <pre>
          <code>{run}</code>
        </pre>
      </div>
      <div className="example-how-it-works">
        <h3>How it works</h3>
        {children}
      </div>
      <div className="example-controls">
        <h3>Controls</h3>
        <p>{controls}</p>
      </div>
      <p className="example-links">
        <a href={sourceHref}>Source</a>
        <a href={testHref}>Relevant test</a>
        <a href={guideHref}>Related guide</a>
      </p>
      {demo ? (
        <div className="example-watch">
          <h3>Watch it</h3>
          <TerminalDemo {...demo} />
        </div>
      ) : null}
    </section>
  );
}
