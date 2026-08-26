import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { once } from 'node:events';
import { join } from 'node:path';

import { chromium } from '@playwright/test';

const websiteRoot = process.cwd();
const counterExampleSource = readFileSync(
  join(websiteRoot, 'src/lib/counter-example.ts'),
  'utf8',
);

function readExportedTemplate(name) {
  const match = counterExampleSource.match(
    new RegExp(`export const ${name} = \`([\\s\\S]*?)\`;`),
  );
  if (!match) {
    throw new Error(`Could not find ${name} in counter-example.ts`);
  }
  return match[1];
}

const counterStateSource = readExportedTemplate('counterStateSource');
const expectedCounterFrame = ['', ' Count: 1', '', '  + Add one', ''].join(
  '\n',
);
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
    await page
      .getByRole('heading', { name: 'Build reactive terminal UIs in Dart.' })
      .waitFor();
    assert.equal(
      await page.getByRole('link', { name: 'Examples', exact: true }).count(),
      0,
      'the removed Examples destination must not remain in navigation',
    );
    assert.equal(
      await page.locator('.framework-path > span:not(.path-arrow)').count(),
      5,
      'the homepage must retain the concise framework ownership model',
    );
    assert.equal(
      await page.locator('.home-proof .terminal-frame').count(),
      1,
      'the homepage must pair source with one static terminal proof',
    );
    assert.ok(
      (await page
        .locator('.home-proof .highlighted-code .shiki span')
        .count()) > 8,
      'the homepage counter source must be syntax-highlighted',
    );
    assert.equal(
      await page.locator('.home-proof figure.highlighted-code').count(),
      1,
      'homepage source must be a captioned figure',
    );
    assert.equal(
      await page.locator('.home-proof .highlighted-code pre[tabindex]').count(),
      0,
      'highlighted source must not insert a dead tab stop',
    );
    assert.ok(
      (await page
        .locator('.home-proof .highlighted-code [style*="--shiki-light"]')
        .count()) > 0,
      'homepage highlighting must emit light-theme token variables',
    );
    assert.ok(
      (await page
        .locator('.home-proof .highlighted-code [style*="--shiki-dark"]')
        .count()) > 0,
      'homepage highlighting must emit dark-theme token variables',
    );
    assert.equal(
      (
        await page
          .locator('.home-proof .highlighted-code .shiki .line')
          .allTextContents()
      )
        .join('\n')
        .replace(/\n+$/, ''),
      counterStateSource.replace(/\n+$/, ''),
      'homepage highlighted text must equal the Counter State excerpt',
    );
    assert.ok(
      (await page
        .locator('.home-proof .highlighted-code')
        .getByText('_increment')
        .count()) >= 1,
      'the homepage must show the Counter increment as a named State method',
    );
    assert.equal(
      await page
        .locator('.home-proof .terminal-frame pre code')
        .evaluate((element) => element.textContent),
      expectedCounterFrame,
      'homepage frame must keep Container padding rows as expected cells',
    );
    assert.equal(
      await page.getByText('Driver capture', { exact: false }).count(),
      0,
      'homepage must not claim a Driver capture it does not have',
    );
    assert.equal(
      await page
        .locator('.home-proof .terminal-frame')
        .getByText('Expected cell output', { exact: false })
        .count(),
      1,
      'homepage frame must be labeled as expected cell output',
    );
    assert.equal(
      await page.locator('.capability-index article').count(),
      4,
      'the homepage must expose four concrete capability groups',
    );
    assert.equal(
      await page.locator('.next-reads > a').count(),
      4,
      'the homepage must offer four task-oriented next steps',
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

    await page.goto(`${baseUrl}/docs`, { waitUntil: 'networkidle' });
    assert.equal(
      new URL(page.url()).pathname,
      '/docs/getting-started',
      'the documentation root must lead to the first tutorial',
    );

    await page.goto(`${baseUrl}/docs/getting-started`, {
      waitUntil: 'networkidle',
    });
    const tutorialHeadings = await page.locator('main h2').allTextContents();
    assert.deepEqual(
      tutorialHeadings,
      [
        'Create the project',
        'Build the counter',
        'Run it with hot reload',
        'Change the running app',
      ],
      'Getting started must be a complete, action-led tutorial',
    );
    assert.equal(
      await page
        .locator('main')
        .getByText('dart create -t console noir_demo', { exact: true })
        .count(),
      1,
      'the first-app tutorial must create the Dart package it relies on',
    );
    assert.equal(
      await page
        .locator('main')
        .getByText('dart run noir:run bin/noir_demo.dart', { exact: true })
        .count(),
      2,
      'the tutorial must show the hot-reload command and identify the captured frame command',
    );
    assert.equal(
      await page
        .locator('main h2')
        .first()
        .evaluate((element) => getComputedStyle(element).borderBottomWidth),
      '0px',
      'article headings must rely on whitespace instead of a rule after every section title',
    );
    assert.equal(
      await page
        .locator('main .terminal-frame pre code')
        .evaluate((element) => element.textContent),
      expectedCounterFrame,
      'Getting started must reuse the same expected counter frame as the homepage',
    );
    assert.equal(
      await page.getByText('Driver capture', { exact: false }).count(),
      0,
      'Getting started must not claim a Driver capture it does not have',
    );

    await page.setViewportSize({ width: 390, height: 844 });
    const routeContracts = [
      ['/docs/getting-started', '#create-the-project', 1],
      ['/docs/widgets-layout', '#follow-the-layout-protocol', 1],
      ['/docs/state-lifecycle', '#let-one-state-own-the-field', 1],
      ['/docs/hooks', '#preserve-hook-order', 1],
      ['/docs/input-focus', '#use-local-pointer-coordinates', 1],
      ['/docs/testing', 'main table', 1],
      ['/docs/architecture-api', '.architecture-layers > li', 5],
      ['/docs/widget-catalog', 'main table', 5],
      ['/docs/platform-limitations', '.limitation-list > div', 6],
      ['/api', '.api-surface-status', 4],
    ];
    for (const [route, selector, count] of routeContracts) {
      await page.goto(`${baseUrl}${route}`, { waitUntil: 'networkidle' });
      assert.equal(
        await page.locator('main h1').count(),
        1,
        `${route} must have one document title`,
      );
      assert.equal(
        await page.locator(selector).count(),
        count,
        `${route} must expose its documented page structure`,
      );
      assert.equal(
        await page.evaluate(
          () =>
            document.documentElement.scrollWidth <=
            document.documentElement.clientWidth,
        ),
        true,
        `${route} must not overflow the mobile viewport`,
      );
      assert.equal(
        await page.locator('a[href="/examples"]').count(),
        0,
        `${route} must not link to the removed Examples route`,
      );
    }

    await page.goto(`${baseUrl}/docs/getting-started`, {
      waitUntil: 'networkidle',
    });
    await page.getByRole('button', { name: 'Menu' }).click();
    const mobileActiveRoute = page.locator(
      ".nextra-mobile-nav a[class~='x:bg-primary-100']",
    );
    assert.equal(
      await mobileActiveRoute.count(),
      1,
      'the mobile drawer must mark only the current route',
    );
    assert.equal(
      await page
        .locator('.nextra-mobile-nav')
        .getByRole('link', { name: 'Index', exact: true })
        .count(),
      0,
      'the routing-only documentation index must stay out of navigation',
    );
    assert.equal(
      await mobileActiveRoute.evaluate(
        (element) => getComputedStyle(element).backgroundColor,
      ),
      'rgba(0, 0, 0, 0)',
      'the mobile current route must use the quiet active treatment',
    );
    assert.equal(
      await mobileActiveRoute.evaluate(
        (element) => getComputedStyle(element).borderInlineStartWidth,
      ),
      '2px',
      'the mobile current route must retain the ink marker',
    );
    await page.getByRole('button', { name: 'Menu' }).click();

    await page.goto(`${baseUrl}/docs/widgets-layout`, {
      waitUntil: 'networkidle',
    });
    assert.equal(
      await page
        .locator('main pre')
        .filter({ hasText: 'minWidth: 18' })
        .count(),
      1,
      'the layout guide must size a titled border wide enough to paint the title',
    );

    await page.goto(`${baseUrl}/docs/hooks`, { waitUntil: 'networkidle' });
    assert.equal(
      await page
        .locator('main')
        .getByText('Timer.periodic', { exact: false })
        .count(),
      1,
      'the Hooks guide must show effect acquisition and cleanup together',
    );

    await page.goto(`${baseUrl}/docs/input-focus`, {
      waitUntil: 'networkidle',
    });
    assert.equal(
      await page
        .locator('main pre')
        .filter({ hasText: 'KeyEventResult.handled' })
        .count(),
      2,
      'the input guide must show both semantic and focused handlers consuming an event',
    );
    assert.equal(
      await page
        .locator('main pre')
        .filter({ hasText: 'event.localPosition' })
        .count(),
      1,
      'the input guide must show pointer-local coordinates in code',
    );
    assert.equal(
      await page
        .locator('main pre')
        .filter({ hasText: 'event.consume' })
        .count(),
      1,
      'the input guide must show TuiApp.onKey consuming with event.consume',
    );

    await page.goto(`${baseUrl}/docs/widget-catalog`, {
      waitUntil: 'networkidle',
    });
    assert.equal(
      await page.locator('main pre').filter({ hasText: 'height: 2' }).count(),
      1,
      'the catalog Select example must set visible height to the option count',
    );
    assert.equal(
      await page
        .locator('main')
        .getByText('option.value!', { exact: false })
        .count(),
      0,
      'the catalog must not force-unwrap a nullable SelectOption value',
    );

    await page.goto(`${baseUrl}/docs/testing`, { waitUntil: 'networkidle' });
    assert.equal(
      await page
        .locator('main')
        .getByText('does not export a public widget-test harness', {
          exact: false,
        })
        .count(),
      1,
      'the Testing guide must distinguish public application seams from repository-only helpers',
    );
    assert.equal(
      await page.locator('main pre').filter({ hasText: 'runTuiApp' }).count(),
      1,
      'the Testing guide must include a consumer-runnable lifecycle test',
    );
    assert.equal(
      await page
        .locator('main')
        .getByText('test/example/', { exact: false })
        .count(),
      0,
      'the consumer guide must not lead with Noir repository test paths',
    );
    assert.equal(
      await page.locator('main pre').filter({ hasText: 'dart test' }).count(),
      1,
      'the Testing guide must include the command that runs its test',
    );

    await page.goto(`${baseUrl}/docs/architecture-api`, {
      waitUntil: 'networkidle',
    });
    assert.equal(
      await page
        .getByRole('heading', { level: 1, name: 'Architecture' })
        .count(),
      1,
      'the architecture page must remain explanation rather than duplicate the API reference',
    );
    assert.equal(
      await page.locator('.api-surfaces-detailed').count(),
      0,
      'the architecture guide must not duplicate the top-level API chooser',
    );
    assert.equal(
      await page.locator('main table').count(),
      0,
      'the architecture guide must explain layers instead of recopying the API surface table',
    );

    await page.goto(`${baseUrl}/docs/platform-limitations`, {
      waitUntil: 'networkidle',
    });
    assert.equal(
      await page.locator('.limitation-list > div').count(),
      6,
      'known platform boundaries must be presented as scannable impact rows',
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
    const architectureLink = page
      .locator('.nextra-sidebar a')
      .filter({ hasText: /^Architecture$/ });
    assert.equal(
      await page
        .locator(".nextra-sidebar a[class~='x:bg-primary-100']")
        .count(),
      1,
      'the sidebar must mark only the current route',
    );
    assert.equal(
      await architectureLink.evaluate(
        (element) => getComputedStyle(element).backgroundColor,
      ),
      'rgba(0, 0, 0, 0)',
      'the active documentation route must use a quiet marker instead of a filled block',
    );
    assert.equal(
      await architectureLink.evaluate(
        (element) => getComputedStyle(element).borderInlineStartWidth,
      ),
      '2px',
      'the active documentation route must retain one precise ink marker',
    );

    assert.equal(
      await page
        .locator('.nextra-sidebar')
        .getByText('Start', { exact: true })
        .count(),
      1,
      'the documentation sidebar must identify the tutorial entry point',
    );
    assert.equal(
      await page
        .locator('.nextra-sidebar')
        .getByText('Build', { exact: true })
        .count(),
      1,
      'the documentation sidebar must identify task-oriented guides',
    );
    assert.equal(
      await page
        .locator('.nextra-sidebar')
        .getByText('Understand', { exact: true })
        .count(),
      1,
      'the documentation sidebar must identify explanatory content',
    );
    assert.equal(
      await page
        .locator('.nextra-sidebar')
        .getByText('Reference', { exact: true })
        .count(),
      1,
      'the documentation sidebar must identify reference content',
    );

    await context.grantPermissions(['clipboard-read', 'clipboard-write'], {
      origin: baseUrl,
    });
    await page.goto(baseUrl, { waitUntil: 'networkidle' });
    await page.getByRole('button', { name: 'Copy' }).click();
    await page.getByRole('button', { name: 'Copied' }).waitFor();
    assert.equal(
      await page.evaluate(() => navigator.clipboard.readText()),
      'dart pub add noir',
    );

    const examplesResponse = await page.goto(`${baseUrl}/examples`, {
      waitUntil: 'networkidle',
    });
    assert.equal(
      examplesResponse?.status(),
      404,
      'the removed Examples route must return 404',
    );
    await page
      .getByRole('heading', {
        name: 'That page isn’t in the Noir documentation.',
      })
      .waitFor();
    assert.equal(
      await page.locator('main#nextra-skip-nav[tabindex="-1"]').count(),
      1,
      'the custom not-found route must keep the Nextra skip-link target',
    );
    assert.equal(
      await page.getByRole('link', { name: 'Examples', exact: true }).count(),
      0,
      'the not-found page must not offer the removed destination',
    );
    assert.deepEqual(
      (await page.locator('.not-found-links a').allTextContents()).map((text) =>
        text.trim(),
      ),
      ['Getting started', 'Widgets and layout', 'API'],
      'the not-found page must recover into current documentation routes',
    );
    assert.deepEqual(
      browserErrors,
      [
        'Failed to load resource: the server responded with a status of 404 (Not Found)',
      ],
      'the removed route may report only its expected main-resource 404',
    );
    browserErrors.length = 0;

    await page.setViewportSize({ width: 320, height: 800 });
    assert.equal(
      await page.evaluate(
        () =>
          document.documentElement.scrollWidth <=
          document.documentElement.clientWidth,
      ),
      true,
      'the not-found page must reflow without horizontal scrolling at 320 CSS pixels',
    );

    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.goto(`${baseUrl}/docs/hooks`, { waitUntil: 'networkidle' });
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

    await search.fill('Examples');
    await page
      .locator('[role="option"]')
      .filter({ hasText: /^State and lifecycle/ })
      .first()
      .waitFor({ state: 'detached' });
    assert.equal(
      await page
        .locator('[role="option"]')
        .filter({ hasText: /^Examples$/ })
        .count(),
      0,
      'search must not offer the removed Examples page',
    );

    assert.deepEqual(browserErrors, [], 'browser console must stay error-free');
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
