import type { MDXComponents } from 'mdx/types';
import { useMDXComponents as getDocsMDXComponents } from 'nextra-theme-docs';

import { InstallCommand } from './src/components/InstallCommand';
import { PrereleaseNotice } from './src/components/PrereleaseNotice';
import { TerminalRecording } from './src/components/TerminalRecording';

export function useMDXComponents(components: MDXComponents): MDXComponents {
  return {
    ...getDocsMDXComponents(),
    ...components,
    InstallCommand,
    PrereleaseNotice,
    TerminalRecording,
  };
}
