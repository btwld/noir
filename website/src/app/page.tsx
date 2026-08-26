import Link from 'next/link';

import { HighlightedCode } from '../components/HighlightedCode';
import { InstallCommand } from '../components/InstallCommand';
import { PrereleaseNotice } from '../components/PrereleaseNotice';
import { TerminalFrame } from '../components/TerminalFrame';
import {
  counterFrameAfterIncrement,
  expectedCounterBoundary,
} from '../lib/counter-example';
import { counterStateHtml } from '../lib/counter-highlight';

export default function HomePage() {
  return (
    <main className="home-page" id="nextra-skip-nav" tabIndex={-1}>
      <section className="home-intro" aria-labelledby="home-title">
        <h1 id="home-title">Build reactive terminal UIs in Dart.</h1>
        <p className="home-summary">
          Noir gives terminal apps a Flutter-like widget tree, retained state,
          cell-based layout, focus, input, and animation. OpenTUI handles the
          native renderer behind the framework.
        </p>
        <PrereleaseNotice />
        <InstallCommand />
        <p className="home-command-note">
          Requires Dart 3.10 or later.{' '}
          <Link href="/docs/getting-started">Build your first Noir app</Link>.
        </p>
      </section>

      <section className="home-proof" aria-labelledby="proof-title">
        <div className="home-proof-copy">
          <h2 id="proof-title">
            One callback becomes the next terminal frame.
          </h2>
          <p>
            Change retained state from an event. Noir rebuilds the matching
            widget subtree, lays it out in cells, and records the next frame.
          </p>
          <HighlightedCode
            caption="Counter state after one increment"
            html={counterStateHtml}
          />
          <Link href="/docs/getting-started">
            Build this counter and hot-reload it
          </Link>
        </div>
        <TerminalFrame
          boundary={expectedCounterBoundary}
          command="dart run noir:run bin/noir_demo.dart"
          output={counterFrameAfterIncrement}
          title="Counter after one activation"
        />
      </section>

      <section className="capability-index" aria-labelledby="capability-title">
        <h2 id="capability-title">
          The terminal pieces are already in the tree.
        </h2>
        <p>
          Compose the app from public widgets instead of rebuilding layout,
          editing, focus, scrolling, and document behavior around raw escape
          output.
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

      <section
        className="architecture-signal"
        aria-labelledby="architecture-title"
      >
        <h2 id="architecture-title">
          A familiar model, carried to terminal cells.
        </h2>
        <p className="framework-path">
          <span>Widgets</span>
          <span className="path-arrow" aria-hidden="true">
            →
          </span>
          <span>Elements</span>
          <span className="path-arrow" aria-hidden="true">
            →
          </span>
          <span>RenderObjects</span>
          <span className="path-arrow" aria-hidden="true">
            →
          </span>
          <span>Display lists</span>
          <span className="path-arrow" aria-hidden="true">
            →
          </span>
          <span>OpenTUI</span>
        </p>
        <p>
          <Link href="/docs/architecture-api">
            Follow an event through Noir’s retained architecture
          </Link>
        </p>
      </section>

      <nav className="next-reads" aria-label="Choose a next reading path">
        <h2>Start with the work in front of you.</h2>
        <Link href="/docs/getting-started">
          Build and hot-reload a first app
        </Link>
        <Link href="/docs/widget-catalog">Find the widget for a UI job</Link>
        <Link href="/docs/testing">Choose an application test boundary</Link>
        <Link href="/api">Choose a public package surface</Link>
      </nav>
    </main>
  );
}
