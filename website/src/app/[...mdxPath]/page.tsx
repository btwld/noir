import { generateStaticParamsFor, importPage } from 'nextra/pages';

import { useMDXComponents as getMDXComponents } from '../../../mdx-components';

export const generateStaticParams = generateStaticParamsFor('mdxPath');
export const dynamicParams = false;

interface PageProps {
  params: Promise<{ mdxPath: string[] }>;
}

export async function generateMetadata({ params }: PageProps) {
  const { mdxPath } = await params;
  const { metadata } = await importPage(mdxPath);
  return metadata;
}

const Wrapper = getMDXComponents({}).wrapper!;

export default async function Page({ params }: PageProps) {
  const { mdxPath } = await params;
  const {
    default: MDXContent,
    metadata,
    sourceCode,
    toc,
  } = await importPage(mdxPath);
  const filePath =
    'sourceUrl' in metadata && typeof metadata.sourceUrl === 'string'
      ? metadata.sourceUrl
      : metadata.filePath;

  return (
    <Wrapper
      metadata={{ ...metadata, filePath }}
      sourceCode={sourceCode}
      toc={toc}
    >
      <MDXContent params={{ mdxPath }} />
    </Wrapper>
  );
}
