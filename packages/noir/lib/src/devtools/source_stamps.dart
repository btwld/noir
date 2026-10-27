import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// Change identity and VM reload timestamp for one watched Dart source.
@internal
typedef SourceStamp = ({DateTime modified, int size, String digest});

/// Snapshots Dart sources without starting the hot-reload process runner.
@internal
Map<String, SourceStamp> readSourceStamps(List<Directory> roots) {
  final stamps = <String, SourceStamp>{};
  for (final root in roots) {
    if (!root.existsSync()) continue;
    final List<FileSystemEntity> entries;
    try {
      entries = root.listSync(recursive: true, followLinks: false);
    } on FileSystemException {
      // A root or descendant can disappear during the recursive listing.
      // Keep watching the other roots and retry this one on the next poll.
      continue;
    }
    for (final entity in entries) {
      if (entity is File && entity.path.endsWith('.dart')) {
        try {
          // Source tools may preserve both length and mtime. Content identity
          // must still change so the runner reaches its forced-reload policy.
          final bytes = entity.readAsBytesSync();
          final stat = entity.statSync();
          if (stat.type != FileSystemEntityType.file) continue;
          stamps[entity.absolute.path] = (
            modified: stat.modified,
            size: bytes.length,
            digest: sha256.convert(bytes).toString(),
          );
        } on PathNotFoundException {
          // An editor can remove a listed source during a save. A later poll
          // will observe its replacement; other read failures still propagate.
          continue;
        }
      }
    }
  }
  return stamps;
}
