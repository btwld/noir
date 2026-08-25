import type { MDXComponents } from 'mdx/types';
import { useMDXComponents as getDocsMDXComponents } from 'nextra-theme-docs';

import { ExampleSection } from './src/components/ExampleSection';
import { InstallCommand } from './src/components/InstallCommand';
import { PrereleaseNotice } from './src/components/PrereleaseNotice';
import { TerminalDemo } from './src/components/TerminalDemo';

export function useMDXComponents(components: MDXComponents): MDXComponents {
  return {
    ...getDocsMDXComponents(),
    ...components,
    ExampleSection,
    InstallCommand,
    PrereleaseNotice,
    TerminalDemo,
  };
}
