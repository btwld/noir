// Generates every documentation fact that must not be maintained twice.
//
// The script owns four derivations and nothing else:
//
//   1. Package availability, from `TODO.md` and the two `pubspec.yaml` files.
//   2. Tutorial code, from the canonical runnable checkpoints in `example/`.
//   3. Captured terminal frames, from `scripts/capture_doc_frames.dart`.
//   4. The task-list lesson pages, from the Markdown that ships with the
//      companion package.
//
// Prose stays human-authored. Stale or ambiguous input fails the build instead
// of silently publishing a wrong version, an unrunnable snippet, or a frame
// that no longer matches its source.

import { createHash } from 'node:crypto';
import {
  mkdir,
  readFile,
  readdir,
  rm,
  stat,
  writeFile,
} from 'node:fs/promises';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { format, resolveConfig } from 'prettier';
import { codeToHtml } from 'shiki';

const websiteRoot = fileURLToPath(new URL('../', import.meta.url));
const prettierConfig = await resolveConfig(
  join(websiteRoot, '.prettierrc.json'),
);
const repositoryRoot = resolve(websiteRoot, '..');
const generatedRoot = join(websiteRoot, 'src/generated');
const blobBase = 'https://github.com/conceptadev/noir/blob/main';
const treeBase = 'https://github.com/conceptadev/noir/tree/main';

const companionRoot = 'packages/noir_signals';
const taskListRoute = '/docs/signals-task-list';

/** The ordered task-list lessons, their sources, and their checkpoints. */
const taskListLessons = [
  {
    slug: '',
    navTitle: 'Create the screen',
    source: `${companionRoot}/doc/getting-started.md`,
    checkpoint: `${companionRoot}/example/tutorials/task_list/step_01.dart`,
  },
  {
    slug: 'store-tasks',
    navTitle: 'Store tasks and derive the count',
    source: `${companionRoot}/doc/tutorials/task-list/store-tasks.md`,
    checkpoint: `${companionRoot}/example/tutorials/task_list/step_02.dart`,
  },
  {
    slug: 'complete-a-task',
    navTitle: 'Complete a task',
    source: `${companionRoot}/doc/tutorials/task-list/complete-a-task.md`,
    checkpoint: `${companionRoot}/example/tutorials/task_list/step_03.dart`,
  },
  {
    slug: 'add-a-task',
    navTitle: 'Add a task',
    source: `${companionRoot}/doc/tutorials/task-list/add-a-task.md`,
    checkpoint: `${companionRoot}/example/tutorials/task_list/step_04.dart`,
  },
  {
    slug: 'filter-and-clear',
    navTitle: 'Filter and clear completed tasks',
    source: `${companionRoot}/doc/tutorials/task-list/filter-and-clear.md`,
    // The final lesson has no separate body: it is the shipped example.
    checkpoint: `${companionRoot}/example/task_list.dart`,
  },
];

/** Checkpoints the first-app tutorial and the homepage render. */
const firstAppCheckpoints = {
  step01: 'example/tutorials/first_app/step_01.dart',
  step02: 'example/tutorials/first_app/step_02.dart',
};

function fail(message) {
  throw new Error(message);
}

async function writeGenerated(name, source) {
  const target = join(generatedRoot, name);
  await writeFile(
    target,
    await format(source, {
      ...prettierConfig,
      filepath: target,
    }),
  );
}

async function readRepositoryFile(path) {
  try {
    return await readFile(join(repositoryRoot, path), 'utf8');
  } catch {
    return fail(`Missing required source file: ${path}`);
  }
}

/* ------------------------------------------------------------------ *
 * 1. Availability
 * ------------------------------------------------------------------ */

const semanticVersion = /^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)*$/;

function parseManifestVersion(pubspec, path) {
  const match = pubspec.match(/^version: (.+)$/m);
  if (!match) fail(`${path} has no version.`);
  return match[1].trim();
}

