// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'git_path.dart';
import 'models.dart';

class UnifiedDiffParser {
  DiffSet parse(List<int> envelopeBytes) {
    final envelope = _parseEnvelope(envelopeBytes);
    if (envelope.records.isEmpty) return const DiffSet([]);
    final blocks = _splitPatchBlocks(envelope.patchBytes);
    final expectedBlockCount = envelope.records.fold(
      0,
      (count, record) =>
          count + (record.changeKind == DiffChangeKind.typeChanged ? 2 : 1),
    );
    if (blocks.length != expectedBlockCount) {
      throw FormatException(
        'Raw records require $expectedBlockCount patch blocks, '
        'but ${blocks.length} were present.',
      );
    }

    final files = <DiffFile>[];
    var blockIndex = 0;
    for (final record in envelope.records) {
      if (record.changeKind == DiffChangeKind.typeChanged) {
        files.add(
          _parseTypeChangeGroup(
            record,
            blocks[blockIndex],
            blocks[blockIndex + 1],
          ),
        );
        blockIndex += 2;
        continue;
      }
      final block = _parsePatchBlock(record, blocks[blockIndex]);
      files.add(
        _fileFromRecord(
          record,
          payloadKind: block.payloadKind,
          headerLines: block.headerLines,
          hunks: block.hunks,
          contentPatchHeader: block.contentPatchHeader,
        ),
      );
      blockIndex++;
    }
    return DiffSet(List<DiffFile>.unmodifiable(files));
  }
}

_ParsedEnvelope _parseEnvelope(List<int> source) {
  final bytes = List<int>.of(source, growable: false);
  for (var i = 0; i < bytes.length; i++) {
    final byte = bytes[i];
    if (byte < 0 || byte > 0xff) {
      throw RangeError.range(byte, 0, 0xff, 'envelopeBytes[$i]');
    }
  }
  if (bytes.isEmpty) {
    return const _ParsedEnvelope(records: [], patchBytes: []);
  }

  final records = <_RawRecord>[];
  var offset = 0;
  while (true) {
    if (offset >= bytes.length || bytes[offset] != 0x3a) {
      throw const FormatException(
        'A non-empty tracked diff must begin with :.',
      );
    }
    final metadataEnd = _nextNul(bytes, offset);
    final metadata = _parseRawMetadata(bytes.sublist(offset, metadataEnd));
    offset = metadataEnd + 1;

    final firstPathEnd = _nextNul(bytes, offset);
    final firstPath = _gitPath(bytes.sublist(offset, firstPathEnd));
    offset = firstPathEnd + 1;

    GitPath? secondPath;
    if (metadata.status == 'C' || metadata.status == 'R') {
      final secondPathEnd = _nextNul(bytes, offset);
      secondPath = _gitPath(bytes.sublist(offset, secondPathEnd));
      offset = secondPathEnd + 1;
    }

    if (metadata.status == 'U' || metadata.status == 'X') {
      throw FormatException('Unsupported raw Git status ${metadata.status}.');
    }
    records.add(_recordFromMetadata(metadata, firstPath, secondPath));

    if (offset >= bytes.length) {
      throw const FormatException(
        'Tracked diff is missing its patch separator.',
      );
    }
    if (bytes[offset] == 0) {
      offset++;
      break;
    }
    if (bytes[offset] != 0x3a) {
      throw const FormatException(
        'Expected another raw record or the raw/patch separator.',
      );
    }
  }

  if (offset >= bytes.length) {
    throw const FormatException(
      'Raw records require corresponding patch blocks.',
    );
  }
  return _ParsedEnvelope(
    records: List<_RawRecord>.unmodifiable(records),
    patchBytes: List<int>.unmodifiable(bytes.sublist(offset)),
  );
}

