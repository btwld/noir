import { createServer } from 'node:http';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { dirname, extname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(import.meta.url);
const websiteRoot = resolve(dirname(scriptPath), '..');

const contentTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.txt': 'text/plain; charset=utf-8',
  '.wasm': 'application/wasm',
};

export function normalizeBasePath(value = '') {
  if (!value) return '';
  if (!/^\/[A-Za-z0-9._~-]+(?:\/[A-Za-z0-9._~-]+)*$/.test(value)) {
    throw new Error(
      'The base path must be empty or an absolute URL path without a trailing slash.',
    );
  }
  return value;
}

function exportedPath(outputRoot, requestPath, basePath) {
  let decodedPath;
  try {
    decodedPath = decodeURIComponent(requestPath);
  } catch {
    return null;
  }

  let sitePath = decodedPath;
  if (basePath) {
    if (sitePath === basePath) {
      sitePath = '/';
    } else if (sitePath.startsWith(`${basePath}/`)) {
      sitePath = sitePath.slice(basePath.length);
    } else {
      return null;
    }
  }

  const relativePath = sitePath.replace(/^\/+/, '');
  const candidates = sitePath.endsWith('/')
    ? [join(relativePath, 'index.html')]
    : [relativePath, `${relativePath}.html`, join(relativePath, 'index.html')];

  for (const candidate of candidates) {
    const filePath = resolve(outputRoot, candidate);
    const fromRoot = relative(outputRoot, filePath);
    if (fromRoot === '..' || fromRoot.startsWith(`..${sep}`)) continue;
    if (existsSync(filePath) && statSync(filePath).isFile()) return filePath;
  }
  return null;
}

export async function startStaticExport({
  basePath = process.env.NOIR_WEBSITE_BASE_PATH,
  hostname = process.env.NOIR_WEBSITE_HOST ?? '127.0.0.1',
  outputRoot = join(websiteRoot, 'out'),
  port = Number(process.env.NOIR_WEBSITE_PORT ?? 3018),
} = {}) {
  const normalizedBasePath = normalizeBasePath(basePath);
  if (!existsSync(join(outputRoot, 'index.html'))) {
    throw new Error('Run npm run build before serving the static export.');
  }

  const server = createServer((request, response) => {
    const requestUrl = new URL(request.url ?? '/', `http://${hostname}`);
    let filePath = exportedPath(
      outputRoot,
      requestUrl.pathname,
      normalizedBasePath,
    );
    let status = 200;
    if (!filePath) {
      filePath = join(outputRoot, '404.html');
      status = 404;
    }

    const body = readFileSync(filePath);
    response.writeHead(status, {
      'Content-Length': body.length,
      'Content-Type':
        contentTypes[extname(filePath)] ?? 'application/octet-stream',
    });
    response.end(body);
  });

  await new Promise((resolveListen, rejectListen) => {
    server.once('error', rejectListen);
    server.listen(port, hostname, resolveListen);
  });
  return server;
}

if (process.argv[1] === scriptPath) {
  const basePath = normalizeBasePath(process.env.NOIR_WEBSITE_BASE_PATH);
  const hostname = process.env.NOIR_WEBSITE_HOST ?? '127.0.0.1';
  const port = Number(process.env.NOIR_WEBSITE_PORT ?? 3018);
  await startStaticExport({ basePath, hostname, port });
  console.log(`Serving website/out at http://${hostname}:${port}${basePath}/`);
}
