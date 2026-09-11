import type { Metadata } from 'next';
import Link from 'next/link';
import type { ReactNode } from 'react';
import type { Folder, MetaJsonFile, PageMapItem } from 'nextra';
import { Head } from 'nextra/components';
import { getPageMap } from 'nextra/page-map';
import { Footer, Layout, Navbar } from 'nextra-theme-docs';

import 'asciinema-player/dist/bundle/asciinema-player.css';
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

const repository = 'https://github.com/conceptadev/noir';

const navbar = (
  <Navbar logo={<span className="wordmark">Noir</span>}>
    <Link className="site-nav-link" href="/docs">
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

const isMeta = (item: PageMapItem): item is MetaJsonFile => 'data' in item;

/**
 * Lifts the documentation groups to the top of the sidebar.
 *
 * Every guide lives under `/docs`, so the raw page map wraps the whole tree in
 * one collapsible Docs folder. The navbar already names Docs; the sidebar
 * should open on the groups. Routes do not change.
 */
function liftDocs(pageMap: PageMapItem[]): PageMapItem[] {
  const docs = pageMap.find(
    (item): item is Folder => 'children' in item && item.name === 'docs',
  );
  if (!docs) throw new Error('The page map has no docs folder to lift.');
  const rootMeta = { ...pageMap.find(isMeta)?.data };
  delete rootMeta.docs;
  return [
    { data: { ...docs.children.find(isMeta)?.data, ...rootMeta } },
    ...docs.children.filter((item) => !isMeta(item)),
    ...pageMap.filter((item) => item !== docs && !isMeta(item)),
  ];
}

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
          // Chapter order belongs to a tutorial, not to the whole document
          // tree. Lessons link forward in their own prose.
          navigation={false}
          pageMap={liftDocs(await getPageMap())}
          sidebar={{ defaultMenuCollapseLevel: 1 }}
        >
          {children}
        </Layout>
      </body>
    </html>
  );
}