GitDiffMetadata _parseRawMetadata(List<int> bytes) {
  final text = _ascii(bytes, 'raw diff metadata');
  final match = _rawMetadataPattern.firstMatch(text);
  if (match == null) {
    throw FormatException('Invalid raw diff metadata: $text');
  }
  final oldObjectId = match.group(3)!;
  final newObjectId = match.group(4)!;
  if (oldObjectId.length != newObjectId.length) {
    throw const FormatException('Raw object IDs must have the same width.');
  }
  final status = match.group(5)!;
  final scoreText = match.group(6);
  final score = scoreText == null ? null : int.parse(scoreText);
  if (score != null && score > 100) {
    throw FormatException('Raw diff score is outside 0..100: $scoreText');
  }
  final scoreAllowed = status == 'M' || status == 'C' || status == 'R';
  if (!scoreAllowed && score != null) {
    throw FormatException('Raw diff status $status cannot have a score.');
  }
  if ((status == 'C' || status == 'R') && score == null) {
    throw FormatException('Raw diff status $status requires a score.');
  }
  return GitDiffMetadata(
    oldMode: match.group(1)!,
    newMode: match.group(2)!,
    oldObjectId: oldObjectId,
    newObjectId: newObjectId,
    status: status,
    score: score,
  );
}

final _rawMetadataPattern = RegExp(
  '^:([0-7]{6}) ([0-7]{6}) '
  '([0-9a-f]{40}|[0-9a-f]{64}) '
  '([0-9a-f]{40}|[0-9a-f]{64}) '
  r'([ACDMRTUX])([0-9]{1,3})?$',
);

_RawRecord _recordFromMetadata(
  GitDiffMetadata metadata,
  GitPath firstPath,
  GitPath? secondPath,
) {
  final (oldPath, newPath, changeKind) = switch (metadata.status) {
    'A' => (null, firstPath, DiffChangeKind.added),
    'D' => (firstPath, null, DiffChangeKind.deleted),
    'M' => (firstPath, firstPath, DiffChangeKind.modified),
    'T' => (firstPath, firstPath, DiffChangeKind.typeChanged),
    'R' => (firstPath, secondPath!, DiffChangeKind.renamed),
    'C' => (firstPath, secondPath!, DiffChangeKind.copied),
    _ => throw StateError('Rejected raw status reached model conversion.'),
  };
  return _RawRecord(
    oldPath: oldPath,
    newPath: newPath,
    changeKind: changeKind,
    metadata: metadata,
  );
}

List<List<int>> _splitPatchBlocks(List<int> bytes) {
  const marker = <int>[
    0x64,
    0x69,
    0x66,
    0x66,
    0x20,
    0x2d,
    0x2d,
    0x67,
    0x69,
    0x74,
    0x20,
  ];
  if (!_matchesAt(bytes, 0, marker)) {
    throw const FormatException('Patch portion must begin with diff --git.');
  }
  final starts = <int>[0];
  for (var i = 1; i < bytes.length; i++) {
    if (bytes[i - 1] == 0x0a && _matchesAt(bytes, i, marker)) {
      starts.add(i);
    }
  }
  return [
    for (var i = 0; i < starts.length; i++)
      List<int>.unmodifiable(
        bytes.sublist(starts[i], i + 1 < starts.length ? starts[i + 1] : null),
      ),
  ];
}

_ParsedPatchBlock _parsePatchBlock(_RawRecord record, List<int> blockBytes) {
  final inspection = _inspectStructuralHeaders(record, blockBytes);
  if (inspection.binary) {
    return _ParsedPatchBlock(
      payloadKind: DiffPayloadKind.binary,
      headerLines: inspection.headerLines,
      hunks: const [],
      contentPatchHeader: inspection.contentPatchHeader,
    );
  }

  final String block;
  try {
    block = utf8.decode(blockBytes);
  } on FormatException {
    return _ParsedPatchBlock(
      payloadKind: DiffPayloadKind.unsupportedTextEncoding,
      headerLines: inspection.headerLines,
      hunks: const [],
      contentPatchHeader: inspection.contentPatchHeader,
    );
  }

  final lines = block.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  final hunks = <DiffHunk>[];
  _HunkBuilder? hunk;

  void finishHunk() {
    final current = hunk;
    if (current == null) return;
    hunks.add(current.build(record.pathIdentity));
    hunk = null;
  }

  for (var i = inspection.firstPayloadLine; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('@@ ')) {
      finishHunk();
      hunk = _HunkBuilder.parse(line);
      continue;
    }
    final current = hunk;
    if (current != null) current.rawLines.add(line);
  }
  finishHunk();

  return _ParsedPatchBlock(
    payloadKind: DiffPayloadKind.text,
    headerLines: inspection.headerLines,
    hunks: hunks,
    contentPatchHeader: inspection.contentPatchHeader,
  );
}

