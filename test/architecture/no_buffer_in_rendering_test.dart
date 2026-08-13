import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('rendering and widgets never import Buffer directly', () {
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
      reason: 'The render-buffer migration budget is closed.',
    );
    expect(
      unexpectedImports,
      isEmpty,
      reason: 'Render objects must record paint through PaintingContext.',
    );
    expect(
      staleAllowlistEntries,
      isEmpty,
      reason: 'A closed allowlist cannot retain stale entries.',
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
