import Link from 'next/link';

import { InstallCommand } from '../components/InstallCommand';
import { PrereleaseNotice } from '../components/PrereleaseNotice';
import { TerminalDemo } from '../components/TerminalDemo';

const counterPoster = `NOIR COUNTER

You have pushed the button
this many times:

            3

Up/+ add | Down/- subtract | Enter/Space | Ctrl+C     +`;

export default function HomePage() {
  return (
    <main className="home-page">
      <section className="home-intro" aria-labelledby="home-title">
        <h1 id="home-title">A retained UI tree for the terminal.</h1>
        <p className="home-summary">
          Flutter-like widgets, state, integer-cell layout, focus, input, and
          native OpenTUI rendering—kept behind explicit ownership boundaries.
        </p>
        <PrereleaseNotice />
        <InstallCommand />
        <p className="home-command-note">
          Then run <code>dart run example/counter.dart</code> from the
          repository.
        </p>
      </section>

      <section
        className="home-terminal"
        aria-label="Recorded Noir Counter example"
      >
        <TerminalDemo
          castUrl="/demos/counter.cast"
          cols={64}
          id="home-counter"
          poster={counterPoster}
          rows={18}
          title="Counter — a stateful terminal frame"
        />
      </section>

      <section
        className="architecture-signal"
        aria-labelledby="architecture-title"
      >
        <h2 id="architecture-title">
          One declarative path, five clear owners.
        </h2>
        <ol>
          <li>
            <strong>Widgets</strong> declare immutable configuration.
          </li>
          <li>
            <strong>Elements</strong> preserve identity and dependencies.
          </li>
          <li>
            <strong>RenderObjects</strong> lay out, hit-test, and record paint.
          </li>
          <li>
            <strong>The compositor</strong> carries display lists to OpenTUI
            buffers.
          </li>
          <li>
            <strong>The native layer</strong> owns FFI, handles, ABI, and
            binaries.
          </li>
        </ol>
      </section>

      <nav className="next-reads" aria-label="Choose a next reading path">
        <h2>Choose the next question.</h2>
        <Link href="/docs/getting-started">How do I run my first app?</Link>
        <Link href="/examples#counter">
          What does state look like in a real example?
        </Link>
        <Link href="/docs/architecture-api">
          Which public API tier should I import?
        </Link>
      </nav>
    </main>
  );
}