DiffFile _parseTypeChangeGroup(
  _RawRecord record,
  List<int> deletionBlock,
  List<int> additionBlock,
) {
  final deletion = _parsePatchBlock(
    _RawRecord(
      oldPath: record.oldPath,
      newPath: null,
      changeKind: DiffChangeKind.deleted,
      metadata: record.metadata,
    ),
    deletionBlock,
  );
  final addition = _parsePatchBlock(
    _RawRecord(
      oldPath: null,
      newPath: record.newPath,
      changeKind: DiffChangeKind.added,
      metadata: record.metadata,
    ),
    additionBlock,
  );
  _requireTypeChangeModeMarker(
    deletion.headerLines,
    requiredLine: 'deleted file mode ${record.metadata.oldMode}',
    requiredPrefix: 'deleted file mode ',
    forbiddenPrefix: 'new file mode ',
  );
  _requireTypeChangeModeMarker(
    addition.headerLines,
    requiredLine: 'new file mode ${record.metadata.newMode}',
    requiredPrefix: 'new file mode ',
    forbiddenPrefix: 'deleted file mode ',
  );

  return _fileFromRecord(
    record,
    payloadKind: _combinedPayloadKind(
      deletion.payloadKind,
      addition.payloadKind,
    ),
    headerLines: [...deletion.headerLines, ...addition.headerLines],
    hunks: const [],
  );
}

void _requireTypeChangeModeMarker(
  List<String> headerLines, {
  required String requiredLine,
  required String requiredPrefix,
  required String forbiddenPrefix,
}) {
  final matchingPrefix = headerLines.where(
    (line) => line.startsWith(requiredPrefix),
  );
  if (matchingPrefix.length != 1 || matchingPrefix.single != requiredLine) {
    throw FormatException(
      'Type-change block requires exact marker: $requiredLine',
    );
  }
  if (headerLines.any(
    (line) =>
        line.startsWith(forbiddenPrefix) ||
        line.startsWith('old mode ') ||
        line.startsWith('new mode '),
  )) {
    throw const FormatException(
      'Type-change block contains an incompatible mode marker.',
    );
  }
}

DiffPayloadKind _combinedPayloadKind(
  DiffPayloadKind first,
  DiffPayloadKind second,
) {
  if (first == DiffPayloadKind.unsupportedTextEncoding ||
      second == DiffPayloadKind.unsupportedTextEncoding) {
    return DiffPayloadKind.unsupportedTextEncoding;
  }
  if (first == DiffPayloadKind.binary || second == DiffPayloadKind.binary) {
    return DiffPayloadKind.binary;
  }
  return DiffPayloadKind.text;
}

