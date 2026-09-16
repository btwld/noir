// Generates every documentation fact that must not be maintained twice.
//
// The script owns four derivations and nothing else:
//
//   1. Package availability, from `publication.json` and the two
//      `pubspec.yaml` files.
//   2. Tutorial code, from the canonical runnable checkpoints in each
//      package's `example/`.
//   3. Captured terminal frames, from `packages/noir/tool/capture_doc_frames.dart`.
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

const driverRoot = 'packages/noir_driver';
const companionRoot = 'packages/noir_signals';
const taskListRoute = '/docs/signals-task-list';
const arguments_ = process.argv.slice(2);
if (arguments_.length > 1 || arguments_.some((value) => value !== '--check')) {
  throw new Error('Usage: node scripts/sync-docs.mjs [--check]');
}
const checkOnly = arguments_.includes('--check');
const outdatedOutputs = new Set();

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
  step01: 'packages/noir/example/tutorials/first_app/step_01.dart',
  step02: 'packages/noir/example/tutorials/first_app/step_02.dart',
};

function fail(message) {
  throw new Error(message);
}

function noteOutdated(path) {
  outdatedOutputs.add(relative(repositoryRoot, path).split('\\').join('/'));
}

async function writeOutput(path, value) {
  if (!checkOnly) return writeFile(path, value);
  try {
    if (!(await readFile(path)).equals(Buffer.from(value))) noteOutdated(path);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    noteOutdated(path);
  }
}

