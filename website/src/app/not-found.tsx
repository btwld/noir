import Link from 'next/link';

export default function NotFound() {
  return (
    <main className="not-found">
      <p>404</p>
      <h1>That page isn’t in the Noir documentation.</h1>
      <Link href="/docs/getting-started">Go to Getting started</Link>
    </main>
  );
}