_HeaderInspection _inspectStructuralHeaders(
  _RawRecord record,
  List<int> blockBytes,
) {
  final lines = _splitByteLines(blockBytes);
  if (lines.isEmpty || !_startsWithAscii(lines.first, 'diff --git ')) {
    throw const FormatException('Patch block is missing diff --git.');
  }

  final headerLines = <String>[];
  GitPath? oldHeaderPath;
  GitPath? newHeaderPath;
  GitPath? renameFrom;
  GitPath? renameTo;
  GitPath? copyFrom;
  GitPath? copyTo;
  var oldHeaderSeen = false;
  var newHeaderSeen = false;
  String? oldFileLine;
  String? newFileLine;
  var renameFromSeen = false;
  var renameToSeen = false;
  var copyFromSeen = false;
  var copyToSeen = false;
  var binary = false;
  var firstPayloadLine = lines.length;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (_startsWithAscii(line, '@@ ')) {
      firstPayloadLine = i;
      break;
    }
    final text = _ascii(line, 'patch structural header');
    headerLines.add(text);

    if (_startsWithAscii(line, 'GIT binary patch') ||
        _startsWithAscii(line, 'Binary files ')) {
      binary = true;
      firstPayloadLine = i + 1;
      break;
    }
    if (_startsWithAscii(line, '--- ')) {
      if (oldHeaderSeen || newHeaderSeen) {
        throw const FormatException('Duplicate or out-of-order --- header.');
      }
      oldHeaderSeen = true;
      oldFileLine = text;
      oldHeaderPath = _decodePatchSide(
        line.sublist(4),
        structuralPrefix: const [0x61, 0x2f],
      );
      continue;
    }
    if (_startsWithAscii(line, '+++ ')) {
      if (!oldHeaderSeen || newHeaderSeen) {
        throw const FormatException('Duplicate or out-of-order +++ header.');
      }
      newHeaderSeen = true;
      newFileLine = text;
      newHeaderPath = _decodePatchSide(
        line.sublist(4),
        structuralPrefix: const [0x62, 0x2f],
      );
      continue;
    }
    if (_startsWithAscii(line, 'rename from ')) {
      if (renameFromSeen || renameToSeen) {
        throw const FormatException('Duplicate or out-of-order rename from.');
      }
      renameFromSeen = true;
      renameFrom = _decodeGitPathField(line.sublist(12));
      continue;
    }
    if (_startsWithAscii(line, 'rename to ')) {
      if (!renameFromSeen || renameToSeen) {
        throw const FormatException('Duplicate or out-of-order rename to.');
      }
      renameToSeen = true;
      renameTo = _decodeGitPathField(line.sublist(10));
      continue;
    }
    if (_startsWithAscii(line, 'copy from ')) {
      if (copyFromSeen || copyToSeen) {
        throw const FormatException('Duplicate or out-of-order copy from.');
      }
      copyFromSeen = true;
      copyFrom = _decodeGitPathField(line.sublist(10));
      continue;
    }
    if (_startsWithAscii(line, 'copy to ')) {
      if (!copyFromSeen || copyToSeen) {
        throw const FormatException('Duplicate or out-of-order copy to.');
      }
      copyToSeen = true;
      copyTo = _decodeGitPathField(line.sublist(8));
    }
  }

  if (oldHeaderSeen != newHeaderSeen) {
    throw const FormatException('Patch requires a complete ---/+++ pair.');
  }
  if (oldHeaderSeen) {
    _requireSamePath(oldHeaderPath, record.oldPath, '---');
    _requireSamePath(newHeaderPath, record.newPath, '+++');
  }
  if (!binary &&
      firstPayloadLine < lines.length &&
      !oldHeaderSeen &&
      record.changeKind != DiffChangeKind.renamed &&
      record.changeKind != DiffChangeKind.copied) {
    throw const FormatException('A textual hunk requires --- and +++ headers.');
  }

  if (record.changeKind == DiffChangeKind.renamed) {
    if (!renameFromSeen || !renameToSeen || copyFromSeen || copyToSeen) {
      throw const FormatException('Rename records require one from/to pair.');
    }
    _requireSamePath(renameFrom, record.oldPath, 'rename from');
    _requireSamePath(renameTo, record.newPath, 'rename to');
  } else if (record.changeKind == DiffChangeKind.copied) {
    if (!copyFromSeen || !copyToSeen || renameFromSeen || renameToSeen) {
      throw const FormatException('Copy records require one from/to pair.');
    }
    _requireSamePath(copyFrom, record.oldPath, 'copy from');
    _requireSamePath(copyTo, record.newPath, 'copy to');
  } else if (renameFromSeen || renameToSeen || copyFromSeen || copyToSeen) {
    throw const FormatException(
      'Non-rename/copy record contains rename/copy headers.',
    );
  }

  return _HeaderInspection(
    headerLines: List<String>.unmodifiable(headerLines),
    firstPayloadLine: firstPayloadLine,
    binary: binary,
    contentPatchHeader: oldHeaderSeen
        ? ContentPatchHeader(
            diffGitLine: headerLines.first,
            oldFileLine: oldFileLine!,
            newFileLine: newFileLine!,
          )
        : null,
  );
}

DiffFile _fileFromRecord(
  _RawRecord record, {
  required DiffPayloadKind payloadKind,
  required List<String> headerLines,
  required List<DiffHunk> hunks,
  ContentPatchHeader? contentPatchHeader,
}) => DiffFile(
  oldPath: record.oldPath,
  newPath: record.newPath,
  changeKind: record.changeKind,
  payloadKind: payloadKind,
  headerLines: headerLines,
  hunks: hunks,
  rawMetadata: record.metadata,
  contentPatchHeader: contentPatchHeader,
);

