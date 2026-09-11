import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import {
  cp,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const repositoryRoot = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../..',
);
const imageRoot = 'packages/noir_signals/doc/images';
const framesPath = 'website/src/generated/terminal-frames.json';
const sha256 = (value) => createHash('sha256').update(value).digest('hex');

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'noir-sync-docs-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  for (const path of [
    'publication.json',
    'pubspec.yaml',
    'example/tutorials',
    'packages/noir_signals/README.md',
    'packages/noir_signals/pubspec.yaml',
    'packages/noir_signals/doc',
    'packages/noir_signals/example',
    'website/.prettierrc.json',
    'website/public/demos/signals-task-list',
    'website/scripts/sync-docs.mjs',
    'website/src',
  ]) {
    await mkdir(dirname(join(root, path)), { recursive: true });
    await cp(join(repositoryRoot, path), join(root, path), { recursive: true });
  }
  await symlink(
    join(repositoryRoot, 'website/node_modules'),
    join(root, 'website/node_modules'),
    'junction',
  );
  return {
    read: (path) => readFile(join(root, path), 'utf8'),
    write: (path, value) => writeFile(join(root, path), value),
    remove: (path) => rm(join(root, path)),
    sync: (...arguments_) =>
      execFileSync(process.execPath, ['scripts/sync-docs.mjs', ...arguments_], {
        cwd: join(root, 'website'),
        stdio: 'pipe',
        encoding: 'utf8',
      }),
  };
}

function rejectsSync(f, message) {
  assert.throws(f.sync, (error) => {
    assert.match(error.stderr, message);
    return true;
  });
}

test('the current documentation synchronizes', async (t) => {
  const f = await fixture(t);
  assert.match(f.sync(), /6 screenshots/);
});

test('the current generated documentation passes check mode', async (t) => {
  const f = await fixture(t);
  assert.match(f.sync('--check'), /6 screenshots/);
});

for (const path of [
  'website/src/generated/availability.ts',
  'website/src/generated/checkpoints.ts',
  'website/src/generated/frames.ts',
  'website/src/content/docs/signals-task-list/index.mdx',
  'website/public/demos/signals-task-list/01-screen.jpg',
]) {
  test(`check mode reports stale output without repairing ${path}`, async (t) => {
    const f = await fixture(t);
    const stale = 'outdated generated output';
    await f.write(path, stale);
    assert.throws(() => f.sync('--check'), /documentation is out of date/);
    assert.equal(await f.read(path), stale);
    assert.match(f.sync(), /6 screenshots/);
    assert.notEqual(await f.read(path), stale);
  });
}

test('check mode reports a missing generated file without creating it', async (t) => {
  const f = await fixture(t);
  const path = 'website/src/generated/availability.ts';
  await f.remove(path);
  assert.throws(() => f.sync('--check'), /documentation is out of date/);
  await assert.rejects(f.read(path), { code: 'ENOENT' });
});

test('check mode reports stale generated regions in canonical lessons', async (t) => {
  const f = await fixture(t);
  const path = 'packages/noir_signals/doc/getting-started.md';
  const stale = (await f.read(path)).replace(
    '<!-- noir:file -->',
    '<!-- noir:file -->\n\nstale generated code',
  );
  await f.write(path, stale);
  assert.throws(() => f.sync('--check'), /documentation is out of date/);
  assert.equal(await f.read(path), stale);
});

test('check mode reports an obsolete generated page without removing it', async (t) => {
  const f = await fixture(t);
  const path = 'website/src/content/docs/signals-task-list.mdx';
  await f.write(path, '# Obsolete generated page\n');
  assert.throws(() => f.sync('--check'), /documentation is out of date/);
  assert.equal(await f.read(path), '# Obsolete generated page\n');
});

