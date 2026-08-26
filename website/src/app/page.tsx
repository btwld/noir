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
    <main className="home-page" id="nextra-skip-nav" tabIndex={-1}>
      <section className="home-intro" aria-labelledby="home-title">
        <h1 id="home-title">Build reactive terminal UIs in Dart.</h1>
        <p className="home-summary">
          Noir brings Flutter-like widgets, state, layout, focus, and input to
          Dart terminal apps. Native OpenTUI rendering stays behind explicit
          framework boundaries.
        </p>
        <PrereleaseNotice />
        <InstallCommand />
        <p className="home-command-note">
          Working from a repository checkout? Run{' '}
          <code>dart run example/counter.dart</code> to try Counter.
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
          From widget declaration to terminal output.
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
        <h2>Where do you want to go next?</h2>
        <Link href="/docs/getting-started">How do I run my first app?</Link>
        <Link href="/examples#counter">
          How does state flow through a real example?
        </Link>
        <Link href="/docs/architecture-api">
          Which public API tier should I import?
        </Link>
      </nav>
    </main>
  );
}