async function readAvailability() {
  const todo = await readRepositoryFile('TODO.md');
  const block = todo.match(/```noir-availability\n([\s\S]*?)```/);
  if (!block) {
    fail(
      'TODO.md must carry exactly one ```noir-availability block. It is the ' +
        'single source of publication state.',
    );
  }
  if (todo.match(/```noir-availability/g).length !== 1) {
    fail('TODO.md must carry exactly one ```noir-availability block.');
  }

  const packages = {};
  for (const line of block[1].split('\n')) {
    const text = line.trim();
    if (!text || text.startsWith('#')) continue;
    const entry = text.match(/^([a-z_]+): manifest=(\S+) published=(\S+)$/);
    if (!entry) {
      fail(
        `Unreadable availability line in TODO.md: "${text}". Use ` +
          '"<package>: manifest=<version> published=<version|none>".',
      );
    }
    const [, name, manifest, published] = entry;
    if (!semanticVersion.test(manifest)) {
      fail(`TODO.md declares an unusable ${name} manifest version.`);
    }
    if (published !== 'none' && !semanticVersion.test(published)) {
      fail(`TODO.md declares an unusable ${name} published version.`);
    }
    packages[name] = { name, manifest, published };
  }

  const manifests = {
    noir: parseManifestVersion(
      await readRepositoryFile('pubspec.yaml'),
      'pubspec.yaml',
    ),
    noir_signals: parseManifestVersion(
      await readRepositoryFile(`${companionRoot}/pubspec.yaml`),
      `${companionRoot}/pubspec.yaml`,
    ),
  };

  for (const [name, version] of Object.entries(manifests)) {
    const declared = packages[name];
    if (!declared) fail(`TODO.md does not record availability for ${name}.`);
    if (declared.manifest !== version) {
      fail(
        `TODO.md records ${name} manifest ${declared.manifest}, but ` +
          `its pubspec.yaml declares ${version}. Update TODO.md.`,
      );
    }
  }

  const noir = packages.noir;
  const companion = packages.noir_signals;
  return {
    noir: {
      ...noir,
      isPublished: noir.published !== 'none',
      installCommand: 'dart pub add noir',
      label:
        noir.published === 'none'
          ? 'Not published yet · repository checkout only'
          : `Published prerelease · ${noir.published}`,
    },
    companion: {
      ...companion,
      isPublished: companion.published !== 'none',
      installCommand: 'dart pub add noir_signals',
      label:
        companion.published === 'none'
          ? 'Not published yet · repository checkout only'
          : `Published prerelease · ${companion.published}`,
    },
  };
}

async function writeAvailability(availability) {
  const source = `// Generated by scripts/sync-docs.mjs from TODO.md and the package manifests.
// Do not edit by hand.

export interface PackageAvailability {
  readonly name: string;
  /** The version in this repository's manifest. */
  readonly manifest: string;
  /** The latest version on pub.dev, or 'none'. */
  readonly published: string;
  readonly isPublished: boolean;
  readonly installCommand: string;
  readonly label: string;
}

export const availability: {
  readonly noir: PackageAvailability;
  readonly companion: PackageAvailability;
} = ${JSON.stringify(availability, null, 2)} as const;
`;
  await writeGenerated('availability.ts', source);
  return availability;
}

/* ------------------------------------------------------------------ *
 * 2. Canonical code and 3. captured frames
 * ------------------------------------------------------------------ */

function sha256(text) {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

async function readFrames() {
  const raw = await readFile(
    join(generatedRoot, 'terminal-frames.json'),
    'utf8',
  );
  const document = JSON.parse(raw);
  for (const [id, frame] of Object.entries(document.frames)) {
    const source = await readRepositoryFile(frame.entrypoint);
    if (sha256(source) !== frame.sourceSha256) {
      fail(
        `Captured frame "${id}" no longer matches ${frame.entrypoint}. Run ` +
          '`dart run scripts/capture_doc_frames.dart` and commit the result.',
      );
    }
  }
  return document;
}

/** Extracts the retained `State` class from the first-app checkpoint. */
function stateExcerpt(source, path) {
  const start = source.indexOf('class _CounterAppState');
  if (start < 0) fail(`${path} must declare _CounterAppState.`);
  return source.slice(start).trimEnd();
}

async function writeFrames(document) {
  const source = `// Generated by scripts/sync-docs.mjs from
// scripts/capture_doc_frames.dart output. Do not edit by hand.

export interface TerminalFrameData {
  readonly title: string;
  readonly command: string;
  readonly entrypoint: string;
  readonly width: number;
  readonly height: number;
  readonly interaction: string;
  readonly sourceSha256: string;
  readonly lines: readonly string[];
}

/** How every frame below was produced. */
export const capturedWith = ${JSON.stringify(document.capturedWith)};

export const terminalFrames: Record<string, TerminalFrameData> =
  ${JSON.stringify(document.frames, null, 2)};
`;
  await writeGenerated('frames.ts', source);
}

async function writeCheckpoints(frames) {
  const step01 = await readRepositoryFile(firstAppCheckpoints.step01);
  const step02 = await readRepositoryFile(firstAppCheckpoints.step02);
  const excerpt = stateExcerpt(step01, firstAppCheckpoints.step01);
  // The homepage promises that one callback changes retained state. The
  // excerpt has to contain both halves of that claim.
  for (const required of ['_count', 'setState(']) {
    if (!excerpt.includes(required)) {
      fail(
        `The homepage excerpt must show ${required}. It comes from ` +
          `${firstAppCheckpoints.step01}, which no longer contains it.`,
      );
    }
  }
  const proofFrame = frames.frames['first-app-count'];
  if (!proofFrame || proofFrame.entrypoint !== firstAppCheckpoints.step01) {
    fail(
      'The homepage proof frame must be captured from ' +
        `${firstAppCheckpoints.step01}.`,
    );
  }

  const html = await codeToHtml(excerpt, {
    defaultColor: false,
    lang: 'dart',
    tabindex: false,
    themes: { dark: 'github-dark', light: 'github-light' },
  });

  const tutorial = await readRepositoryFile(
    'website/src/content/docs/getting-started.mdx',
  );
  if (!tutorial.includes(`\n${step01.trimEnd()}\n\`\`\``)) {
    fail(
      'website/src/content/docs/getting-started.mdx must show ' +
        `${firstAppCheckpoints.step01} verbatim in one Dart fence.`,
    );
  }
  const edited = step02.split('\n').find((line) => line.includes('Total: '));
  const original = step01.split('\n').find((line) => line.includes('Count: '));
  if (!edited || !original)
    fail('The first-app checkpoints must differ by one label.');
  if (!tutorial.includes(`-${original}`) || !tutorial.includes(`+${edited}`)) {
    fail(
      'The first-app tutorial must show the exact label edit between ' +
        'the two checkpoints as a diff.',
    );
  }

  const source = `// Generated by scripts/sync-docs.mjs from the runnable first-app checkpoints.
// Do not edit by hand.

/** ${firstAppCheckpoints.step01} — the complete tutorial app. */
export const firstAppSource = ${JSON.stringify(step01.trimEnd())};

/** ${firstAppCheckpoints.step02} — the same app after the label edit. */
export const firstAppEditedSource = ${JSON.stringify(step02.trimEnd())};

/** The retained State the homepage shows beside its captured frame. */
export const firstAppStateSource = ${JSON.stringify(excerpt)};

/** Shiki markup for {@link firstAppStateSource}. */
export const firstAppStateHtml = ${JSON.stringify(html)};

/** Where the checkpoints live, for "view source" links. */
export const firstAppSourcePaths = ${JSON.stringify(firstAppCheckpoints, null, 2)} as const;
`;
  await writeGenerated('checkpoints.ts', source);
}

/* ------------------------------------------------------------------ *
 * 4. Task-list lessons
 * ------------------------------------------------------------------ */

/** Shortest-edit unified diff with three lines of context. */
function unifiedDiff(before, after, fromLabel, toLabel) {
  const a = before.replace(/\n+$/, '').split('\n');
  const b = after.replace(/\n+$/, '').split('\n');
  const lengths = Array.from(
    { length: a.length + 1 },
    () => new Uint32Array(b.length + 1),
  );
  for (let i = a.length - 1; i >= 0; i--) {
    for (let j = b.length - 1; j >= 0; j--) {
      lengths[i][j] =
        a[i] === b[j]
          ? lengths[i + 1][j + 1] + 1
          : Math.max(lengths[i + 1][j], lengths[i][j + 1]);
    }
  }

  const script = [];
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) {
      script.push({ kind: ' ', text: a[i] });
      i++;
      j++;
    } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
      script.push({ kind: '-', text: a[i] });
      i++;
    } else {
      script.push({ kind: '+', text: b[j] });
      j++;
    }
  }
  for (; i < a.length; i++) script.push({ kind: '-', text: a[i] });
  for (; j < b.length; j++) script.push({ kind: '+', text: b[j] });

  const context = 3;
  const keep = new Array(script.length).fill(false);
  script.forEach((entry, index) => {
    if (entry.kind === ' ') return;
    for (
      let near = Math.max(0, index - context);
      near <= Math.min(script.length - 1, index + context);
      near++
    ) {
      keep[near] = true;
    }
  });

  const lines = [`--- ${fromLabel}`, `+++ ${toLabel}`];
  let index = 0;
  let oldLine = 1;
  let newLine = 1;
  while (index < script.length) {
    if (!keep[index]) {
      if (script[index].kind !== '+') oldLine++;
      if (script[index].kind !== '-') newLine++;
      index++;
      continue;
    }
    const hunk = [];
    const oldStart = oldLine;
    const newStart = newLine;
    let oldCount = 0;
    let newCount = 0;
    while (index < script.length && keep[index]) {
      const entry = script[index];
      hunk.push(`${entry.kind}${entry.text}`.trimEnd());
      if (entry.kind !== '+') {
        oldLine++;
        oldCount++;
      }
      if (entry.kind !== '-') {
        newLine++;
        newCount++;
      }
      index++;
    }
    lines.push(
      `@@ -${oldStart},${oldCount} +${newStart},${newCount} @@`,
      ...hunk,
    );
  }
  if (lines.length === 2)
    fail(`No difference between ${fromLabel} and ${toLabel}.`);
  return lines.join('\n');
}

