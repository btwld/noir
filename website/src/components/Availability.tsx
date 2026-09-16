import Link from 'next/link';
import type { ReactNode } from 'react';

import { availability } from '../generated/availability';

interface AvailabilityProps {
  /** Which package this reader is about to depend on. */
  of: 'noir' | 'driver' | 'companion';
  /** Replaces the default consequence sentence when a page needs its own. */
  children?: ReactNode;
  /** Set false on the installation page itself, which owns the detail. */
  setup?: boolean;
}

const defaults = {
  noir: 'Noir is an alpha prerelease. Its APIs and platform guarantees can change before 1.0.',
  driver: availability.driver.isPublished
    ? 'The optional driver package runs your app headlessly so a test can assert on what it painted.'
    : 'The optional driver package is not on pub.dev yet. Resolve it from a Noir repository checkout.',
  companion: availability.companion.isPublished
    ? 'The optional companion package adds lifecycle hooks and Signals integration.'
    : 'The optional companion package is not on pub.dev yet. Resolve it from a Noir repository checkout.',
} as const;

/**
 * One compact availability label, derived from `publication.json` and the manifests.
 *
 * Put it where a reader is about to copy a dependency or a command. The
 * installation page owns the detail; this component never repeats it.
 */
export function Availability({
  of,
  children,
  setup = true,
}: AvailabilityProps) {
  const target = availability[of];
  return (
    <aside className="availability" aria-label={`${target.name} availability`}>
      <strong>{target.label}</strong>
      <div>
        {children ?? defaults[of]}
        {setup ? (
          <>
            {' '}
            <Link href="/docs/installation">Set up your project</Link>.
          </>
        ) : null}
      </div>
    </aside>
  );
}
