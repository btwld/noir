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

  return (
    <Wrapper metadata={metadata} sourceCode={sourceCode} toc={toc}>
      <MDXContent params={{ mdxPath }} />
    </Wrapper>
  );
}