async function removeOutput(path) {
  if (!checkOnly) return rm(path, { force: true });
  try {
    await stat(path);
    noteOutdated(path);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

async function writeGenerated(name, source) {
  const target = join(generatedRoot, name);
  await writeOutput(
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

// Pre-release and build parts are dot-separated identifiers. An identifier
// never contains a dot, so each part has only one way to match.
const semanticVersion =
  /^\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;

function parseManifestVersion(pubspec, path) {
  const match = pubspec.match(/^version: (.+)$/m);
  if (!match) fail(`${path} has no version.`);
  const version = match[1].trim();
  if (!semanticVersion.test(version)) fail(`${path} has an unusable version.`);
  return version;
}

/**
 * Reads `publication.json`, the record of what is on pub.dev.
 *
 * Each key is a package name and each value is the latest published version
 * or `null`. Manifest versions come from the pubspecs themselves, so bumping
 * a version needs no second edit; publishing does.
 */
async function readAvailability() {
  let published;
  try {
    published = JSON.parse(await readRepositoryFile('publication.json'));
  } catch (error) {
    fail(`publication.json is not valid JSON: ${error.message}`);
  }
  if (published === null || typeof published !== 'object') {
    fail('publication.json must be an object of package name to version.');
  }

  const manifests = {
    noir: parseManifestVersion(
      await readRepositoryFile('packages/noir/pubspec.yaml'),
      'packages/noir/pubspec.yaml',
    ),
    noir_driver: parseManifestVersion(
      await readRepositoryFile(`${driverRoot}/pubspec.yaml`),
      `${driverRoot}/pubspec.yaml`,
    ),
    noir_signals: parseManifestVersion(
      await readRepositoryFile(`${companionRoot}/pubspec.yaml`),
      `${companionRoot}/pubspec.yaml`,
    ),
  };

  const packages = {};
  for (const [name, manifest] of Object.entries(manifests)) {
    if (!(name in published)) {
      fail(`publication.json does not record ${name}.`);
    }
    const version = published[name];
    if (
      version !== null &&
      (typeof version !== 'string' || !semanticVersion.test(version))
    ) {
      fail(`publication.json declares an unusable ${name} version.`);
    }
    packages[name] = { name, manifest, published: version ?? 'none' };
  }
  for (const name of Object.keys(published)) {
    if (!(name in manifests)) {
      fail(`publication.json records ${name}, which is not a package here.`);
    }
  }

  const noir = packages.noir;
  const driver = packages.noir_driver;
  const companion = packages.noir_signals;
  return {
    noir: {
      ...noir,
      isPublished: noir.published !== 'none',
      installCommand: 'dart pub add noir',
      label:
        noir.published === 'none'
          ? 'Not published yet · repository checkout only'
          : `Published version · ${noir.published}`,
    },
    driver: {
      ...driver,
      isPublished: driver.published !== 'none',
      installCommand: 'dart pub add --dev noir_driver',
      label:
        driver.published === 'none'
          ? 'Not published yet · repository checkout only'
          : `Published version · ${driver.published}`,
    },
    companion: {
      ...companion,
      isPublished: companion.published !== 'none',
      installCommand: 'dart pub add noir_signals',
      label:
        companion.published === 'none'
          ? 'Not published yet · repository checkout only'
          : `Published version · ${companion.published}`,
    },
  };
}

async function writeAvailability(availability) {
  const source = `// Generated by scripts/sync-docs.mjs from publication.json and the package manifests.
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
  readonly driver: PackageAvailability;
  readonly companion: PackageAvailability;
} = ${JSON.stringify(availability, null, 2)} as const;
`;
  await writeGenerated('availability.ts', source);
  return availability;
}

/**
 * Holds authored release claims to the availability data.
 *
 * The label beside a dependency is generated, but the sentences around it are
 * written by hand. Publishing a package would otherwise leave a page saying
 * the version it just installed cannot be installed.
 */
async function checkReleaseClaims(availability) {
  const contentRoot = join(websiteRoot, 'src/content');
  const pages = [];
  async function collect(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) await collect(path);
      else if (entry.name.endsWith('.mdx')) pages.push(path);
    }
  }
  await collect(contentRoot);

  const unpublishedCompanion = [
    'not on pub.dev yet',
    'cannot resolve from pub.dev',
    'is not published',
    'unpublished companion',
  ];
  // A page may never call the published version unreleased. The vaguer
  // "next version" wording is only a contradiction once nothing newer is
  // pending in the manifest.
  const noirManifestIsPublished =
    availability.noir.published === availability.noir.manifest;
  const unreleasedNoir = [
    ...(availability.noir.isPublished
      ? [
          `unreleased Noir ${availability.noir.published.replace(/^\d+\.\d+\.\d+-/, '')}`,
        ]
      : []),
    ...(noirManifestIsPublished ? ['the unreleased next version'] : []),
  ];

  const contradictions = [];
  let statesCompanionIsUnpublished = false;
  for (const page of pages) {
    const source = (await readFile(page, 'utf8'))
      .replace(/\s+/g, ' ')
      .toLowerCase();
    const name = relative(repositoryRoot, page).split('\\').join('/');
    for (const claim of unpublishedCompanion) {
      if (!source.includes(claim.toLowerCase())) continue;
      statesCompanionIsUnpublished = true;
      if (availability.companion.isPublished) {
        contradictions.push(
          `${name} says "${claim}", but publication.json records noir_signals ` +
            `${availability.companion.published} on pub.dev.`,
        );
      }
    }
    for (const claim of unreleasedNoir) {
      if (!source.includes(claim.toLowerCase())) continue;
      contradictions.push(
        `${name} says "${claim}", but publication.json records noir ` +
          `${availability.noir.published} on pub.dev.`,
      );
    }
  }

  if (!availability.companion.isPublished && !statesCompanionIsUnpublished) {
    contradictions.push(
      'noir_signals is unpublished, but no page says so. A reader would ' +
        'follow a dependency block that cannot resolve.',
    );
  }
  if (contradictions.length > 0) {
    fail(
      `Release claims disagree with publication.json:\n- ${contradictions.join('\n- ')}`,
    );
  }
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
  const imageRoot = join(repositoryRoot, companionRoot, 'doc/images');
  const provenance = JSON.parse(
    await readFile(join(imageRoot, 'provenance.json'), 'utf8'),
  );
  for (const [id, frame] of Object.entries(document.frames)) {
    const source = await readRepositoryFile(frame.entrypoint);
    if (sha256(source) !== frame.sourceSha256) {
      fail(
        `Captured frame "${id}" no longer matches ${frame.entrypoint}. Run ` +
          '`dart run tool/capture_doc_frames.dart` from packages/noir and commit the result.',
      );
    }
    if (frame.image) {
      const reviewed = provenance[frame.image];
      const imageHash = sha256(await readFile(join(imageRoot, frame.image)));
      if (
        !/^[a-f0-9]{64}$/.test(frame.visualSha256 ?? '') ||
        reviewed?.sourceSha256 !== frame.sourceSha256 ||
        reviewed?.visualSha256 !== frame.visualSha256 ||
        reviewed?.imageSha256 !== imageHash
      ) {
        fail(
          `Screenshot ${frame.image} is stale or needs review. Recapture and ` +
            'review the JPEG, then update doc/images/provenance.json as described ' +
            'in packages/noir_signals/doc/images/README.md. Text recapture does not approve images.',
        );
      }
    }
    // The styled runs are what a page draws; the lines are what a reader can
    // search and a scene expects. Both must describe the same cells.
    const painted = (frame.runs ?? []).map((row) =>
      row
        .map((run) => run.text)
        .join('')
        .trimEnd(),
    );
    const text = Array.from(
      { length: frame.height },
      (_, row) => frame.lines[row] ?? '',
    );
    if (
      painted.length !== frame.height ||
      painted.some((row, index) => row !== text[index])
    ) {
      fail(
        `Captured frame "${id}" has styled runs that disagree with its text. ` +
          'Run `dart run tool/capture_doc_frames.dart` from packages/noir and commit the result.',
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
// packages/noir/tool/capture_doc_frames.dart output. Do not edit by hand.

/** Adjacent cells that share one style. Omitted fields are unstyled. */
export interface TerminalRun {
  readonly text: string;
  readonly fg?: string;
  readonly bg?: string;
  /** OpenTUI attribute bits: bold 1, dim 2, italic 4, underline 8, blink 16,
   *  reverse 32, strikethrough 64. */
  readonly attrs?: number;
}

export interface TerminalFrameData {
  readonly title: string;
  readonly command: string;
  readonly entrypoint: string;
  readonly width: number;
  readonly height: number;
  readonly interaction: string;
  /** The walkthrough screenshot this scene backs, when it has one. */
  readonly image?: string;
  readonly sourceSha256: string;
  readonly visualSha256: string;
  readonly lines: readonly string[];
  /** One entry per terminal row, including trailing blank rows. */
  readonly runs: readonly (readonly TerminalRun[])[];
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
  if (route) {
    if (fragment) {
      fail(
        `${lesson.source} links to ${target}. The website owns that file as ` +
          `${route}, whose headings differ, so the anchor cannot be carried ` +
          'over. Link the page without a fragment.',
      );
    }
    return route;
  }
  const suffix = fragment ? `#${fragment}` : '';

  const stats = await stat(absolute).catch(() => null);
  if (!stats) fail(`${lesson.source} links to a missing file: ${target}`);
  const base = stats.isDirectory() ? treeBase : blobBase;
  return `${base}/${repositoryPath}${suffix}`;
}

/**
 * Removes Markdown comments, which MDX does not accept.
 *
 * One pass can join the halves of a nested marker into a new comment opener,
 * so the removal repeats until the text stops changing.
 */
function stripComments(markdown, lesson) {
  let previous;
  let current = markdown;
  do {
    previous = current;
    current = current.replace(/<!--[\s\S]*?-->\n?/g, '');
  } while (current !== previous);
  if (current.includes('<!--')) {
    fail(`${lesson.source} has an unterminated Markdown comment.`);
  }
  return current;
}

async function toMdxBody(markdown, lesson, imageNames) {
  let body = stripComments(markdown, lesson).replace(
    /\]\((?:\.\.\/)*\.?\/?images\/([a-z0-9-]+\.jpg)\)/g,
    (_, name) => {
      imageNames.add(name);
      return `](/demos/signals-task-list/${name})`;
    },
  );

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
  await removeOutput(
    join(websiteRoot, 'src/content/docs/signals-task-list.mdx'),
  );
  if (!checkOnly) await mkdir(targetRoot, { recursive: true });

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
    await writeOutput(join(repositoryRoot, sourcePath), markdown);

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
    await writeOutput(
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
  await writeOutput(
    metaPath,
    await format(meta, { ...prettierConfig, filepath: metaPath }),
  );

  const imageRoot = join(websiteRoot, 'public/demos/signals-task-list');
  if (!checkOnly) await mkdir(imageRoot, { recursive: true });
  const sourceImages = join(repositoryRoot, companionRoot, 'doc/images');
  const available = new Set(await readdir(sourceImages));
  for (const name of imageNames) {
    if (!available.has(name)) fail(`Missing walkthrough image: ${name}`);
    await writeOutput(
      join(imageRoot, name),
      await readFile(join(sourceImages, name)),
    );
  }
  return { pages: pages.length, images: imageNames.size };
}

/* ------------------------------------------------------------------ *
 * Entry point
 * ------------------------------------------------------------------ */

if (!checkOnly) await mkdir(generatedRoot, { recursive: true });
const availability = await writeAvailability(await readAvailability());
const frames = await readFrames();
await writeFrames(frames);
await writeCheckpoints(frames);
const taskList = await syncTaskList();
if (outdatedOutputs.size > 0) {
  fail(
    `Generated documentation is out of date:\n- ${[...outdatedOutputs].join('\n- ')}\n` +
      'Run npm run sync and commit the regenerated files with the source change.',
  );
}
await checkReleaseClaims(availability);

console.log(
  `${checkOnly ? 'Checked' : 'Synced'} availability (noir ${availability.noir.published}, ` +
    `noir_driver ${availability.driver.published}, ` +
    `noir_signals ${availability.companion.published}), ` +
    `${Object.keys(frames.frames).length} captured frames, ` +
    `${taskList.pages} task-list lessons, and ${taskList.images} screenshots.`,
);
