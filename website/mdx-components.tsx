import type { MDXComponents } from 'mdx/types';
import { useMDXComponents as getDocsMDXComponents } from 'nextra-theme-docs';

import { InstallCommand } from './src/components/InstallCommand';
import { PrereleaseNotice } from './src/components/PrereleaseNotice';
import { TerminalFrame } from './src/components/TerminalFrame';

export function useMDXComponents(components: MDXComponents): MDXComponents {
  return {
    ...getDocsMDXComponents(),
    ...components,
    InstallCommand,
    PrereleaseNotice,
    TerminalFrame,
  };
}