GitPath? _decodePatchSide(
  List<int> field, {
  required List<int> structuralPrefix,
}) {
  const devNull = <int>[0x2f, 0x64, 0x65, 0x76, 0x2f, 0x6e, 0x75, 0x6c, 0x6c];
  if (field.length == devNull.length && _matchesAt(field, 0, devNull)) {
    return null;
  }
  final decoded = _decodeGitPathBytes(field);
  if (!_matchesAt(decoded, 0, structuralPrefix)) {
    throw const FormatException('Patch path is missing its structural prefix.');
  }
  return _gitPath(decoded.sublist(structuralPrefix.length));
}

GitPath _decodeGitPathField(List<int> field) =>
    _gitPath(_decodeGitPathBytes(field));

List<int> _decodeGitPathBytes(List<int> field) {
  if (field.isEmpty) {
    throw const FormatException('Git pathname field is empty.');
  }
  if (field.first != 0x22) {
    if (field.contains(0x22)) {
      throw const FormatException('Unquoted Git pathname contains a quote.');
    }
    return List<int>.of(field, growable: false);
  }
  if (field.length < 2 || field.last != 0x22) {
    throw const FormatException('Quoted Git pathname is not closed.');
  }

  final result = <int>[];
  for (var i = 1; i < field.length - 1; i++) {
    final byte = field[i];
    if (byte == 0x22) {
      throw const FormatException('Quoted Git pathname has an early quote.');
    }
    if (byte != 0x5c) {
      result.add(byte);
      continue;
    }
    if (++i >= field.length - 1) {
      throw const FormatException('Quoted Git pathname has a trailing slash.');
    }
    final escaped = field[i];
    final mnemonic = switch (escaped) {
      0x22 => 0x22,
      0x5c => 0x5c,
      0x61 => 0x07,
      0x62 => 0x08,
      0x74 => 0x09,
      0x6e => 0x0a,
      0x76 => 0x0b,
      0x66 => 0x0c,
      0x72 => 0x0d,
      _ => null,
    };
    if (mnemonic != null) {
      result.add(mnemonic);
      continue;
    }
    if (!_isOctal(escaped) ||
        i + 2 >= field.length - 1 ||
        !_isOctal(field[i + 1]) ||
        !_isOctal(field[i + 2])) {
      throw const FormatException(
        'Git octal pathname escapes require exactly three digits.',
      );
    }
    final value =
        (escaped - 0x30) * 64 + (field[i + 1] - 0x30) * 8 + field[i + 2] - 0x30;
    if (value > 0xff) {
      throw const FormatException(
        'Git octal pathname escape exceeds one byte.',
      );
    }
    result.add(value);
    i += 2;
  }
  return result;
}

// GitPath.fromBytes is the single owner of the repository-relative path
// domain (non-empty, no NUL, no edge slashes, no empty/./.. components);
// the parser only maps its rejection to the diff-level FormatException.
// Byte-range RangeErrors are unreachable here: _parseEnvelope pre-validates
// 0..0xff and _decodeGitPathBytes caps octal escapes, so the ArgumentError
// catch (which RangeError subclasses) only ever sees domain rejection.
GitPath _gitPath(List<int> bytes) {
  try {
    return GitPath.fromBytes(bytes);
    // The GitPath factory contract reports domain rejection as ArgumentError;
    // translating it here is the delegation point, not error-flow control.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    throw const FormatException('Invalid repository-relative Git path.');
  }
}

void _requireSamePath(GitPath? actual, GitPath? expected, String header) {
  if (actual != expected) {
    throw FormatException('$header path does not match the raw Git record.');
  }
}

List<List<int>> _splitByteLines(List<int> bytes) {
  final lines = <List<int>>[];
  var start = 0;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] != 0x0a) continue;
    lines.add(List<int>.unmodifiable(bytes.sublist(start, i)));
    start = i + 1;
  }
  if (start < bytes.length) {
    lines.add(List<int>.unmodifiable(bytes.sublist(start)));
  }
  return lines;
}

int _nextNul(List<int> bytes, int start) {
  for (var i = start; i < bytes.length; i++) {
    if (bytes[i] == 0) return i;
  }
  throw const FormatException('Tracked diff contains a truncated NUL field.');
}

String _ascii(List<int> bytes, String owner) {
  for (final byte in bytes) {
    if (byte > 0x7f) {
      throw FormatException('$owner must contain ASCII only.');
    }
  }
  return ascii.decode(bytes);
}

