import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { chromium, expect } from '@playwright/test';

import {
  normalizeBasePath,
  startStaticExport,
} from './serve-static-export.mjs';

const websiteRoot = process.cwd();
const repositoryRoot = join(websiteRoot, '..');

function readRepositoryFile(path) {
  return readFileSync(join(repositoryRoot, path), 'utf8');
}

const firstAppSource = readRepositoryFile(
  'packages/noir/example/tutorials/first_app/step_01.dart',
);
const firstAppStateSource = firstAppSource
  .slice(firstAppSource.indexOf('class _CounterAppState'))
  .trimEnd();
const capturedFrames = JSON.parse(
  readFileSync(join(websiteRoot, 'src/generated/terminal-frames.json'), 'utf8'),
).frames;

/** Rendered frame text, ignoring the styled blanks a row may end with. */
function screenText(text) {
  return text.replace(/[ \t]+$/gm, '').replace(/\s+$/, '');
}

function frameText(id) {
  return screenText(capturedFrames[id].lines.join('\n'));
}

const port = Number(process.env.NOIR_WEBSITE_PORT ?? 3018);
const suppliedUrl = process.env.NOIR_WEBSITE_URL;
const basePath = normalizeBasePath(process.env.NOIR_WEBSITE_BASE_PATH);
const baseUrl = (suppliedUrl ?? `http://localhost:${port}${basePath}`).replace(
  /\/$/,
  '',
);
const siteOrigin = new URL(baseUrl).origin;
const chromeOnMac =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

let server;

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
  throw new Error(`Timed out waiting for ${baseUrl}.`);
}

async function startServer() {
  if (suppliedUrl) return;

  server = await startStaticExport({ basePath, port });
  await waitForServer();
}

async function stopServer() {
  if (!server) return;
  await new Promise((resolveClose, rejectClose) => {
    server.close((error) => (error ? rejectClose(error) : resolveClose()));
  });
}

async function launchBrowser() {
  try {
    return await chromium.launch({ headless: true });
  } catch (error) {
    if (!existsSync(chromeOnMac)) throw error;
    return chromium.launch({ executablePath: chromeOnMac, headless: true });
  }
}

async function assertInternalLinksUseBasePath(page, pageName) {
  if (!basePath) return;
  const invalidLinks = await page
    .locator('a[href^="/"]')
    .evaluateAll(
      (links, expectedBasePath) =>
        links
          .map((link) => link.getAttribute('href'))
          .filter(
            (href) =>
              href !== expectedBasePath &&
              !href?.startsWith(`${expectedBasePath}/`),
          ),
      basePath,
    );
  assert.deepEqual(
    [...new Set(invalidLinks)],
    [],
    `${pageName} must keep internal links under the Pages base path`,
  );
}