function fillRegion(markdown, region, body, sourcePath) {
  const open = `<!-- noir:${region} -->`;
  const close = `<!-- /noir:${region} -->`;
  const start = markdown.indexOf(open);
  if (start < 0) return { markdown, filled: false };
  const end = markdown.indexOf(close, start);
  if (end < 0) fail(`${sourcePath} opens ${open} without ${close}.`);
  if (markdown.indexOf(open, start + open.length) >= 0) {
    fail(`${sourcePath} repeats ${open}.`);
  }
  return {
    markdown:
      markdown.slice(0, start + open.length) +
      `\n\n${body}\n\n` +
      markdown.slice(end),
    filled: true,
  };
}

/** Collapses indentation so a re-indented excerpt still matches its source. */
function withoutIndent(text) {
  return text
    .split('\n')
    .map((line) => line.trimEnd().replace(/^\s+/, ''))
    .filter((line, index, lines) => line !== '' || index < lines.length - 1)
    .join('\n')
    .trim();
}

function verifyExcerpts(markdown, checkpointSource, sourcePath) {
  const fences = [
    ...markdown.matchAll(
      /(<!-- noir:illustration -->\s*)?```dart\n([\s\S]*?)```/g,
    ),
  ];
  const haystack = withoutIndent(checkpointSource);
  for (const [, illustration, code] of fences) {
    if (illustration) continue;
    const needle = withoutIndent(code);
    if (needle === '' || haystack.includes(needle)) continue;
    fail(
      `${sourcePath} shows Dart that is not in its checkpoint. Copy it from ` +
        'the runnable file, or mark the fence <!-- noir:illustration -->.\n' +
        `First unmatched line: ${needle.split('\n')[0]}`,
    );
  }
}

