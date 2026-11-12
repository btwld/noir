import 'dart:io';

import 'package:test/test.dart';

/// Layers of `lib/src`, lowest first.
///
/// A file may import, export or include as a `part` any file in its own layer
/// or a lower one, never a higher one. Directories on the same rank do not
/// depend on each other at all.
const _layerRanks = <String, int>{
  'foundation': 0,
  'render': 0,
  'core': 1,
  'painting': 2,
  'rendering': 3,
  'framework': 4,
  'widgets': 5,
  'app': 6,
};

/// Directories outside the layer order, so neither imports from them nor
/// imports to them are checked here. `ffi` follows the native-layer rules;
/// `animation`, `scheduler` and `devtools` sit beside the framework.
const _unlayeredDirectories = {'animation', 'devtools', 'ffi', 'scheduler'};

void main() {
  test('every lib/src directory has a place in the layer order', () {
    final entries = Directory('lib/src')
        .listSync()
        .map((entry) => entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
        .toSet();
    final unclassified = entries.difference({
      ..._layerRanks.keys,
      ..._unlayeredDirectories,
    }).toList()..sort();

    expect(
      unclassified,
      isEmpty,
      reason:
          'Add each new lib/src directory to _layerRanks, or to '
          '_unlayeredDirectories with a reason.',
    );
  });

  test('lib/src never imports a higher layer', () {
    final root = Directory('lib/src').absolute.uri;
    final violations = <String>[];
    var checkedDirectives = 0;

    for (final file in Directory('lib/src').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.absolute.uri;
      final from = _topDirectory(root, source);
      final fromRank = _layerRanks[from];
      if (fromRank == null) continue;

      for (final directive in _directive.allMatches(file.readAsStringSync())) {
        for (final uri in _directiveUri.allMatches(directive.group(2)!)) {
          final target = uri.group(1)!;
          final to = _targetDirectory(root, source, target);
          final toRank = to == _publicBarrel
              ? _publicBarrelRank
              : _layerRanks[to];
          if (toRank == null) continue;
          checkedDirectives++;
          if (toRank > fromRank || (toRank == fromRank && to != from)) {
            final relative = source.path.substring(root.path.length);
            violations.add('$relative: ${directive.group(1)} $target');
          }
        }
      }
    }

    expect(checkedDirectives, greaterThan(0), reason: 'Scan found nothing.');
    expect(
      violations..sort(),
      isEmpty,
      reason:
          'Lower layers must not depend on higher ones. Move the shared '
          'declaration down to the lowest layer that uses it.',
    );
  });
}

/// Target for a `lib/noir*.dart` barrel, which ranks above every layer:
/// `lib/src` must never import the public surface it implements.
const _publicBarrel = '<public barrel>';
const _publicBarrelRank = 1 << 30;

/// An `import`, `export` or `part` statement up to its semicolon. Group 2
/// starts at the first URI, so it also holds any conditional-import URIs.
final _directive = RegExp(
  r'''^\s*(import|export|part)\s+(['"][^;]*);''',
  multiLine: true,
);

/// The primary URI of a directive, or a URI that follows an `if (...)`
/// configuration in a conditional import.
final _directiveUri = RegExp(r'''(?:^|\bif\s*\([^)]*\)\s*)['"]([^'"]+)['"]''');

/// Returns the first directory under [root] that contains [file], or null
/// when [file] is outside [root].
String? _topDirectory(Uri root, Uri file) {
  if (!file.path.startsWith(root.path)) return null;
  final segments = file.path.substring(root.path.length).split('/');
  return segments.length > 1 ? segments.first : null;
}

String? _targetDirectory(Uri root, Uri source, String uri) {
  if (uri.startsWith('dart:')) return null;
  const packagePrefix = 'package:noir/';
  if (uri.startsWith(packagePrefix)) {
    final path = uri.substring(packagePrefix.length);
    return path.startsWith('src/')
        ? path.substring('src/'.length).split('/').first
        : _publicBarrel;
  }
  if (uri.startsWith('package:')) return null;
  final target = source.resolve(uri);
  if (target.path.startsWith(root.path)) return _topDirectory(root, target);
  return target.path.startsWith(root.resolve('..').path) ? _publicBarrel : null;
}
