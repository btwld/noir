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
        Start with your first app, return to the guides, run an example, or look
        up an API.
      </p>
      <nav className="not-found-links" aria-label="Documentation recovery">
        <Link href="/docs/getting-started">Your first app</Link>
        <Link href="/docs">Documentation</Link>
        <Link href="/examples">Examples</Link>
        <Link href="/api">API</Link>
      </nav>
    </main>
  );
}