function lessonRoute(lesson) {
  return lesson.slug ? `${taskListRoute}/${lesson.slug}` : taskListRoute;
}

function markdownTitle(markdown, sourcePath) {
  const heading = markdown.match(/^# (.+)$/m);
  if (!heading) fail(`${sourcePath} needs one level-one heading.`);
  return heading[1].trim();
}

function markdownDescription(markdown, sourcePath) {
  const body = markdown.slice(markdown.indexOf('\n', markdown.indexOf('# ')));
  const paragraph = body
    .split(/\n{2,}/)
    .map((block) => block.trim())
    .find(
      (block) =>
        block &&
        !block.startsWith('#') &&
        !block.startsWith('<') &&
        !block.startsWith('>') &&
        !block.startsWith('```') &&
        !block.startsWith('|'),
    );
  if (!paragraph) fail(`${sourcePath} needs an opening paragraph.`);
  const text = paragraph
    .replace(/\s+/g, ' ')
    .replace(/[[\]`]/g, '')
    .trim();
  let description = '';
  for (const sentence of text.split(/(?<=\.)\s+/)) {
    if (description && `${description} ${sentence}`.length > 160) break;
    description = description ? `${description} ${sentence}` : sentence;
  }
  return description;
}

/** Repository files that the website owns a page for. */
function routeMap() {
  const routes = new Map([
    [`${companionRoot}/README.md`, '/docs/installation'],
    [`${companionRoot}/doc/hooks.md`, '/docs/hooks'],
    [`${companionRoot}/doc/signals.md`, '/docs/signals'],
    ['README.md', '/docs/installation'],
  ]);
  for (const lesson of taskListLessons) {
    routes.set(lesson.source, lessonRoute(lesson));
  }
  return routes;
}

/**
 * Rewrites a relative link from package Markdown into a website destination.
 *
 * A file the website owns becomes its route. Any other repository file becomes
 * a canonical GitHub link, so one Markdown source works from the archive, from
 * GitHub, and from the documentation site.
 */
async function resolveLink(target, lesson, routes) {
  const [path, fragment] = target.split('#');
  const from = dirname(join(repositoryRoot, lesson.source));
  const absolute = resolve(from, path);
  const repositoryPath = relative(repositoryRoot, absolute)
    .split('\\')
    .join('/');
  if (repositoryPath.startsWith('..')) {
    fail(`${lesson.source} links outside the repository: ${target}`);
  }
  const route = routes.get(repositoryPath);
  const suffix = fragment ? `#${fragment}` : '';
  if (route) return `${route}${suffix}`;

  const stats = await stat(absolute).catch(() => null);
  if (!stats) fail(`${lesson.source} links to a missing file: ${target}`);
  const base = stats.isDirectory() ? treeBase : blobBase;
  return `${base}/${repositoryPath}${suffix}`;
}

async function toMdxBody(markdown, lesson, imageNames) {
  let body = markdown
    // Generator markers are Markdown comments; MDX does not accept them.
    .replace(/<!--[\s\S]*?-->\n?/g, '')
    .replace(/\]\((?:\.\.\/)*\.?\/?images\/([a-z0-9-]+\.jpg)\)/g, (_, name) => {
      imageNames.add(name);
      return `](/demos/signals-task-list/${name})`;
    });

  const routes = routeMap();
  const relativeLinks = [
    ...new Set(
      [...body.matchAll(/\]\((\.[^)\s]+)\)/g)].map((match) => match[1]),
    ),
  ];
  for (const target of relativeLinks) {
    const destination = await resolveLink(target, lesson, routes);
    body = body.split(`](${target})`).join(`](${destination})`);
  }
  // Every link must have become a website route or a canonical GitHub URL.
  const unresolved = [...body.matchAll(/\]\(([^)\s]+)\)/g)]
    .map((match) => match[1])
    .filter((target) => !target.startsWith('/') && !target.startsWith('http'));
  if (unresolved.length > 0) {
    fail(
      `${lesson.source} leaves a repository path in the generated page: ` +
        `${unresolved.join(', ')}. Write it as a relative link so the ` +
        'generator can resolve it.',
    );
  }
  return body.replace(/\n{3,}/g, '\n\n').trim();
}

