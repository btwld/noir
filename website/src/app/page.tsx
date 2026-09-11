import Link from 'next/link';

import { Availability } from '../components/Availability';
import { HighlightedCode } from '../components/HighlightedCode';
import { InstallCommand } from '../components/InstallCommand';
import { TerminalFrame } from '../components/TerminalFrame';
import { firstAppStateHtml } from '../generated/checkpoints';

export default function HomePage() {
  return (
    <main className="home-page" id="nextra-skip-nav" tabIndex={-1}>
      <section className="home-hero" aria-labelledby="home-title">
        <h1 id="home-title">Build terminal apps in Dart.</h1>
        <div className="home-hero-copy">
          <p className="home-summary">
            Noir gives a terminal program a widget tree, retained state, and
            layout measured in cells.
          </p>
          <p className="home-actions">
            <Link className="home-primary-action" href="/docs/getting-started">
              Build your first app
            </Link>
            <Link href="/examples">Run an example</Link>
          </p>
          <InstallCommand />
          <p className="home-command-note">Requires Dart 3.10 or later.</p>
        </div>
      </section>

      <section className="home-proof" aria-labelledby="proof-title">
        <h2 id="proof-title">Press the button to update the count.</h2>
        <div className="home-proof-pair">
          <HighlightedCode
            caption="The retained State of the first-app tutorial"
            html={firstAppStateHtml}
          />
          <TerminalFrame
            id="first-app-count"
            title="The same file after one Space press"
          />
        </div>
      </section>

      <Availability of="noir" />

      <section className="capability-index" aria-labelledby="capability-title">
        <h2 id="capability-title">
          Build with text, inputs, lists, and dialogs.
        </h2>
        <p>
          Compose the screen from public widgets instead of writing escape
          sequences around raw terminal output.
        </p>
        <div>
          <article>
            <h3>Layout in cells</h3>
            <p>
              Row, Column, Flex, Stack, Wrap, overlays, borders, and scrolling
              use integer terminal geometry.
            </p>
            <Link href="/docs/widgets-layout">Learn the layout model</Link>
          </article>
          <article>
            <h3>Input with ownership</h3>
            <p>
              Focus traversal, shortcuts, editable text, pointer hit testing,
              and wheel input share one ordered pipeline.
            </p>
            <Link href="/docs/input-focus">Route input correctly</Link>
          </article>
          <article>
            <h3>Controls and data</h3>
            <p>
              Buttons, fields, selects, tabs, sliders, lists, and data tables
              keep values explicit and keyboard behavior predictable.
            </p>
            <Link href="/docs/widget-catalog">Browse the widget catalog</Link>
          </article>
          <article>
            <h3>Terminal documents</h3>
            <p>
              CodeView, DiffView, MarkdownView, rich tables, hyperlinks, and
              terminal images live on the same retained render path.
            </p>
            <Link href="/docs/widget-catalog#documents-and-media">
              Find document widgets
            </Link>
          </article>
        </div>
      </section>

      <nav className="next-reads" aria-label="Choose a next reading path">
        <h2>Start with the work in front of you.</h2>
        <Link href="/docs/getting-started">Build and edit a first app</Link>
        <Link href="/docs/signals-task-list">
          Learn reactive state by building a task list
        </Link>
        <Link href="/docs/widget-catalog">Find the widget for a UI job</Link>
        <Link href="/docs/architecture-api">
          Follow an event through the retained architecture
        </Link>
      </nav>
    </main>
  );
}
