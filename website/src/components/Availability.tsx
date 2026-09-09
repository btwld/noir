import Link from 'next/link';
import type { ReactNode } from 'react';

import { availability } from '../generated/availability';

interface AvailabilityProps {
  /** Which package this reader is about to depend on. */
  of: 'noir' | 'companion';
  /** Replaces the default consequence sentence when a page needs its own. */
  children?: ReactNode;
}

const defaults = {
  noir: 'Noir is an alpha prerelease. Its APIs and platform guarantees can change before 1.0.',
  companion:
    'The optional companion package is not on pub.dev yet. Resolve it from a Noir repository checkout.',
} as const;

/**
 * One compact availability label, derived from `TODO.md` and the manifests.
 *
 * Put it where a reader is about to copy a dependency or a command. The
 * installation page owns the detail; this component never repeats it.
 */
export function Availability({ of, children }: AvailabilityProps) {
  const target = availability[of];
  return (
    <aside className="availability" aria-label={`${target.name} availability`}>
      <strong>{target.label}</strong>
      <div>
        {children ?? defaults[of]}{' '}
        <Link href="/docs/installation">Set up your project</Link>.
      </div>
    </aside>
  );
}
