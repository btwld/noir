import 'dart:io';

import 'package:test/test.dart';

/// Documentation links must reach something that exists in this repository.
///
/// The website, the package guides, and the example catalogs all publish
/// canonical GitHub links. A renamed or deleted file turns one of them into a
/// dead end that nothing else reports.
const _blobPrefix = 'https://github.com/btwld/noir/blob/main/';
const _treePrefix = 'https://github.com/btwld/noir/tree/main/';

const _documentationRoots = <String>[
  '../../website/src',
  '../noir_signals/doc',
  '../noir_signals/example',
  'example',
];

const _standaloneDocuments = <String>[
  'README.md',
  '../../CONTRIBUTING.md',
  '../../AGENTS.md',
  '../noir_signals/README.md',
  '../../website/README.md',
  '../../website/DESIGN.md',
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
            ? Directory('../../$target').existsSync()
            : File('../../$target').existsSync();
        if (!exists) broken.add('${document.path} -> $prefix$target');
      }
    }
    expect(broken, isEmpty);
  });

  test('every internal website link reaches a page or an asset', () {
    // Derive the routes from the content tree instead of listing them. A
    // generated lesson page must not be able to escape this check.
    const contentRoot = '../../website/src/content';
    final routes = <String>{'/'};
    for (final file
        in Directory(contentRoot)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.mdx'))) {
      final relative = file.path
          .substring(contentRoot.length + 1)
          .replaceAll(r'\', '/')
          .replaceAll(RegExp(r'\.mdx$'), '');
      routes.add('/${relative.replaceAll(RegExp(r'(^|/)index$'), '')}');
    }
    expect(routes, contains('/docs/signals-task-list'));
    expect(routes, contains('/docs/signals-task-list/filter-and-clear'));
    expect(routes, contains('/docs/widgets/text-input'));

    final unknown = <String>{};
    for (final document in documents.where(
      (file) => file.path.startsWith('../../website/src'),
    )) {
      for (final match in RegExp(
        r'''(?:\]\(|href=")(/[a-zA-Z0-9/._-]*)''',
      ).allMatches(document.readAsStringSync())) {
        final target = match.group(1)!.replaceAll(RegExp(r'(?<=.)/$'), '');
        if (target.startsWith('/demos/')) {
          // A generated asset path must name a file the site publishes.
          if (!File('../../website/public$target').existsSync()) {
            unknown.add('${document.path} -> $target (missing asset)');
          }
          continue;
        }
        if (routes.contains(target)) continue;
        unknown.add('${document.path} -> $target');
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
