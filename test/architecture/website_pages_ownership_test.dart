import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('website exports one GitHub Pages-compatible static artifact', () {
    final config = _read('website/next.config.mjs');
    final package = _read('website/package.json');

    expect(config, contains("output: 'export'"));
    expect(config, contains('trailingSlash: true'));
    expect(config, contains('unoptimized: true'));
    expect(config, contains('process.env.NOIR_WEBSITE_BASE_PATH'));
    expect(config, contains('basePath,'));
    expect(
      package,
      contains(
        '"postbuild": "pagefind --site out --output-path out/_pagefind"',
      ),
    );
  });

  test('Pages workflow builds the website and deploys only its export', () {
    final workflow = _read('.github/workflows/pages.yml');

    expect(workflow, contains('push:\n    branches: [main]'));
    expect(workflow, contains('  workflow_dispatch:'));
    expect(
      workflow,
      contains(r'NOIR_WEBSITE_BASE_PATH: ${{ steps.pages.outputs.base_path }}'),
    );
    expect(workflow, contains('working-directory: website'));
    expect(workflow, contains('run: npm ci'));
    expect(workflow, contains('run: npm run build'));
    expect(workflow, contains('path: website/out'));
    expect(workflow, contains('needs: build'));
    expect(workflow, contains('pages: write'));
    expect(workflow, contains('id-token: write'));
    expect(workflow, contains('name: github-pages'));

    final actionLines = workflow
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('uses:'));
    expect(actionLines, isNotEmpty);
    for (final line in actionLines) {
      expect(
        line,
        matches(RegExp(r'^uses: [^@ ]+@[0-9a-f]{40}(?: # v[^ ]+)?$')),
        reason: 'mutable or malformed action reference: $line',
      );
    }
  });

  test('website records the Pages URL and deployment boundary', () {
    final readme = _read('website/README.md');

    expect(readme, contains('https://conceptadev.github.io/noir/'));
    expect(readme, contains('Source: GitHub Actions'));
    expect(readme, contains('website/out'));
    expect(readme, contains('NOIR_WEBSITE_BASE_PATH=/noir'));
  });
}

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');
