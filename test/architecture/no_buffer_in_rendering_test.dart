import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('rendering Buffer imports are limited to the Phase 4 allowlist', () {
    const allowlistedBufferImports = <String>{};

    final unexpectedImports = <String>[];
    final staleAllowlistEntries = <String>[];
    final seenAllowlistEntries = <String>{};

    for (final file in [
      ..._dartFilesUnder('lib/src/rendering'),
      ..._dartFilesUnder('lib/src/widgets'),
    ]) {
      final path = _normalizePath(file.path);
      final importsBuffer = _importsBuffer(file.readAsStringSync());

      if (allowlistedBufferImports.contains(path)) {
        seenAllowlistEntries.add(path);
        if (!importsBuffer) {
          staleAllowlistEntries.add(path);
        }
      } else if (importsBuffer) {
        unexpectedImports.add(path);
      }
    }

    expect(
      allowlistedBufferImports,
      isEmpty,
      reason: 'Phase 4 removes the render-buffer migration budget.',
    );
    expect(
      unexpectedImports,
      isEmpty,
      reason: 'New render objects must not import Buffer during migration.',
    );
    expect(
      staleAllowlistEntries,
      isEmpty,
      reason: 'Remove files from the allowlist as Phase 4 migrates them.',
    );
    expect(
      seenAllowlistEntries,
      containsAll(allowlistedBufferImports),
      reason: 'Allowlist entries must point at existing rendering files.',
    );
  });
}

Iterable<File> _dartFilesUnder(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

bool _importsBuffer(String source) =>
    source.contains("import '../core/buffer.dart';") ||
    source.contains('src/core/buffer.dart');

String _normalizePath(String path) =>
    path.replaceAll(Platform.pathSeparator, '/');
