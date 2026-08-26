import type { Metadata } from 'next';
import Link from 'next/link';

export const metadata: Metadata = {
  title: 'Page not found',
};

export default function NotFound() {
  return (
    <main className="not-found" id="nextra-skip-nav" tabIndex={-1}>
      <p>404</p>
      <h1>That page isn’t in the Noir documentation.</h1>
      <p className="not-found-summary">
        Start with your first app, return to the guides, or choose a supported
        API surface.
      </p>
      <nav className="not-found-links" aria-label="Documentation recovery">
        <Link href="/docs/getting-started">Getting started</Link>
        <Link href="/docs/widgets-layout">Widgets and layout</Link>
        <Link href="/api">API</Link>
      </nav>
    </main>
  );
}
