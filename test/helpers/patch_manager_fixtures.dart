import 'dart:convert';

import '../../scripts/patch_manager/patch_manager.dart';

GitPath fixturePath(String path) => GitPath.utf8(path);

String presentedPath(DiffFile file) =>
    GitPathPresentation.asciiSafe(file.pathIdentity).full;

GitCommandResult fixtureGitResult({
  int exitCode = 0,
  String stdout = '',
  String stderr = '',
  Iterable<int>? stdoutBytes,
  Iterable<int>? stderrBytes,
}) => GitCommandResult(
  exitCode: exitCode,
  stdoutBytes: stdoutBytes ?? utf8.encode(stdout),
  stderrBytes: stderrBytes ?? utf8.encode(stderr),
);

DiffSet parsePatchFixture(String patch, {List<PatchFixtureRecord>? records}) =>
    UnifiedDiffParser().parse(buildPatchEnvelope(patch, records: records));

List<int> buildPatchEnvelope(
  String patch, {
  List<PatchFixtureRecord>? records,
}) {
  final normalized = patch.startsWith('\n') ? patch.substring(1) : patch;
  final blocks = _patchBlocks(normalized);
  final effectiveRecords =
      records ?? [for (final block in blocks) _inferRecord(block)];
  final expectedBlockCount = effectiveRecords.fold(
    0,
    (count, record) => count + (record.status == 'T' ? 2 : 1),
  );
  if (expectedBlockCount != blocks.length) {
    throw ArgumentError('Patch fixture blocks must match raw-record arity.');
  }

  final output = <int>[];
  for (final record in effectiveRecords) {
    output
      ..addAll(
        ascii.encode(
          ':${record.oldMode} ${record.newMode} '
          '${record.oldObjectId} ${record.newObjectId} '
          '${record.status}${record.score ?? ''}',
        ),
      )
      ..add(0);
    final firstPath = record.oldPath ?? record.newPath!;
    output
      ..addAll(firstPath.bytes)
      ..add(0);
    if (record.status == 'R' || record.status == 'C') {
      output
        ..addAll(record.newPath!.bytes)
        ..add(0);
    }
  }
  output
    ..add(0)
    ..addAll(utf8.encode(normalized));
  return List<int>.unmodifiable(output);
}

final class PatchFixtureRecord {
  PatchFixtureRecord({
    required this.status,
    required this.oldPath,
    required this.newPath,
    this.oldMode = '100644',
    this.newMode = '100644',
    this.score,
    String? oldObjectId,
    String? newObjectId,
  }) : oldObjectId = oldObjectId ?? (oldPath == null ? '0' * 40 : '1' * 40),
       newObjectId = newObjectId ?? (newPath == null ? '0' * 40 : '2' * 40);

  final String status;
  final GitPath? oldPath;
  final GitPath? newPath;
  final String oldMode;
  final String newMode;
  final int? score;
  final String oldObjectId;
  final String newObjectId;
}

List<String> _patchBlocks(String patch) {
  final starts = <int>[0];
  for (var offset = patch.indexOf('\ndiff --git '); offset >= 0;) {
    starts.add(offset + 1);
    offset = patch.indexOf('\ndiff --git ', offset + 1);
  }
  return [
    for (var i = 0; i < starts.length; i++)
      patch.substring(
        starts[i],
        i + 1 < starts.length ? starts[i + 1] : patch.length,
      ),
  ];
}

PatchFixtureRecord _inferRecord(String block) {
  final lines = block.split('\n');
  final diffLine = lines.first;
  if (!diffLine.startsWith('diff --git a/')) {
    throw ArgumentError(
      'Quoted fixture paths require an explicit PatchFixtureRecord.',
    );
  }

  final secondPrefix = diffLine.lastIndexOf(' b/');
  if (secondPrefix < 0) {
    throw ArgumentError('Cannot infer fixture paths from $diffLine');
  }
  var oldPath = GitPath.utf8(
    diffLine.substring('diff --git a/'.length, secondPrefix),
  );
  var newPath = GitPath.utf8(diffLine.substring(secondPrefix + 3));
  var status = 'M';
  int? score;
  var oldMode = '100644';
  var newMode = '100644';

  for (final line in lines) {
    if (line.startsWith('new file mode ')) {
      status = 'A';
      oldPath = newPath;
      oldMode = '000000';
      newMode = line.substring('new file mode '.length);
    } else if (line.startsWith('deleted file mode ')) {
      status = 'D';
      newPath = oldPath;
      oldMode = line.substring('deleted file mode '.length);
      newMode = '000000';
    } else if (line.startsWith('rename from ')) {
      status = 'R';
      score = 100;
      oldPath = GitPath.utf8(line.substring('rename from '.length));
    } else if (line.startsWith('rename to ')) {
      newPath = GitPath.utf8(line.substring('rename to '.length));
    } else if (line.startsWith('copy from ')) {
      status = 'C';
      score = 100;
      oldPath = GitPath.utf8(line.substring('copy from '.length));
    } else if (line.startsWith('copy to ')) {
      newPath = GitPath.utf8(line.substring('copy to '.length));
    }
  }

  return PatchFixtureRecord(
    status: status,
    oldPath: status == 'A' ? null : oldPath,
    newPath: status == 'D' ? null : newPath,
    oldMode: oldMode,
    newMode: newMode,
    score: score,
  );
}
