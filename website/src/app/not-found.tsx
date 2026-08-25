import Link from 'next/link';

export default function NotFound() {
  return (
    <main className="not-found">
      <p>404</p>
      <h1>This page is not part of Noir’s small documentation set.</h1>
      <Link href="/docs/getting-started">Start with Getting Started</Link>
    </main>
  );
}
