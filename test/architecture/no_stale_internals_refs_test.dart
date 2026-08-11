import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'no stale noir_internals references remain outside architecture lock',
    () {
      final staleRefs = <String>[];

      for (final file in _scannedFiles()) {
        final path = _normalizePath(file.path);
        final source = file.readAsStringSync();
        if (!source.contains('noir_internals')) {
          continue;
        }
        if (path == 'test/architecture/internals_barrel_split_test.dart' ||
            path == 'test/architecture/no_stale_internals_refs_test.dart') {
          continue;
        }
        staleRefs.add(path);
      }

      expect(
        staleRefs,
        isEmpty,
        reason:
            'noir_internals.dart has been deleted; stale docs and comments '
            'must point at noir_low_level.dart / noir_ffi.dart instead.',
      );
    },
  );
}

Iterable<File> _scannedFiles() sync* {
  for (final root in ['lib', 'test', 'example', 'bin']) {
    yield* _filesUnder(root).where((file) => file.path.endsWith('.dart'));
  }
  yield File('GOALS.md');
  yield* _filesUnder('tasks').where((file) => file.path.endsWith('.md'));
}

Iterable<File> _filesUnder(String path) sync* {
  final directory = Directory(path);
  if (!directory.existsSync()) return;
  yield* directory.listSync(recursive: true).whereType<File>();
}

String _normalizePath(String path) =>
    path.replaceAll(Platform.pathSeparator, '/');
