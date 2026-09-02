'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';

export default function DocsPage() {
  const router = useRouter();

  useEffect(() => {
    router.replace('/docs/getting-started');
  }, [router]);

  return (
    <main className="not-found" id="nextra-skip-nav" tabIndex={-1}>
      <h1>Noir documentation</h1>
      <p>
        Continue to <Link href="/docs/getting-started">Getting started</Link>.
      </p>
    </main>
  );
}