test('recapturing changed padding cannot approve an unchanged JPEG', async (t) => {
  const f = await fixture(t);
  const sourcePath =
    'packages/noir_signals/example/tutorials/task_list/step_01.dart';
  const source = (await f.read(sourcePath)).replace(
    'horizontal: 2',
    'horizontal: 3',
  );
  await f.write(sourcePath, source);
  // Model the capture command's output without launching a Dart VM in a Node test.
  const frames = JSON.parse(await f.read(framesPath));
  const frame = frames.frames['task-list-screen'];
  frame.sourceSha256 = sha256(source);
  frame.lines = frame.lines.map((line) => (line ? ` ${line}` : line));
  frame.visualSha256 = sha256('the recaptured frame at padding 3');
  await f.write(framesPath, JSON.stringify(frames));
  rejectsSync(f, /01-screen\.jpg.*(?:stale|review)/i);
});

test('a style or cursor change requires screenshot review even with unchanged source and text', async (t) => {
  const f = await fixture(t);
  const frames = JSON.parse(await f.read(framesPath));
  frames.frames['task-list-screen'].visualSha256 = sha256(
    'changed cell styles or cursor',
  );
  await f.write(framesPath, JSON.stringify(frames));
  rejectsSync(f, /01-screen\.jpg.*(?:stale|review)/i);
});

test('replacing a JPEG requires updated review provenance', async (t) => {
  const f = await fixture(t);
  await f.write(`${imageRoot}/01-screen.jpg`, 'wrong image bytes');
  rejectsSync(f, /01-screen\.jpg.*(?:stale|review)/i);
});

test('a canonical lesson replaces stale generated release prose before validation', async (t) => {
  const f = await fixture(t);
  // Only Noir is published in this transition. Clear the existing authored
  // pages to isolate the generated lesson's before/after contract.
  await f.write(
    'publication.json',
    (await f.read('publication.json')).replace(
      '"noir": "0.0.1-alpha.4"',
      '"noir": "0.0.1"',
    ),
  );
  for (const path of [
    'docs/installation',
    'docs/hooks',
    'docs/platform-limitations',
    'docs/state-lifecycle',
    'docs/widget-catalog',
    'docs/widgets-layout',
  ]) {
    await f.write(`website/src/content/${path}.mdx`, '# Current release\n');
  }
  const path = 'website/src/content/docs/signals-task-list/index.mdx';
  await f.write(
    path,
    `${await f.read(path)}\nUses the unreleased next version.\n`,
  );
  assert.match(f.sync(), /5 task-list lessons/);
  assert.doesNotMatch(await f.read(path), /the unreleased next version/);
});

test('newly generated wrapped release contradictions fail in the same sync', async (t) => {
  const f = await fixture(t);
  await f.write(
    'publication.json',
    (await f.read('publication.json')).replace(
      '"noir": "0.0.1-alpha.4"',
      '"noir": "0.0.1"',
    ),
  );
  const source = 'packages/noir_signals/doc/getting-started.md';
  await f.write(
    source,
    `${await f.read(source)}\nRequires the unreleased Noir\n  0.0.1.\n`,
  );
  rejectsSync(
    f,
    /signals-task-list[/\\]index\.mdx says "unreleased Noir 0\.0\.1"/,
  );
});

test('wrapped authored release claims are rejected', async (t) => {
  const f = await fixture(t);
  await f.write(
    'publication.json',
    (await f.read('publication.json')).replace(
      '"noir": "0.0.1-alpha.4"',
      '"noir": "0.0.1"',
    ),
  );
  await f.write(
    'website/src/content/docs/hooks.mdx',
    '# Hooks\nRequires the unreleased Noir\n  0.0.1.\n',
  );
  rejectsSync(f, /hooks\.mdx says "unreleased Noir 0\.0\.1"/);
});

for (const version of [['0.0.1-alpha.4'], { version: '0.0.1-alpha.4' }]) {
  test(`publication rejects a non-string version: ${JSON.stringify(version)}`, async (t) => {
    const f = await fixture(t);
    await f.write(
      'publication.json',
      JSON.stringify({ noir: version, noir_signals: null }),
    );
    rejectsSync(f, /unusable noir version/);
  });
}

test('an invalid manifest version cannot generate availability', async (t) => {
  const f = await fixture(t);
  await f.write(
    'pubspec.yaml',
    (await f.read('pubspec.yaml')).replace(
      /^version: .+$/m,
      'version: invalid',
    ),
  );
  rejectsSync(f, /unusable.*version/);
});