bool _startsWithAscii(List<int> bytes, String prefix) =>
    _matchesAt(bytes, 0, ascii.encode(prefix));

bool _matchesAt(List<int> bytes, int offset, List<int> expected) {
  if (offset < 0 || offset + expected.length > bytes.length) return false;
  for (var i = 0; i < expected.length; i++) {
    if (bytes[offset + i] != expected[i]) return false;
  }
  return true;
}

bool _isOctal(int byte) => byte >= 0x30 && byte <= 0x37;

class _HunkBuilder {
  _HunkBuilder({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.sectionHeading,
    required this.rawHeader,
  });

  factory _HunkBuilder.parse(String line) {
    final match = _headerPattern.firstMatch(line);
    if (match == null) {
      throw FormatException('Invalid unified diff hunk header: $line');
    }
    return _HunkBuilder(
      oldStart: int.parse(match.group(1)!),
      oldCount: int.parse(match.group(2) ?? '1'),
      newStart: int.parse(match.group(3)!),
      newCount: int.parse(match.group(4) ?? '1'),
      sectionHeading: match.group(5) ?? '',
      rawHeader: line,
    );
  }

  static final _headerPattern = RegExp(
    r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?: (.*))?$',
  );

  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String sectionHeading;
  final String rawHeader;
  final List<String> rawLines = [];

  DiffHunk build(GitPath filePath) {
    var nextOldLine = oldStart;
    var nextNewLine = newStart;
    final lines = <DiffLine>[];

    for (final rawLine in rawLines) {
      if (rawLine.startsWith('+')) {
        lines.add(
          DiffLine(
            type: DiffLineType.addition,
            text: rawLine.substring(1),
            raw: rawLine,
            oldLineNumber: null,
            newLineNumber: nextNewLine++,
          ),
        );
        continue;
      }
      if (rawLine.startsWith('-')) {
        lines.add(
          DiffLine(
            type: DiffLineType.deletion,
            text: rawLine.substring(1),
            raw: rawLine,
            oldLineNumber: nextOldLine++,
            newLineNumber: null,
          ),
        );
        continue;
      }
      if (rawLine.startsWith(r'\')) {
        lines.add(
          DiffLine(
            type: DiffLineType.noNewlineMarker,
            text: rawLine,
            raw: rawLine,
            oldLineNumber: null,
            newLineNumber: null,
          ),
        );
        continue;
      }
      lines.add(
        DiffLine(
          type: DiffLineType.context,
          text: rawLine.startsWith(' ') ? rawLine.substring(1) : rawLine,
          raw: rawLine,
          oldLineNumber: nextOldLine++,
          newLineNumber: nextNewLine++,
        ),
      );
    }

    return DiffHunk.fromLines(
      filePath: filePath,
      oldStart: oldStart,
      oldCount: oldCount,
      newStart: newStart,
      newCount: newCount,
      sectionHeading: sectionHeading,
      rawHeader: rawHeader,
      lines: lines,
    );
  }
}

final class _ParsedPatchBlock {
  _ParsedPatchBlock({
    required this.payloadKind,
    required List<String> headerLines,
    required List<DiffHunk> hunks,
    required this.contentPatchHeader,
  }) : headerLines = List<String>.unmodifiable(headerLines),
       hunks = List<DiffHunk>.unmodifiable(hunks);

  final DiffPayloadKind payloadKind;
  final List<String> headerLines;
  final List<DiffHunk> hunks;
  final ContentPatchHeader? contentPatchHeader;
}

final class _ParsedEnvelope {
  const _ParsedEnvelope({required this.records, required this.patchBytes});

  final List<_RawRecord> records;
  final List<int> patchBytes;
}

final class _RawRecord {
  const _RawRecord({
    required this.oldPath,
    required this.newPath,
    required this.changeKind,
    required this.metadata,
  });

  final GitPath? oldPath;
  final GitPath? newPath;
  final DiffChangeKind changeKind;
  final GitDiffMetadata metadata;

  GitPath get pathIdentity => newPath ?? oldPath!;
}

final class _HeaderInspection {
  const _HeaderInspection({
    required this.headerLines,
    required this.firstPayloadLine,
    required this.binary,
    required this.contentPatchHeader,
  });

  final List<String> headerLines;
  final int firstPayloadLine;
  final bool binary;
  final ContentPatchHeader? contentPatchHeader;
}
