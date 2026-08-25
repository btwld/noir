import type { Metadata } from 'next';
import Link from 'next/link';
import type { ReactNode } from 'react';
import { Head } from 'nextra/components';
import { getPageMap } from 'nextra/page-map';
import { Footer, Layout, Navbar } from 'nextra-theme-docs';

import 'nextra-theme-docs/style.css';
import './globals.css';

export const metadata: Metadata = {
  description:
    'Noir is a prerelease Flutter-like reactive terminal UI framework for Dart.',
  title: {
    default: 'Noir — terminal UI for Dart',
    template: '%s · Noir',
  },
};

const repository = 'https://github.com/leoafarias/noir';

const designContract = `<!--
QUIET-SIGNAL-2026
THESIS: Noir documentation treats a real terminal frame as evidence, not decoration.
OWN-WORLD: Black-and-white editorial reading, hairline rules, and one terminal anchor.
STORY: A Dart developer installs Noir, understands retained rendering, and chooses a safe next step.
FIRST VIEWPORT: A short promise, copyable install command, and Counter poster lead the page.
FORM: Quiet Signal; user-supplied implementation direction; seed quiet-signal-2026.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.
-->`;

const navbar = (
  <Navbar logo={<span className="wordmark">Noir</span>}>
    <Link className="site-nav-link" href="/">
      Home
    </Link>
    <Link className="site-nav-link" href="/docs/getting-started">
      Docs
    </Link>
    <Link className="site-nav-link" href="/examples">
      Examples
    </Link>
    <Link className="site-nav-link" href="/api">
      API
    </Link>
    <a className="site-nav-link site-nav-github" href={repository}>
      GitHub
    </a>
  </Navbar>
);

const footer = (
  <Footer>
    <span>
      Noir is a prerelease. Read the limits before making a platform promise.
    </span>
  </Footer>
);

export default async function RootLayout({
  children,
}: Readonly<{ children: ReactNode }>) {
  return (
    <html data-scroll-behavior="smooth" lang="en" suppressHydrationWarning>
      <Head
        color={{
          hue: 0,
          lightness: { dark: 100, light: 12 },
          saturation: 0,
        }}
      />
      <body>
        <template
          data-design-contract="quiet-signal-2026"
          dangerouslySetInnerHTML={{ __html: designContract }}
        />
        <Layout
          docsRepositoryBase={`${repository}/tree/main/website`}
          editLink="View source on GitHub"
          feedback={{
            content: 'Report a documentation issue',
            labels: 'documentation',
          }}
          footer={footer}
          navbar={navbar}
          pageMap={await getPageMap()}
          sidebar={{ defaultMenuCollapseLevel: 1 }}
        >
          {children}
        </Layout>
      </body>
    </html>
  );
}
