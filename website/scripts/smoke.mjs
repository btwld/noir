import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { once } from 'node:events';
import { join } from 'node:path';

import { chromium } from '@playwright/test';

const websiteRoot = process.cwd();
const port = Number(process.env.NOIR_WEBSITE_PORT ?? 3018);
const suppliedUrl = process.env.NOIR_WEBSITE_URL;
const baseUrl = suppliedUrl ?? `http://localhost:${port}`;
const chromeOnMac =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

let server;
let serverOutput = '';

function appendServerOutput(chunk) {
  serverOutput += chunk.toString();
}

async function waitForServer() {
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(baseUrl);
      if (response.ok) return;
    } catch {
      // Next is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error(`Timed out waiting for ${baseUrl}.\n${serverOutput}`);
}

async function startServer() {
  if (suppliedUrl) return;

  if (!existsSync(join(websiteRoot, '.next', 'BUILD_ID'))) {
    throw new Error('Run npm run build before npm run test:smoke.');
  }

  server = spawn(
    process.execPath,
    [
      'node_modules/next/dist/bin/next',
      'start',
      '--hostname',
      '127.0.0.1',
      '--port',
      String(port),
    ],
    { cwd: websiteRoot, stdio: ['ignore', 'pipe', 'pipe'] },
  );
  server.stdout.on('data', appendServerOutput);
  server.stderr.on('data', appendServerOutput);
  await waitForServer();
}

async function stopServer() {
  if (!server || server.exitCode !== null) return;
  const exited = once(server, 'exit');
  server.kill();
  await exited;
}

async function launchBrowser() {
  try {
    return await chromium.launch({ headless: true });
  } catch (error) {
    if (!existsSync(chromeOnMac)) throw error;
    return chromium.launch({ executablePath: chromeOnMac, headless: true });
  }
}

async function runSmoke() {
  const browser = await launchBrowser();
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    await page.goto(baseUrl, { waitUntil: 'networkidle' });
    await assert.rejects(
      () =>
        page
          .locator('.terminal-player')
          .waitFor({ state: 'attached', timeout: 250 }),
      /Timeout/,
      'recordings must stay as posters until the reader chooses Play',
    );

    await page.getByRole('link', { name: /What does state look like/ }).click();
    await page.waitForURL('**/examples#counter');
    await page.getByRole('link', { name: 'Hooks guide' }).click();
    await page.waitForURL('**/docs/hooks');
    assert.equal(
      await page
        .getByRole('link', { name: 'Hooks Counter' })
        .getAttribute('href'),
      'https://github.com/leoafarias/noir/blob/main/example/hooks_counter.dart',
      'the Hooks source link must point to the repository',
    );
    const search = page.getByRole('combobox', {
      name: 'Search documentation…',
    });
    await search.click();
    await search.fill('state');
    await page
      .locator('[role="option"]')
      .filter({ hasText: /^State & Lifecycle/ })
      .first()
      .waitFor();

    await page.goto(`${baseUrl}/examples`, { waitUntil: 'networkidle' });
    assert.equal(await page.locator('.terminal-player').count(), 0);
    const playButtons = page.getByRole('button', { name: 'Play recording' });
    await playButtons.nth(0).click();
    await page.locator('.terminal-player > *').waitFor({ state: 'attached' });
    assert.equal(await page.locator('.terminal-player').count(), 1);
    await playButtons.nth(1).click();
    await page.locator('.terminal-player > *').waitFor({ state: 'attached' });
    assert.equal(await page.locator('.terminal-player').count(), 1);

    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.goto(baseUrl, { waitUntil: 'networkidle' });
    await page
      .getByText(
        'Reduced motion is enabled. This recording remains still until you choose Play.',
      )
      .waitFor();
    assert.equal(await page.locator('.terminal-player').count(), 0);

    await context.grantPermissions(['clipboard-read', 'clipboard-write'], {
      origin: baseUrl,
    });
    await page.getByRole('button', { name: 'Copy' }).click();
    await page.getByRole('button', { name: 'Copied' }).waitFor();
    assert.equal(
      await page.evaluate(() => navigator.clipboard.readText()),
      'dart pub add noir',
    );

    await page.goto(`${baseUrl}/not-a-real-route`, {
      waitUntil: 'networkidle',
    });
    await page
      .getByRole('heading', {
        name: 'This page is not part of Noir’s small documentation set.',
      })
      .waitFor();
  } finally {
    await browser.close();
  }
}

try {
  await startServer();
  await runSmoke();
  console.log('Website smoke test passed.');
} catch (error) {
  if (serverOutput) process.stderr.write(serverOutput);
  throw error;
} finally {
  await stopServer();
}
