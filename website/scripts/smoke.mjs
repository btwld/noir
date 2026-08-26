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
  const browserErrors = [];

  page.on('console', (message) => {
    if (message.type() === 'error') browserErrors.push(message.text());
  });
  page.on('pageerror', (error) => browserErrors.push(error.message));

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
    await page.keyboard.press('Tab');
    const keyboardFocus = await page.evaluate(() => {
      const element = document.activeElement;
      if (!(element instanceof HTMLElement)) return null;
      const style = getComputedStyle(element);
      return { outlineStyle: style.outlineStyle, tagName: element.tagName };
    });
    assert.notEqual(
      keyboardFocus?.tagName,
      'BODY',
      'Tab must move focus to an interactive element',
    );
    assert.notEqual(
      keyboardFocus?.outlineStyle,
      'none',
      'keyboard focus must have a visible outline',
    );
    await page.keyboard.press('Enter');
    await page.waitForURL('**/#nextra-skip-nav');
    assert.equal(
      await page.evaluate(() => document.activeElement?.id),
      'nextra-skip-nav',
      'the homepage skip link must move focus to the main content',
    );

    await page.getByRole('link', { name: /How does state flow/ }).click();
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
      .filter({ hasText: /^State and lifecycle/ })
      .first()
      .waitFor();

    await page.goto(`${baseUrl}/examples`, { waitUntil: 'networkidle' });
    assert.equal(
      await page.getByRole('link', { name: 'Index', exact: true }).count(),
      0,
      'the custom homepage must not appear as an Index documentation page',
    );
    assert.equal(
      await page.getByRole('heading', { name: 'What it proves' }).count(),
      0,
      'example metadata labels must not flatten the document heading hierarchy',
    );
    assert.equal(await page.locator('.terminal-player').count(), 0);
    const playButtons = page.getByRole('button', { name: 'Play recording' });
    assert.equal(
      await playButtons.count(),
      6,
      'the six reviewed recordings must stay attached to the featured examples',
    );
    assert.equal(
      await page.locator('.example-catalog li').count(),
      24,
      'the complete catalog must keep every shipped example',
    );
    await playButtons.nth(0).click();
    await page.locator('.terminal-player > *').waitFor({ state: 'attached' });
    assert.equal(await page.locator('.terminal-player').count(), 1);

    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`${baseUrl}/examples`, { waitUntil: 'networkidle' });
    assert.equal(
      await page.evaluate(
        () =>
          document.documentElement.scrollWidth <=
          document.documentElement.clientWidth,
      ),
      true,
      'the Examples page must not overflow the mobile viewport',
    );

    await page.goto(`${baseUrl}/api`, { waitUntil: 'networkidle' });
    assert.equal(
      await page.locator('.api-surfaces').count(),
      1,
      'the API chooser must use the responsive package-surface layout',
    );
    assert.equal(
      await page.evaluate(
        () =>
          document.documentElement.scrollWidth <=
          document.documentElement.clientWidth,
      ),
      true,
      'the API page must not overflow the mobile viewport',
    );

    await page.setViewportSize({ width: 768, height: 900 });
    await page.goto(`${baseUrl}/api`, { waitUntil: 'networkidle' });
    assert.equal(
      await page
        .locator('.api-surfaces > div')
        .first()
        .evaluate((element) => getComputedStyle(element).display),
      'block',
      'the API chooser must stack when the documentation sidebar narrows its article',
    );

    await page.goto(`${baseUrl}/docs/architecture-api`, {
      waitUntil: 'networkidle',
    });
    assert.equal(
      await page
        .locator('.api-surfaces-detailed > div')
        .first()
        .evaluate((element) => getComputedStyle(element).display),
      'block',
      'the detailed API chooser must stack when the documentation sidebar narrows its article',
    );

    await page.goto(`${baseUrl}/examples`, { waitUntil: 'networkidle' });
    assert.equal(
      await page.evaluate(
        () =>
          document.documentElement.scrollWidth <=
          document.documentElement.clientWidth,
      ),
      true,
      'the Examples page must not overflow when the documentation sidebar narrows its article',
    );
    assert.equal(
      await page
        .locator('.example-brief')
        .first()
        .evaluate((element) => getComputedStyle(element).display),
      'block',
      'example controls must stack when the documentation sidebar narrows the article',
    );
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

    assert.deepEqual(browserErrors, [], 'browser console must stay error-free');

    await page.goto(`${baseUrl}/not-a-real-route`, {
      waitUntil: 'networkidle',
    });
    await page
      .getByRole('heading', {
        name: 'That page isn’t in the Noir documentation.',
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
