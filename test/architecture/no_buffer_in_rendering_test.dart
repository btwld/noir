import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('rendering and widgets never import Buffer directly', () {
    final unexpectedImports = <String>[];

    for (final file in [
      ..._dartFilesUnder('lib/src/rendering'),
      ..._dartFilesUnder('lib/src/widgets'),
    ]) {
      final path = _normalizePath(file.path);
      final importsBuffer = _importsBuffer(file.readAsStringSync());

      if (importsBuffer) {
        unexpectedImports.add(path);
      }
    }

    expect(
      unexpectedImports,
      isEmpty,
      reason: 'Render objects must record paint through PaintingContext.',
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
