import type { MDXComponents } from 'mdx/types';
import { useMDXComponents as getDocsMDXComponents } from 'nextra-theme-docs';

import { Availability } from './src/components/Availability';
import { InstallCommand } from './src/components/InstallCommand';
import { TerminalFrame } from './src/components/TerminalFrame';
import { TerminalRecording } from './src/components/TerminalRecording';

export function useMDXComponents(components: MDXComponents): MDXComponents {
  return {
    ...getDocsMDXComponents(),
    ...components,
    Availability,
    InstallCommand,
    TerminalFrame,
    TerminalRecording,
  };
}
