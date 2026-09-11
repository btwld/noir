# Current Nextra patterns

Use this reference for Nextra 4-style implementation. Verify the live official
sources before writing code because Nextra and Next.js can change independently.

## Primary sources

- Docs Theme setup: <https://nextra.site/docs/docs-theme/start>
- File conventions: <https://nextra.site/docs/file-conventions>
- Layout component: <https://nextra.site/docs/docs-theme/built-ins/layout>
- Search setup: <https://nextra.site/docs/guide/search>
- Current official docs example:
  <https://github.com/shuding/nextra/tree/main/examples/docs>
- Current example configuration:
  <https://github.com/shuding/nextra/blob/main/examples/docs/next.config.mjs>
- Current example layout:
  <https://github.com/shuding/nextra/blob/main/examples/docs/src/app/layout.jsx>
- Current content-directory catch-all:
  <https://github.com/shuding/nextra/blob/main/examples/docs/src/app/docs/%5B%5B...mdxPath%5D%5D/page.jsx>

Do not use <https://github.com/shuding/nextra-docs-template> as the current
contract. It remains useful historical material, but its checked-in scaffold
uses Next.js 13, the Pages Router, and `theme.config.tsx`.

## Minimal configuration shape

Adapt this shape to the installed release. Omit `contentDirBasePath` for
colocated `app/**/page.mdx` content.

```js
// next.config.mjs
import nextra from 'nextra'

const withNextra = nextra({
  contentDirBasePath: '/docs',
  search: {
    codeblocks: false
  }
})

export default withNextra({
  reactStrictMode: true
})
```

The Nextra 4 configuration does not select the Docs Theme through `theme` or
`themeConfig`. Compose the theme in the App Router layout instead.

## MDX components shape

```js
// mdx-components.js
import { useMDXComponents as getDocsMDXComponents } from 'nextra-theme-docs'

const docsComponents = getDocsMDXComponents()

export const useMDXComponents = components => ({
  ...docsComponents,
  ...components
})
```

If the project uses TypeScript, follow the current official typing guidance
rather than inventing a broad `any` type.

## Docs Theme layout shape

```jsx
import { Footer, Layout, Navbar } from 'nextra-theme-docs'
import { Head } from 'nextra/components'
import { getPageMap } from 'nextra/page-map'
import 'nextra-theme-docs/style.css'

const navbar = <Navbar logo={<b>Project</b>} />
const footer = <Footer>Project documentation</Footer>

export default async function RootLayout({ children }) {
  return (
    <html lang="en" dir="ltr" suppressHydrationWarning>
      <Head />
      <body>
        <Layout
          navbar={navbar}
          pageMap={await getPageMap()}
          docsRepositoryBase="https://github.com/owner/repository/tree/main"
          footer={footer}
        >
          {children}
        </Layout>
      </body>
    </html>
  )
}
```

Replace every placeholder with repository facts. Keep the layout async because
`getPageMap()` is asynchronous.

## Content-directory catch-all

When content lives outside `app/`, follow the current official example and
adapt the import path to the project's `mdx-components.*` file:

```jsx
import { generateStaticParamsFor, importPage } from 'nextra/pages'
import { useMDXComponents as getMDXComponents } from '../../../../mdx-components'

export const generateStaticParams = generateStaticParamsFor('mdxPath')

export async function generateMetadata({ params }) {
  const { mdxPath } = await params
  const { metadata } = await importPage(mdxPath)
  return metadata
}

const Wrapper = getMDXComponents().wrapper

export default async function Page(props) {
  const params = await props.params
  const { default: MDXContent, toc, metadata, sourceCode } =
    await importPage(params.mdxPath)

  return (
    <Wrapper toc={toc} metadata={metadata} sourceCode={sourceCode}>
      <MDXContent {...props} params={params} />
    </Wrapper>
  )
}
```

Confirm the catch-all parameter name and import behavior against the installed
Nextra version before relying on this snippet.

## Pagefind search

Nextra's current local search integration uses Pagefind. Install `pagefind` as
a development dependency and index only after a successful Next.js build.

For a server build:

```json
{
  "scripts": {
    "build": "next build",
    "postbuild": "pagefind --site .next/server/app --output-path public/_pagefind"
  }
}
```

For a static export, direct output to `out/_pagefind`. Add `_pagefind/` to the
web app's ignore rules, build, confirm the directory exists, and test a query
in the built application.

## Custom homepage boundary

Keep marketing and documentation concerns separate even when they share a
Next.js app:

- Let `app/page.*` own the custom landing page.
- Let Nextra own MDX compilation, page maps, documentation chrome, and search.
- Hide or classify the homepage with current `_meta.*` options as needed.
- Share intentional brand tokens and primitives; do not override Nextra with a
  large global CSS reset that breaks docs typography or focus states.
- Verify the official example before introducing route-group-specific layouts.

For Noir, derive product claims and API examples from the current source,
tests, `CHANGELOG.md`, `publication.json`, and `GOALS.md`. Do not describe the prerelease as stable.
