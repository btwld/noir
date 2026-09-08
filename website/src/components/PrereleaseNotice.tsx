import type { ReactNode } from 'react';

interface PrereleaseNoticeProps {
  children?: ReactNode;
}

export function PrereleaseNotice({ children }: PrereleaseNoticeProps) {
  return (
    <aside className="prerelease-notice" aria-label="Prerelease notice">
      <strong>Prerelease</strong>
      <div>
        {children ??
          'Noir is an alpha preview. APIs and platform guarantees may change before 1.0.'}
      </div>
    </aside>
  );
}