/** Every captured frame on the page must equal its recorded capture. */
async function assertFramesMatchCaptures(page, route) {
  const frames = await page.locator('.terminal-frame pre').allInnerTexts();
  assert.ok(frames.length > 0, `${route} must show a captured frame`);
  const expected = Object.keys(capturedFrames).map((id) => frameText(id));
  for (const text of frames) {
    assert.ok(
      expected.includes(screenText(text)),
      `${route} shows a frame that no capture produced:\n${text}`,
    );
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
    // Mobile navigation and section links must remain usable without hover.
    for (const width of [320, 390, 767]) {
      await page.setViewportSize({ width, height: 844 });
      await page.goto(`${baseUrl}/docs/getting-started`, {
        waitUntil: 'networkidle',
      });
      const permalink = page
        .getByRole('link', {
          name: 'Permalink for this section',
        })
        .first();
      const target = await permalink.boundingBox();
      assert.ok(
        target.width >= 44 && target.height >= 44,
        `section permalinks need a 44px target at ${width}px`,
      );
      assert.equal(
        await permalink.evaluate((el) => getComputedStyle(el).opacity),
        '1',
        'mobile permalinks must be discoverable without hover',
      );
      await permalink.click();
      assert.ok(
        new URL(page.url()).hash,
        'a permalink must navigate to its section',
      );
      await page.getByRole('button', { name: 'Menu', exact: true }).click();
      const rows = page.locator(
        '.nextra-mobile-nav li > a, .nextra-mobile-nav li > button',
      );
      for (const row of await rows.all()) {
        if (!(await row.isVisible())) continue;
        assert.ok(
          (await row.boundingBox()).height >= 44,
          `mobile row "${await row.innerText()}" needs a 44px target at ${width}px`,
        );
      }
      const destination = page.locator('.nextra-mobile-nav').getByRole('link', {
        name: 'Platform support',
        exact: true,
      });
      await destination.click();
      await page
        .getByRole('heading', { level: 1, name: 'Platform support' })
        .waitFor();
      assert.ok(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth,
        ),
        `mobile navigation must not overflow at ${width}px`,
      );
    }

    // Sidebar destinations use the same readable palette in both themes.
    for (const colorScheme of ['dark', 'light']) {
      await page.emulateMedia({ colorScheme });
      await page.setViewportSize({ width: 1440, height: 1000 });
      await page.goto(`${baseUrl}/docs/getting-started`, {
        waitUntil: 'networkidle',
      });
      const ink = await page
        .locator('body')
        .evaluate((el) => getComputedStyle(el).color);
      await expect(
        page.locator('.nextra-sidebar').getByRole('link', {
          name: 'Handle input and focus',
          exact: true,
        }),
      ).toHaveCSS('color', ink);
      await page.setViewportSize({ width: 390, height: 844 });
      await page.getByRole('button', { name: 'Menu', exact: true }).click();
      await expect(
        page.locator('.nextra-mobile-nav').getByRole('link', {
          name: 'Handle input and focus',
          exact: true,
        }),
      ).toHaveCSS('color', ink);
      await page.getByRole('button', { name: 'Menu', exact: true }).click();
    }

    // ---- Homepage: one promise, one action, one exact code/output pair ----
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.goto(baseUrl, { waitUntil: 'networkidle' });
    await page
      .getByRole('heading', { name: 'Build terminal apps in Dart.' })
      .waitFor();
    await assertInternalLinksUseBasePath(page, 'the homepage');

    const primaryAction = page.locator('.home-primary-action');
    assert.equal(
      await primaryAction.getAttribute('href'),
      `${basePath}/docs/getting-started/`,
      'the homepage must lead with the first-app action',
    );
    assert.ok(
      (await primaryAction.boundingBox()).y < 1000,
      'the first-app action must be visible without scrolling at 1440x1000',
    );
    assert.ok(
      (await page.locator('.home-proof .terminal-frame').boundingBox()).y <
        1000,
      'the code and output proof must be visible on the first desktop screen',
    );

    assert.equal(
      await page.locator('.home-proof figure.highlighted-code').count(),
      1,
      'homepage source must be one captioned figure',
    );
    assert.equal(
      await page.locator('.home-proof .highlighted-code pre[tabindex]').count(),
      0,
      'highlighted source must not insert a dead tab stop',
    );
    for (const variable of ['--shiki-light', '--shiki-dark']) {
      assert.ok(
        (await page
          .locator(`.home-proof .highlighted-code [style*="${variable}"]`)
          .count()) > 0,
        `homepage highlighting must emit ${variable} token variables`,
      );
    }
    assert.equal(
      (
        await page
          .locator('.home-proof .highlighted-code .shiki .line')
          .allTextContents()
      )
        .join('\n')
        .replace(/\n+$/, ''),
      firstAppStateSource,
      'homepage source must equal the runnable first-app checkpoint excerpt',
    );
    assert.equal(
      screenText(
        await page.locator('.home-proof .terminal-frame pre').innerText(),
      ),
      frameText('first-app-count'),
      'the homepage output must be the captured frame of that same file',
    );
    assert.equal(
      await page
        .locator('.home-proof .terminal-frame pre span', {
          hasText: '+ Add one',
        })
        .last()
        .evaluate((element) => getComputedStyle(element).backgroundColor),
      'rgb(102, 217, 255)',
      'the frame must keep the focused button colors the app painted',
    );
    assert.ok(
      await page
        .locator('.home-proof .highlighted-code pre')
        .evaluate((element) => element.scrollWidth <= element.clientWidth),
      'the homepage source must fit its column without scrolling at 1440px',
    );
    assert.equal(
      await page
        .locator('.terminal-frame')
        .getByText('NoirDriver (NOIR_DRIVE=1)', { exact: false })
        .count(),
      1,
      'a captured frame must state how it was produced',
    );
    assert.equal(
      await page.locator('.home-proof .terminal-recording').count(),
      0,
      'the homepage proof must show the tutorial file, not another recording',
    );
    assert.equal(
      await page.locator('.availability strong').textContent(),
      `Published version · ${JSON.parse(readRepositoryFile('publication.json')).noir}`,
      'the homepage must carry one generated availability label',
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

    // ---- Global navigation ----
    assert.equal(
      await page
        .locator('.nextra-navbar')
        .getByRole('link', { name: 'Home', exact: true })
        .count(),
      0,
      'the wordmark already returns home; a Home item is redundant',
    );
    for (const name of ['Docs', 'Examples', 'API']) {
      assert.equal(
        await page
          .locator('.nextra-navbar')
          .getByRole('link', { name, exact: true })
          .count(),
        1,
        `the top navigation must offer ${name}`,
      );
    }

    // ---- Keyboard entry ----
    await page.goto(baseUrl, { waitUntil: 'networkidle' });
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
    await page.waitForURL('**/*#nextra-skip-nav');
    assert.equal(
      await page.evaluate(() => document.activeElement?.id),
      'nextra-skip-nav',
      'the homepage skip link must move focus to the main content',
    );

    // ---- Typography: sans-serif root, serif display only ----
    const rootFont = await page.evaluate(
      () => getComputedStyle(document.body).fontFamily,
    );
    assert.ok(
      /sans-serif/.test(rootFont) && !/Georgia/.test(rootFont),
      `the application root must default to sans-serif, not ${rootFont}`,
    );

    // ---- Sidebar hierarchy ----
    // A lesson index is both the open folder and its first page.
    await page.goto(`${baseUrl}/docs/signals-task-list`, {
      waitUntil: 'networkidle',
    });
    const sidebar = page.locator('.nextra-sidebar');
    assert.equal(
      await sidebar.getByRole('button', { name: 'Docs', exact: true }).count(),
      0,
      'the sidebar must open on its groups, not one Docs folder around them',
    );
    assert.deepEqual(
      (
        await sidebar.locator("li[class~='x:font-semibold']").allTextContents()
      ).map((text) => text.trim()),
      ['Start here', 'Guides', 'Concepts', 'noir_signals', 'Reference'],
      'the sidebar must group pages by reader intent, core before companion',
    );
    const activeRoute = sidebar.locator("a[class~='x:bg-primary-100']");
    const activeSection = sidebar.locator("button[class~='x:bg-primary-100']");
    assert.equal(
      await activeRoute.count(),
      1,
      'the sidebar must mark the current page once',
    );
    assert.equal(
      await activeSection.count(),
      1,
      'the sidebar must mark the section that contains the current page',
    );
    for (const active of [activeRoute, activeSection]) {
      assert.equal(
        await active.evaluate(
          (element) => getComputedStyle(element).backgroundColor,
        ),
        'rgba(0, 0, 0, 0)',
        'an active sidebar row must use the quiet marker, not a filled block',
      );
      assert.equal(
        await active.evaluate(
          (element) => getComputedStyle(element).borderInlineStartWidth,
        ),
        '2px',
        'an active sidebar row must retain the ink marker',
      );
    }
    assert.equal(
      await activeSection.evaluate(
        (element) => getComputedStyle(element).fontSize,
      ),
      await activeRoute.evaluate(
        (element) => getComputedStyle(element).fontSize,
      ),
      'a sidebar folder must use the same type size as its pages',
    );

    // ---- Documentation router ----
    await page.goto(`${baseUrl}/docs`, { waitUntil: 'networkidle' });
    assert.equal(
      new URL(page.url()).pathname.replace(/\/$/, ''),
      `${basePath}/docs`,
      'the documentation root must stay a compact router',
    );
    assert.deepEqual(
      await page.locator('main h2').allTextContents(),
      [
        'Start here',
        'Finish a task',
        'Understand the model',
        'Add hooks and Signals with noir_signals',
        'Look something up',
        'Contribute',
      ],
      'the overview must route by reader intent',
    );
    assert.equal(
      await page.locator('main .install-command').count(),
      0,
      'the overview must not repeat the installation instructions',
    );

    // ---- Your first app ----
    await page.goto(`${baseUrl}/docs/getting-started`, {
      waitUntil: 'networkidle',
    });
    assert.deepEqual(
      await page.locator('main h2').allTextContents(),
      [
        '1. Create the project',
        '2. Add Noir',
        '3. Write the screen',
        '4. Run it and press the button',
        '5. Change the running app',
        'What you built',
        'Where to go next',
      ],
      'the first tutorial must be a numbered, action-led sequence',
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
        .locator('main pre')
        .filter({ hasText: 'dart run noir:run bin/noir_demo.dart' })
        .count(),
      1,
      'the tutorial must show the runner command once, as a command',
    );
    assert.equal(
      (
        await page
          .locator('main pre')
          .filter({ hasText: "import 'package:noir/noir.dart';" })
          .first()
          .innerText()
      )
        .replace(/^[ \t]+$/gm, '')
        .trim(),
      firstAppSource.trim(),
      'the tutorial file must equal the runnable first-app checkpoint',
    );
    assert.equal(
      await page.locator('main .terminal-frame').count(),
      2,
      'the tutorial must show the frame before and after its edit',
    );
    await assertFramesMatchCaptures(page, '/docs/getting-started');
    assert.equal(
      await page.locator('main .terminal-recording').count(),
      0,
      'the tutorial must not show a recording of a different program',
    );
    assert.equal(
      await page
        .locator('main h2')
        .first()
        .evaluate((element) => getComputedStyle(element).borderBottomWidth),
      '0px',
      'article headings must rely on whitespace instead of a rule',
    );

    // ---- Installation owns every dependency instruction ----
    await page.goto(`${baseUrl}/docs/installation`, {
      waitUntil: 'networkidle',
    });
    assert.equal(
      await page.locator('main .install-command code').innerText(),
      'dart pub add noir',
      'the installation page must render the generated install command',
    );
    assert.equal(
      await page
        .locator('main pre')
        .filter({ hasText: 'dependency_overrides' })
        .count(),
      1,
      'the installation page must own the companion checkout setup',
    );
    assert.equal(
      await page.locator('main .availability').count(),
      2,
      'each package must carry its own availability label here',
    );

    // ---- Examples reach runnable source ----
    await page.goto(`${baseUrl}/examples`, { waitUntil: 'networkidle' });
    const exampleRecording = page.locator('main .terminal-recording');
    await exampleRecording.locator('.ap-wrapper').waitFor();
    const terminalText = exampleRecording.locator('.ap-term-text');
    await terminalText.waitFor();
    await page.waitForFunction(
      () =>
        document
          .querySelector('main .terminal-recording .ap-term-text')
          ?.textContent?.includes('Noir Counter') ?? false,
    );
    assert.match(
      (await terminalText.textContent()) ?? '',
      /Noir Counter[\s\S]*this many times:[\s\S]*0/,
      'the examples poster must show the real initial counter frame',
    );
    await page.waitForTimeout(900);
    assert.match(
      (await terminalText.textContent()) ?? '',
      /this many times:[\s\S]*0/,
      'the recording must not autoplay',
    );
    await exampleRecording.locator('.ap-play-button').click();
    await page.waitForFunction(
      () =>
        /this many times:[\s\S]*3/.test(
          document.querySelector('main .terminal-recording .ap-term-text')
            ?.textContent ?? '',
        ),
      undefined,
      { timeout: 6000 },
    );
    await page.waitForTimeout(250);
    assert.match(
      (await terminalText.textContent()) ?? '',
      /this many times:[\s\S]*3/,
      'the final pointer interaction must remain visible before the loop',
    );
    const sourceLinks = await page
      .locator('main table a[href^="https://github.com/"]')
      .evaluateAll((links) => links.map((link) => link.getAttribute('href')));
    assert.ok(
      sourceLinks.length >= 7,
      'the examples index must link every listed source file',
    );
    for (const href of sourceLinks) {
      assert.ok(
        href.endsWith('.dart'),
        `an example entry must point at a file, not a page: ${href}`,
      );
      const path = href.replace(
        'https://github.com/btwld/noir/blob/main/',
        '',
      );
      assert.ok(
        existsSync(join(repositoryRoot, path)),
        `the examples index links a missing file: ${path}`,
      );
    }

    // ---- The task list is five lessons with local navigation ----
    const lessonRoutes = [
      '/docs/signals-task-list',
      '/docs/signals-task-list/store-tasks',
      '/docs/signals-task-list/complete-a-task',
      '/docs/signals-task-list/add-a-task',
      '/docs/signals-task-list/filter-and-clear',
    ];
    for (const route of lessonRoutes) {
      await page.goto(`${baseUrl}${route}`, { waitUntil: 'networkidle' });
      assert.equal(
        await page.locator('main h1').count(),
        1,
        `${route} must have one document title`,
      );
      const images = page.locator('main img');
      assert.ok(
        (await images.count()) >= 1,
        `${route} must show the result of its own step`,
      );
      assert.equal(
        await page.locator('main figure:has(img) figcaption').count(),
        await images.count(),
        `${route} must caption every screenshot`,
      );
      for (const picture of await images.all()) {
        await picture.scrollIntoViewIfNeeded();
        await picture.evaluate((image) => image.decode());
        assert.ok(
          await picture.evaluate((image) => image.naturalWidth > 0),
          `${route} has a screenshot that does not load`,
        );
      }
    }

    await page.goto(`${baseUrl}/docs/signals-task-list`, {
      waitUntil: 'networkidle',
    });
    for (const legacyAnchor of [
      'step-1-create-the-screen',
      'step-2-own-the-task-signal-and-derive-the-count',
      'step-3-complete-tasks-by-replacing-the-list',
      'step-4-retain-a-draft-and-add-tasks',
      'step-5-filter-the-view-and-remove-completed-tasks',
      'run-the-examples',
      'continue-with-your-app',
    ]) {
      assert.equal(
        await page.locator(`#${legacyAnchor}`).count(),
        1,
        `the tutorial entry must keep the ${legacyAnchor} destination`,
      );
    }
    assert.equal(
      await page
        .getByRole('link', {
          name: 'View source on GitHub',
          includeHidden: true,
        })
        .getAttribute('href'),
      'https://github.com/btwld/noir/blob/main/packages/noir_signals/doc/getting-started.md',
      'the source link must open the canonical guide, not the generated page',
    );

    await page.goto(`${baseUrl}/docs/signals-task-list/filter-and-clear`, {
      waitUntil: 'networkidle',
    });
    const finalCheckpoint = page.locator('details').filter({
      has: page.getByText('Complete code after lesson 5', { exact: true }),
    });
    const checkpointControl = finalCheckpoint.locator('summary');
    await checkpointControl.focus();
    await checkpointControl.press('Enter');
    assert.equal(
      await finalCheckpoint.evaluate((element) => element.hasAttribute('open')),
      true,
      'complete code must open with the keyboard',
    );
    assert.equal(
      // Shiki renders otherwise empty lines with a space to preserve height.
      (await finalCheckpoint.locator('pre').innerText())
        .replace(/^[ \t]+$/gm, '')
        .trim(),
      readRepositoryFile('packages/noir_signals/example/task_list.dart').trim(),
      'the copyable final checkpoint must match the runnable example',
    );
    const controlHeight = await checkpointControl.evaluate(
      (element) => element.getBoundingClientRect().height,
    );
    assert.ok(
      controlHeight >= 44 && controlHeight < 80,
      'code controls must have a usable target without heading margins',
    );

    // ---- The document order never becomes tutorial navigation ----
    assert.equal(
      await page
        .locator('.nextra-content nav[aria-label="Pagination"]')
        .count(),
      0,
      'global pagination must not follow a lesson into an unrelated guide',
    );

    // ---- Route contracts at phone width ----
    await page.setViewportSize({ width: 390, height: 844 });
    const expectedLimitationRows = 9;
    const routeContracts = [
      ['/docs', 'main h2', 6],
      ['/docs/getting-started', '[id="3-write-the-screen"]', 1],
      ['/docs/installation', 'main table', 1],
      ['/docs/command-line-arguments', '#parse-flags-for-one-application', 1],
      ['/docs/widgets-layout', '#constraints-go-down-sizes-come-up', 1],
      ['/docs/state-lifecycle', '#let-one-state-own-the-resource', 1],
      ['/docs/noir-signals', '#choose-a-guide', 1],
      ['/docs/hooks', '#own-a-resource-and-its-cleanup-together', 1],
      ['/docs/signals', '#observation-is-explicit', 1],
      ['/docs/signals-task-list', 'main img', 2],
      ['/docs/input-focus', '#use-local-pointer-coordinates', 1],
      ['/docs/testing', 'main table', 1],
      ['/docs/architecture-api', '.architecture-layers > li', 5],
      ['/docs/widget-catalog', 'main table', 6],
      ['/docs/widgets/text-input', 'main table', 1],
      [
        '/docs/platform-limitations',
        '.limitation-list > div',
        expectedLimitationRows,
      ],
      ['/api', '.api-surface-status', 4],
      ['/examples', 'main table', 2],
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
      await assertInternalLinksUseBasePath(page, route);
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

    // ---- Guides keep the examples their readers need ----
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.goto(`${baseUrl}/docs/widgets-layout`, {
      waitUntil: 'networkidle',
    });
    assert.equal(
      await page
        .locator('main pre')
        .filter({ hasText: "title: 'Build log'" })
        .filter({ hasText: 'width: 24' })
        .count(),
      1,
      'the layout guide must size a titled panel wide enough to paint the title',
    );

    await page.goto(`${baseUrl}/docs/hooks`, { waitUntil: 'networkidle' });
    assert.equal(
      await page
        .locator('main')
        .getByText('Timer.periodic', { exact: false })
        .count(),
      1,
      'the resource guide must show acquisition and cleanup together',
    );
    assert.equal(
      await page.locator('main pre').filter({ hasText: 'alpha.0' }).count(),
      0,
      'an ordinary guide must not repeat a dependency block that cannot resolve',
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

    await page.goto(`${baseUrl}/docs/command-line-arguments`, {
      waitUntil: 'networkidle',
    });
    assert.equal(
      await page.locator('main pre').filter({ hasText: 'ArgParser()' }).count(),
      1,
      'the CLI guide must start from a complete ArgParser recipe',
    );

    await page.goto(`${baseUrl}/docs/testing`, { waitUntil: 'networkidle' });
    assert.equal(
      await page
        .locator('main')
        .getByText('does not export a widget-test harness', { exact: false })
        .count(),
      1,
      'the testing guide must distinguish public seams from repository helpers',
    );
    assert.equal(
      await page
        .locator('main pre')
        .filter({ hasText: 'headless: true' })
        .count(),
      1,
      'the testing guide must include a consumer-runnable lifecycle test',
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
      'the testing guide must include the command that runs its test',
    );

    await page.setViewportSize({ width: 768, height: 900 });
    await page.goto(`${baseUrl}/api`, { waitUntil: 'networkidle' });
    assert.equal(
      await page
        .locator('.api-surfaces > div')
        .first()
        .evaluate((element) => getComputedStyle(element).display),
      'block',
      'the API chooser must stack when the sidebar narrows its article',
    );
    await page.setViewportSize({ width: 1440, height: 1000 });

    await page.goto(`${baseUrl}/docs/architecture-api`, {
      waitUntil: 'networkidle',
    });
    assert.equal(
      await page.locator('.api-surfaces').count(),
      0,
      'the architecture guide must not duplicate the API chooser',
    );
    assert.equal(
      await page
        .locator('main')
        .getByText('lays out the changed subtree', { exact: false })
        .count(),
      0,
      'the architecture guide must not promise subtree-only layout',
    );

    // ---- Lookup: catalog to a usable reference in two actions ----
    await page.goto(`${baseUrl}/docs/widget-catalog`, {
      waitUntil: 'networkidle',
    });
    await page
      .locator('main')
      .getByRole('link', { name: 'TextInput', exact: true })
      .first()
      .click();
    await page.waitForURL('**/docs/widgets/text-input/');
    assert.equal(
      await page
        .locator('main pre')
        .filter({ hasText: 'TextEditingController' })
        .count(),
      1,
      'the widget reference must show one complete working usage',
    );
    assert.equal(
      await page
        .locator('main')
        .getByRole('link', { name: 'Generated signature', exact: true })
        .count(),
      1,
      'the widget reference must link its generated signature',
    );

    // ---- Copying the install command ----
    await context.grantPermissions(['clipboard-read', 'clipboard-write'], {
      origin: siteOrigin,
    });
    await page.goto(baseUrl, { waitUntil: 'networkidle' });
    await page.getByRole('button', { name: 'Copy' }).click();
    await page.getByRole('button', { name: 'Copied' }).waitFor();
    assert.equal(
      await page.evaluate(() => navigator.clipboard.readText()),
      'dart pub add noir',
    );

    // ---- Recovery from a missing page ----
    const removedResponse = await page.goto(`${baseUrl}/docs/signals-guide`, {
      waitUntil: 'networkidle',
    });
    assert.equal(
      removedResponse?.status(),
      404,
      'an unknown documentation route must return 404',
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
    assert.deepEqual(
      (await page.locator('.not-found-links a').allTextContents()).map((text) =>
        text.trim(),
      ),
      ['Your first app', 'Documentation', 'Examples', 'API'],
      'the not-found page must recover into current documentation routes',
    );
    assert.deepEqual(
      browserErrors,
      [
        'Failed to load resource: the server responded with a status of 404 (Not Found)',
      ],
      'the missing route may report only its expected main-resource 404',
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
      'the not-found page must reflow without horizontal scrolling at 320px',
    );

    // ---- Search reaches the reference, in the article typeface ----
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.goto(`${baseUrl}/docs/hooks`, { waitUntil: 'networkidle' });
    const search = page.getByRole('combobox', {
      name: 'Search documentation…',
    });
    await search.click();
    await search.fill('TextInput');
    const textInputResult = page
      .locator('[role="option"]')
      .filter({ hasText: /TextInput/ })
      .first();
    await textInputResult.waitFor();
    const resultFont = await textInputResult.evaluate(
      (element) => getComputedStyle(element).fontFamily,
    );
    assert.ok(
      /sans-serif/.test(resultFont) && !/Georgia/.test(resultFont),
      `search results must use the interface typeface, not ${resultFont}`,
    );
    await search.fill('SignalWidget');
    await page
      .locator('[role="option"]')
      .filter({ hasText: /Show shared state|Build a task list/ })
      .first()
      .waitFor();

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
  throw error;
} finally {
  await stopServer();
}
