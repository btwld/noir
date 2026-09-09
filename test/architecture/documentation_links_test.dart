import 'dart:io';

import 'package:test/test.dart';

/// Documentation links must reach something that exists in this repository.
///
/// The website, the package guides, and the example catalogs all publish
/// canonical GitHub links. A renamed or deleted file turns one of them into a
/// dead end that nothing else reports.
const _blobPrefix = 'https://github.com/conceptadev/noir/blob/main/';
const _treePrefix = 'https://github.com/conceptadev/noir/tree/main/';

const _documentationRoots = <String>[
  'website/src',
  'packages/noir_signals/doc',
  'packages/noir_signals/example',
  'example',
];

const _standaloneDocuments = <String>[
  'README.md',
  'CONTRIBUTING.md',
  'AGENTS.md',
  'packages/noir_signals/README.md',
  'website/README.md',
  'website/DESIGN.md',
];

void main() {
  final documents = <File>[
    for (final path in _standaloneDocuments) File(path),
    for (final root in _documentationRoots)
      ...Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => _isDocumentation(file.path)),
  ];

  test('documentation covers the sources this check reads', () {
    expect(documents.length, greaterThan(20));
    for (final document in documents) {
      expect(document.existsSync(), isTrue, reason: document.path);
    }
  });

  test('every canonical GitHub link names a real repository path', () {
    final broken = <String>[];
    for (final document in documents) {
      final source = document.readAsStringSync();
      for (final match in RegExp(
        '($_blobPrefix|$_treePrefix)'
        r'([^)\s"`]+)',
      ).allMatches(source)) {
        final prefix = match.group(1)!;
        final target = match.group(2)!.split('#').first;
        final exists = prefix == _treePrefix
            ? Directory(target).existsSync()
            : File(target).existsSync();
        if (!exists) broken.add('${document.path} -> $prefix$target');
      }
    }
    expect(broken, isEmpty);
  });

  test('website routes named in documentation exist as content', () {
    final routes = <String, String>{
      '/docs': 'website/src/content/docs/index.mdx',
      '/docs/getting-started': 'website/src/content/docs/getting-started.mdx',
      '/docs/installation': 'website/src/content/docs/installation.mdx',
      '/docs/signals-task-list':
          'website/src/content/docs/signals-task-list/index.mdx',
      '/docs/hooks': 'website/src/content/docs/hooks.mdx',
      '/docs/signals': 'website/src/content/docs/signals.mdx',
      '/docs/input-focus': 'website/src/content/docs/input-focus.mdx',
      '/docs/command-line-arguments':
          'website/src/content/docs/command-line-arguments.mdx',
      '/docs/testing': 'website/src/content/docs/testing.mdx',
      '/docs/widgets-layout': 'website/src/content/docs/widgets-layout.mdx',
      '/docs/state-lifecycle': 'website/src/content/docs/state-lifecycle.mdx',
      '/docs/architecture-api': 'website/src/content/docs/architecture-api.mdx',
      '/docs/widget-catalog': 'website/src/content/docs/widget-catalog.mdx',
      '/docs/widgets/text-input':
          'website/src/content/docs/widgets/text-input.mdx',
      '/docs/platform-limitations':
          'website/src/content/docs/platform-limitations.mdx',
      '/examples': 'website/src/content/examples.mdx',
      '/api': 'website/src/content/api.mdx',
    };
    for (final entry in routes.entries) {
      expect(
        File(entry.value).existsSync(),
        isTrue,
        reason: '${entry.key} has no content file',
      );
    }

    // Every internal link the website publishes must be one of those routes,
    // the homepage, or a route with a fragment.
    final unknown = <String>{};
    for (final document in documents.where(
      (file) => file.path.startsWith('website/src'),
    )) {
      for (final match in RegExp(
        r'''(?:\]\(|href=")(/[a-z0-9/-]*)''',
      ).allMatches(document.readAsStringSync())) {
        final route = match.group(1)!.replaceAll(RegExp(r'/$'), '');
        if (route.isEmpty || route.startsWith('/demos')) continue;
        if (routes.containsKey(route)) continue;
        if (route.startsWith('/docs/signals-task-list/')) continue;
        unknown.add('${document.path} -> $route');
      }
    }
    expect(unknown, isEmpty);
  });
}

bool _isDocumentation(String path) =>
    path.endsWith('.md') ||
    path.endsWith('.mdx') ||
    path.endsWith('.tsx') ||
    path.endsWith('.ts');
