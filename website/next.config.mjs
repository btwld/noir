import nextra from 'nextra';

const basePath = process.env.NOIR_WEBSITE_BASE_PATH ?? '';

if (basePath && !/^\/[A-Za-z0-9._~-]+(?:\/[A-Za-z0-9._~-]+)*$/.test(basePath)) {
  throw new Error(
    'NOIR_WEBSITE_BASE_PATH must be empty or an absolute URL path without a trailing slash.',
  );
}

const withNextra = nextra({
  contentDirBasePath: '/',
  search: {
    codeblocks: false,
  },
});

export default withNextra({
  agentRules: false,
  basePath,
  images: {
    unoptimized: true,
  },
  output: 'export',
  reactStrictMode: true,
  trailingSlash: true,
});
