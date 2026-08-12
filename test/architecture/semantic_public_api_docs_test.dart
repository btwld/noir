import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('authored public API docs do not use known filler forms', () {
    final matches = <_FillerMatch>[];

    for (final file in _authoredLibraryFiles()) {
      final path = _normalizePath(file.path);
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final source = lines[index];
        for (final family in _families) {
          if (family.pattern.hasMatch(source)) {
            matches.add(
              _FillerMatch(
                path: path,
                line: index + 1,
                family: family.name,
                source: source,
              ),
            );
          }
        }
      }
    }

    final totals = <String, int>{
      for (final family in _families) family.name: 0,
    };
    for (final match in matches) {
      totals.update(match.family, (count) => count + 1);
    }
    final files = matches.map((match) => match.path).toSet();
    final diagnostics = matches
        .map(
          (match) =>
              '${match.path}:${match.line} [${match.family}] ${match.source}',
        )
        .join('\n');

    expect(
      matches,
      isEmpty,
      reason:
          'Authored Dartdoc must state a source-backed guarantee instead of '
          'a known filler form.\n'
          'Totals: value=${totals['value']}, runs=${totals['runs']}, '
          'creates=${totals['creates']}, '
          'typeFiller=${totals['typeFiller']}; files=${files.length}; '
          'union=${matches.length}.\n'
          '$diagnostics',
    );
  });
}

const _excludedGeneratedFiles = <String>{
  'lib/src/ffi/generated_bindings.dart',
  'lib/src/ffi/native_asset_bindings.dart',
};

final _families = <({String name, RegExp pattern})>[
  (name: 'value', pattern: RegExp(r'^\s*/// The .* value\.$')),
  (name: 'runs', pattern: RegExp(r'^\s*/// Runs [A-Za-z_][A-Za-z0-9_]*\.$')),
  (
    name: 'creates',
    pattern: RegExp(r'^\s*/// Creates (a|an) [A-Za-z_][A-Za-z0-9_<>]*\.$'),
  ),
  (
    name: 'typeFiller',
    pattern: RegExp(
      r'^\s*/// ([A-Za-z_][A-Za-z0-9_<>]* (type|mixin|callback type)'
      r'|Values for [A-Za-z_][A-Za-z0-9_<>]*)\.$',
    ),
  ),
];

Iterable<File> _authoredLibraryFiles() {
  final files =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where(
            (file) =>
                !_excludedGeneratedFiles.contains(_normalizePath(file.path)),
          )
          .toList()
        ..sort(
          (left, right) =>
              _normalizePath(left.path).compareTo(_normalizePath(right.path)),
        );
  return files;
}

String _normalizePath(String path) =>
    path.replaceAll(Platform.pathSeparator, '/');

class _FillerMatch {
  const _FillerMatch({
    required this.path,
    required this.line,
    required this.family,
    required this.source,
  });

  final String path;
  final int line;
  final String family;
  final String source;
}
