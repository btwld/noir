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
    default: 'Noir — reactive terminal UI for Dart',
    template: '%s · Noir',
  },
};

const repository = 'https://github.com/leoafarias/noir';

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
      Noir is a prerelease.{' '}
      <Link href="/docs/platform-limitations">
        Review platform support and known limitations.
      </Link>
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
        <Layout
          copyPageButton={false}
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
