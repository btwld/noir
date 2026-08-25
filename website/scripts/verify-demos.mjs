import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const demos = [
  ['chat-loading.cast', 64, 16],
  ['components-spinner.cast', 80, 24],
  ['counter.cast', 64, 18],
  ['like-reactor.cast', 72, 24],
  ['pub-search.cast', 100, 30],
  ['pulse-animation.cast', 56, 18],
];

await Promise.all(
  demos.map(async ([fileName, width, height]) => {
    const path = resolve('public/demos', fileName);
    const source = await readFile(path, 'utf8');
    const [headerLine] = source.split('\n');
    const header = JSON.parse(headerLine);

    if (
      header.version !== 2 ||
      header.width !== width ||
      header.height !== height
    ) {
      throw new Error(
        `${fileName} is not the reviewed ${width}x${height} asciicast v2.`,
      );
    }
  }),
);

console.log(`Verified ${demos.length} reviewed asciicast v2 demos.`);
