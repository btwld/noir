'use client';

import { useState } from 'react';

interface InstallCommandProps {
  command?: string;
}

export function InstallCommand({
  command = 'dart pub add noir',
}: InstallCommandProps) {
  const [copied, setCopied] = useState(false);

  function copyWithSelection() {
    const selection = document.createElement('textarea');
    selection.value = command;
    selection.setAttribute('readonly', '');
    selection.style.left = '-9999px';
    selection.style.position = 'fixed';
    document.body.append(selection);
    selection.select();
    const didCopy = document.execCommand('copy');
    selection.remove();
    return didCopy;
  }

  async function copyCommand() {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
    } catch {
      setCopied(copyWithSelection());
    }
    window.setTimeout(() => setCopied(false), 1800);
  }

  return (
    <div className="install-command" aria-label="Install Noir">
      <code>{command}</code>
      <button type="button" onClick={copyCommand}>
        {copied ? 'Copied' : 'Copy'}
      </button>
      <span className="sr-only" aria-live="polite">
        {copied ? 'Install command copied.' : ''}
      </span>
    </div>
  );
}