async function syncTaskList() {
  const imageNames = new Set();
  const targetRoot = join(websiteRoot, 'src/content/docs/signals-task-list');
  await rm(join(websiteRoot, 'src/content/docs/signals-task-list.mdx'), {
    force: true,
  });
  await mkdir(targetRoot, { recursive: true });

  const checkpoints = [];
  for (const lesson of taskListLessons) {
    checkpoints.push(await readRepositoryFile(lesson.checkpoint));
  }

  const pages = [];
  for (const [index, lesson] of taskListLessons.entries()) {
    const sourcePath = lesson.source;
    let markdown = await readRepositoryFile(sourcePath);
    const checkpoint = checkpoints[index];

    const full = fillRegion(
      markdown,
      'file',
      ['```dart', checkpoint.trimEnd(), '```'].join('\n'),
      sourcePath,
    );
    markdown = full.markdown;
    if (!full.filled) {
      fail(`${sourcePath} must include a <!-- noir:file --> region.`);
    }

    if (index > 0) {
      const diff = unifiedDiff(
        checkpoints[index - 1],
        checkpoint,
        `lesson-${index}`,
        `lesson-${index + 1}`,
      );
      const applied = fillRegion(
        markdown,
        'diff',
        ['```diff', diff, '```'].join('\n'),
        sourcePath,
      );
      if (!applied.filled) {
        fail(`${sourcePath} must include a <!-- noir:diff --> region.`);
      }
      markdown = applied.markdown;
    }

    verifyExcerpts(markdown, checkpoint, sourcePath);
    await writeFile(join(repositoryRoot, sourcePath), markdown);

    const title = markdownTitle(markdown, sourcePath);
    const description = markdownDescription(markdown, sourcePath);
    const body = await toMdxBody(markdown, lesson, imageNames);
    const target = join(
      targetRoot,
      lesson.slug ? `${lesson.slug}.mdx` : 'index.mdx',
    );
    const page = `---
title: ${JSON.stringify(title)}
description: ${JSON.stringify(description)}
sourceUrl: ${blobBase}/${sourcePath}
---

{/* Generated by website/scripts/sync-docs.mjs from ${sourcePath}. */}

${body}
`;
    await writeFile(
      target,
      await format(page, { ...prettierConfig, filepath: target }),
    );
    pages.push(target);
  }

  const meta = `// Generated by website/scripts/sync-docs.mjs. Do not edit by hand.
const pages = {
  index: ${JSON.stringify(taskListLessons[0].navTitle)},
${taskListLessons
  .slice(1)
  .map(
    (lesson) =>
      `  ${JSON.stringify(lesson.slug)}: ${JSON.stringify(lesson.navTitle)},`,
  )
  .join('\n')}
};

export default pages;
`;
  const metaPath = join(targetRoot, '_meta.ts');
  await writeFile(
    metaPath,
    await format(meta, { ...prettierConfig, filepath: metaPath }),
  );

  const imageRoot = join(websiteRoot, 'public/demos/signals-task-list');
  await mkdir(imageRoot, { recursive: true });
  const sourceImages = join(repositoryRoot, companionRoot, 'doc/images');
  const available = new Set(await readdir(sourceImages));
  for (const name of imageNames) {
    if (!available.has(name)) fail(`Missing walkthrough image: ${name}`);
    await writeFile(
      join(imageRoot, name),
      await readFile(join(sourceImages, name)),
    );
  }
  return { pages: pages.length, images: imageNames.size };
}

/* ------------------------------------------------------------------ *
 * Entry point
 * ------------------------------------------------------------------ */

await mkdir(generatedRoot, { recursive: true });
const availability = await writeAvailability(await readAvailability());
const frames = await readFrames();
await writeFrames(frames);
await writeCheckpoints(frames);
const taskList = await syncTaskList();

console.log(
  `Synced availability (noir ${availability.noir.published}, ` +
    `noir_signals ${availability.companion.published}), ` +
    `${Object.keys(frames.frames).length} captured frames, ` +
    `${taskList.pages} task-list lessons, and ${taskList.images} screenshots.`,
);
