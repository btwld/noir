// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:characters/characters.dart';

import '../../core/grapheme_metrics.dart';
import 'diff_parser.dart';
import 'git_path.dart';
import 'models.dart';
import 'patch_generator.dart';

const _binaryProbeByteLimit = 8000;
const _fileByteLimit = 65536;
const _workspaceByteLimit = 1048576;
const _fileLineLimit = 400;
const _workspaceLineLimit = 4000;
const _fileCellLimit = 32 * 1024;
const _workspaceCellLimit = 256 * 1024;

class GitPatchRepository {
  GitPatchRepository({
    String? worktreePath,
    GitCommandRunner? runner,
    UnifiedDiffParser? parser,
    PatchGenerator? patchGenerator,
    Future<String> Function(String path)? linkTargetReader,
  }) : worktreePath = worktreePath ?? Directory.current.path,
       _runner =
           runner ??
           ProcessGitCommandRunner(worktreePath ?? Directory.current.path),
       _parser = parser ?? UnifiedDiffParser(),
       _patchGenerator = patchGenerator ?? PatchGenerator(),
       _linkTargetReader = linkTargetReader ?? _readLinkTarget;

  final String worktreePath;
  final GitCommandRunner _runner;
  final UnifiedDiffParser _parser;
  final PatchGenerator _patchGenerator;
  final Future<String> Function(String path) _linkTargetReader;

  Future<DiffSet> loadTrackedDiff() async {
    final result = await _runner.run([
      '-c',
      'core.quotePath=true',
      'diff',
      '--no-ext-diff',
      '--no-color',
      '--raw',
      '-z',
      '--patch',
      '--unified=3',
      '--abbrev=64',
      '--src-prefix=a/',
      '--dst-prefix=b/',
      '--',
    ]);
    if (result.exitCode != 0) {
      throw GitPatchException(
        GitDiagnosticText.fromBytes(result.stderrBytes).text,
      );
    }
    return _parser.parse(result.stdoutBytes);
  }

  Future<DiffSet> loadWorkspace() async {
    final tracked = await loadTrackedDiff();
    final untracked = await _loadUntrackedFiles();
    return DiffSet([...tracked.files, ...untracked]);
  }

  Future<GitStageResult> stageContent(ContentStageSelection selection) async {
    final patch = _patchGenerator.buildContentPatch(selection);
    final patchBytes = utf8.encode(patch);

    final GitCommandResult check;
    try {
      check = await _runner.run([
        'apply',
        '--cached',
        '--check',
        '--whitespace=nowarn',
        '-',
      ], stdinBytes: patchBytes);
    } on Object catch (error) {
      return _runnerExceptionStageResult(
        phase: 'content apply check',
        error: error,
        outcome: GitStageOutcome.rejectedUnchanged,
        patch: patch,
      );
    }
    if (check.exitCode != 0) {
      return _stageResultFromCommand(
        check,
        outcome: GitStageOutcome.rejectedUnchanged,
        patch: patch,
      );
    }

    final GitCommandResult result;
    try {
      result = await _runner.run([
        'apply',
        '--cached',
        '--whitespace=nowarn',
        '-',
      ], stdinBytes: patchBytes);
    } on Object catch (error) {
      return _runnerExceptionStageResult(
        phase: 'content apply mutation',
        error: error,
        outcome: GitStageOutcome.failedRefreshRequired,
        patch: patch,
      );
    }
    return _stageResultFromCommand(
      result,
      outcome: result.exitCode == 0
          ? GitStageOutcome.applied
          : GitStageOutcome.rejectedUnchanged,
      patch: patch,
    );
  }

  Future<GitStageResult> stageWholeFile(WholeFileChange change) async {
    final input = _pathspecInput(change.pathspecs);

    final GitCommandResult check;
    try {
      check = await _runner.run([
        '--literal-pathspecs',
        'add',
        '--no-ignore-errors',
        '--dry-run',
        '--pathspec-from-file=-',
        '--pathspec-file-nul',
      ], stdinBytes: input);
    } on Object catch (error) {
      return _runnerExceptionStageResult(
        phase: 'whole-file add dry-run',
        error: error,
        outcome: GitStageOutcome.rejectedUnchanged,
        patch: '',
      );
    }
    if (check.exitCode != 0) {
      return _stageResultFromCommand(
        check,
        outcome: GitStageOutcome.rejectedUnchanged,
        patch: '',
      );
    }

    final GitCommandResult result;
    try {
      result = await _runner.run([
        '--literal-pathspecs',
        'add',
        '--no-ignore-errors',
        '--pathspec-from-file=-',
        '--pathspec-file-nul',
      ], stdinBytes: input);
    } on Object catch (error) {
      return _runnerExceptionStageResult(
        phase: 'whole-file add mutation',
        error: error,
        outcome: GitStageOutcome.failedRefreshRequired,
        patch: '',
      );
    }
    return _stageResultFromCommand(
      result,
      outcome: result.exitCode == 0
          ? GitStageOutcome.applied
          : GitStageOutcome.failedRefreshRequired,
      patch: '',
    );
  }

  Future<List<DiffFile>> _loadUntrackedFiles() async {
    final result = await _runner.run([
      'ls-files',
      '--others',
      '--exclude-standard',
      '-z',
    ]);
    if (result.exitCode != 0) {
      throw GitPatchException(
        GitDiagnosticText.fromBytes(result.stderrBytes).text,
      );
    }
    final paths = _parseNulPaths(result.stdoutBytes);
    final loader = _UntrackedPreviewLoader(
      worktreePath: worktreePath,
      linkTargetReader: _linkTargetReader,
    );
    final files = <DiffFile>[];
    for (final path in paths) {
      files.add(await loader.load(path));
    }
    return files;
  }
}

class _UntrackedPreviewLoader {
  _UntrackedPreviewLoader({
    required this.worktreePath,
    required this.linkTargetReader,
  });

  final String worktreePath;
  final Future<String> Function(String path) linkTargetReader;
  final _PreviewBudget budget = _PreviewBudget();

  Future<DiffFile> load(GitPath path) async {
    final fullPath = _joinWorktreePath(worktreePath, path);
    if (fullPath == null) {
      return _untrackedFile(
        path,
        UntrackedEntityKind.unknown,
        UntrackedPreviewState.unavailable,
      );
    }
    final type = _entityType(fullPath);
    if (type == FileSystemEntityType.file) {
      return _loadRegularFile(path, fullPath);
    }
    if (type == FileSystemEntityType.link) {
      return _loadSymbolicLink(path, fullPath);
    }
    return _untrackedFile(
      path,
      UntrackedEntityKind.unknown,
      UntrackedPreviewState.unavailable,
    );
  }

  Future<DiffFile> _loadRegularFile(GitPath path, String fullPath) async {
    const kind = UntrackedEntityKind.regularFile;
    if (!budget.hasContentCapacity) {
      return _untrackedFile(path, kind, UntrackedPreviewState.omitted);
    }

    final retainedLimit = math.min(
      _fileByteLimit,
      math.max(0, budget.remainingBytes - 1),
    );
    if (retainedLimit == 0) {
      return _untrackedFile(path, kind, UntrackedPreviewState.omitted);
    }

    final _RegularBytes bytes;
    try {
      bytes = await _readRegularBytes(fullPath, retainedLimit);
    } on FileSystemException {
      return _untrackedFile(path, kind, UntrackedPreviewState.unavailable);
    } on IOException {
      return _untrackedFile(path, kind, UntrackedPreviewState.unavailable);
    }

    if (_entityType(fullPath) != FileSystemEntityType.file) {
      return _untrackedFile(path, kind, UntrackedPreviewState.unavailable);
    }
    if (bytes.hasNull) {
      return _untrackedFile(path, kind, UntrackedPreviewState.binary);
    }

    final decoded = _decodeRegularPrefix(
      bytes.retained,
      byteTruncated: bytes.byteTruncated,
    );
    if (decoded == null) {
      return _untrackedFile(path, kind, UntrackedPreviewState.binary);
    }

    final preview = _materializeText(decoded);
    return _untrackedFile(
      path,
      kind,
      bytes.byteTruncated || preview.truncated
          ? UntrackedPreviewState.truncatedText
          : UntrackedPreviewState.completeText,
      preview.lines,
    );
  }

  Future<_RegularBytes> _readRegularBytes(
    String fullPath,
    int retainedLimit,
  ) async {
    final handle = await File(fullPath).open();
    try {
      final returned = <int>[];
      final returnLimit = retainedLimit + 1;
      var firstRead = true;
      var hasNull = false;
      while (returned.length < returnLimit) {
        final remaining = returnLimit - returned.length;
        final request = firstRead
            ? math.min(_binaryProbeByteLimit, remaining)
            : math.min(8192, remaining);
        firstRead = false;
        final chunk = await handle.read(request);
        if (chunk.isEmpty) break;

        final retainedStart = math.min(returned.length, retainedLimit);
        returned.addAll(chunk);
        budget.consumeBytes(chunk.length);
        final retainedEnd = math.min(returned.length, retainedLimit);
        for (var i = retainedStart; i < retainedEnd; i++) {
          if (returned[i] == 0) {
            hasNull = true;
            break;
          }
        }
        if (hasNull) break;
      }

      final byteTruncated = returned.length > retainedLimit;
      return _RegularBytes(
        retained: List<int>.unmodifiable(
          returned.take(retainedLimit).toList(growable: false),
        ),
        byteTruncated: byteTruncated,
        hasNull: hasNull,
      );
    } finally {
      await handle.close();
    }
  }

  String? _decodeRegularPrefix(
    List<int> retained, {
    required bool byteTruncated,
  }) {
    try {
      final decoded = utf8.decode(retained);
      return byteTruncated ? _withoutFinalGrapheme(decoded) : decoded;
    } on FormatException {
      if (!byteTruncated) return null;
      final suffixLength = _incompleteUtf8SuffixLength(retained);
      if (suffixLength == 0) return null;
      try {
        final decoded = utf8.decode(
          retained.sublist(0, retained.length - suffixLength),
        );
        return _withoutFinalGrapheme(decoded);
      } on FormatException {
        return null;
      }
    }
  }

  _TextPreview _materializeText(String text) {
    if (text.isEmpty) return const _TextPreview([], truncated: false);

    final lines = <String>[];
    var offset = 0;
    var localCells = 0;
    while (offset < text.length) {
      if (lines.length >= _fileLineLimit || budget.remainingLines == 0) {
        return _TextPreview(lines, truncated: true);
      }
      final remainingCells = math.min(
        _fileCellLimit - localCells,
        budget.remainingCells,
      );
      if (remainingCells <= 0) {
        return _TextPreview(lines, truncated: true);
      }

      final newline = text.indexOf('\n', offset);
      final end = newline < 0 ? text.length : newline;
      final sourceLine = text.substring(offset, end);
      final fitted = _fitByCells(sourceLine, remainingCells);
      if (!fitted.complete && fitted.text.isEmpty) {
        return _TextPreview(lines, truncated: true);
      }

      lines.add(fitted.text);
      budget
        ..consumeLines(1)
        ..consumeCells(fitted.cells);
      localCells += fitted.cells;
      if (!fitted.complete) {
        return _TextPreview(lines, truncated: true);
      }
      if (newline < 0 || newline + 1 == text.length) break;
      offset = newline + 1;
    }
    return _TextPreview(lines, truncated: false);
  }

  Future<DiffFile> _loadSymbolicLink(GitPath path, String fullPath) async {
    const kind = UntrackedEntityKind.symbolicLink;
    if (!budget.hasContentCapacity) {
      return _untrackedFile(path, kind, UntrackedPreviewState.omitted);
    }

    final String target;
    try {
      target = await linkTargetReader(fullPath);
    } on FileSystemException {
      return _untrackedFile(path, kind, UntrackedPreviewState.unavailable);
    } on IOException {
      return _untrackedFile(path, kind, UntrackedPreviewState.unavailable);
    }
    if (target.contains('\uFFFD')) {
      return _untrackedFile(path, kind, UntrackedPreviewState.unavailable);
    }

    final encoded = StringBuffer();
    var localBytes = 0;
    var localCells = 0;
    var acceptedToken = false;
    var truncated = false;
    for (final token in _linkDisplayTokens(target)) {
      final tokenBytes = utf8.encode(token).length;
      final tokenCells = terminalStringWidth(token);
      if (localBytes + tokenBytes > _fileByteLimit ||
          tokenBytes > budget.remainingBytes ||
          localCells + tokenCells > _fileCellLimit ||
          tokenCells > budget.remainingCells) {
        truncated = true;
        break;
      }
      if (!acceptedToken) {
        budget.consumeLines(1);
        acceptedToken = true;
      }
      encoded.write(token);
      localBytes += tokenBytes;
      localCells += tokenCells;
      budget
        ..consumeBytes(tokenBytes)
        ..consumeCells(tokenCells);
    }

    final display = encoded.toString();
    return _untrackedFile(
      path,
      kind,
      truncated
          ? UntrackedPreviewState.truncatedText
          : UntrackedPreviewState.completeText,
      display.isEmpty ? const [] : [display],
    );
  }

  FileSystemEntityType _entityType(String path) {
    try {
      return FileSystemEntity.typeSync(path, followLinks: false);
    } on FileSystemException {
      return FileSystemEntityType.notFound;
    } on IOException {
      return FileSystemEntityType.notFound;
    }
  }

  DiffFile _untrackedFile(
    GitPath path,
    UntrackedEntityKind kind,
    UntrackedPreviewState state, [
    List<String> lines = const [],
  ]) => DiffFile.untracked(
    path: path,
    entityKind: kind,
    previewState: state,
    previewLines: lines,
  );
}

class _PreviewBudget {
  var _bytes = 0;
  var _lines = 0;
  var _cells = 0;

  int get remainingBytes => _workspaceByteLimit - _bytes;
  int get remainingLines => _workspaceLineLimit - _lines;
  int get remainingCells => _workspaceCellLimit - _cells;

  bool get hasContentCapacity =>
      remainingBytes > 0 && remainingLines > 0 && remainingCells > 0;

  void consumeBytes(int count) {
    assert(count >= 0 && count <= remainingBytes);
    _bytes += count;
  }

  void consumeLines(int count) {
    assert(count >= 0 && count <= remainingLines);
    _lines += count;
  }

  void consumeCells(int count) {
    assert(count >= 0 && count <= remainingCells);
    _cells += count;
  }
}

class _RegularBytes {
  const _RegularBytes({
    required this.retained,
    required this.byteTruncated,
    required this.hasNull,
  });

  final List<int> retained;
  final bool byteTruncated;
  final bool hasNull;
}

class _TextPreview {
  const _TextPreview(this.lines, {required this.truncated});

  final List<String> lines;
  final bool truncated;
}

class _FittedText {
  const _FittedText({
    required this.text,
    required this.cells,
    required this.complete,
  });

  final String text;
  final int cells;
  final bool complete;
}

_FittedText _fitByCells(String text, int maxCells) {
  final output = StringBuffer();
  var cells = 0;
  var complete = true;
  for (final cluster in text.characters) {
    final width = terminalCellWidth(cluster);
    if (cells + width > maxCells) {
      complete = false;
      break;
    }
    output.write(cluster);
    cells += width;
  }
  return _FittedText(text: output.toString(), cells: cells, complete: complete);
}

String _withoutFinalGrapheme(String text) {
  final output = StringBuffer();
  String? pending;
  for (final cluster in text.characters) {
    if (pending != null) output.write(pending);
    pending = cluster;
  }
  return output.toString();
}

int _incompleteUtf8SuffixLength(List<int> bytes) {
  if (bytes.isEmpty) return 0;
  final firstCandidate = math.max(0, bytes.length - 4);
  for (var index = bytes.length - 1; index >= firstCandidate; index--) {
    final byte = bytes[index];
    if (_isUtf8Continuation(byte)) continue;
    final expected = _utf8SequenceLength(byte);
    if (expected == null) return 0;
    final actual = bytes.length - index;
    if (actual >= expected) return 0;
    for (var i = index + 1; i < bytes.length; i++) {
      if (!_isUtf8Continuation(bytes[i])) return 0;
    }
    if (!_isValidPartialUtf8Sequence(bytes, index, actual)) return 0;
    return actual;
  }
  return 0;
}

int? _utf8SequenceLength(int leadingByte) {
  if (leadingByte <= 0x7f) return 1;
  if (leadingByte >= 0xc2 && leadingByte <= 0xdf) return 2;
  if (leadingByte >= 0xe0 && leadingByte <= 0xef) return 3;
  if (leadingByte >= 0xf0 && leadingByte <= 0xf4) return 4;
  return null;
}

bool _isUtf8Continuation(int byte) => byte >= 0x80 && byte <= 0xbf;

bool _isValidPartialUtf8Sequence(List<int> bytes, int start, int length) {
  if (length < 2) return true;
  final lead = bytes[start];
  final firstContinuation = bytes[start + 1];
  if (lead == 0xe0 && firstContinuation < 0xa0) return false;
  if (lead == 0xed && firstContinuation > 0x9f) return false;
  if (lead == 0xf0 && firstContinuation < 0x90) return false;
  if (lead == 0xf4 && firstContinuation > 0x8f) return false;
  return true;
}

Iterable<String> _linkDisplayTokens(String target) sync* {
  for (final cluster in target.characters) {
    var containsEscape = false;
    for (final rune in cluster.runes) {
      if (_escapedLinkRune(rune) != null) {
        containsEscape = true;
        break;
      }
    }
    if (containsEscape) {
      for (final rune in cluster.runes) {
        yield _escapedLinkRune(rune) ?? String.fromCharCode(rune);
      }
    } else {
      yield cluster;
    }
  }
}

String? _escapedLinkRune(int rune) => switch (rune) {
  0x5c => r'\\',
  0x0a => r'\n',
  0x0d => r'\r',
  0x09 => r'\t',
  0x1b => r'\e',
  < 0x20 || (>= 0x7f && <= 0x9f) =>
    '\\u{${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}}',
  _ => null,
};

Future<String> _readLinkTarget(String path) => Link(path).target();

GitStageResult _stageResultFromCommand(
  GitCommandResult result, {
  required GitStageOutcome outcome,
  required String patch,
}) => GitStageResult(
  outcome: outcome,
  stdout: GitDiagnosticText.fromBytes(result.stdoutBytes).text,
  stderr: GitDiagnosticText.fromBytes(result.stderrBytes).text,
  patch: patch,
);

GitStageResult _runnerExceptionStageResult({
  required String phase,
  required Object error,
  required GitStageOutcome outcome,
  required String patch,
}) => GitStageResult(
  outcome: outcome,
  stdout: '',
  stderr: '$phase failed: ${GitDiagnosticText.fromObject(error).text}',
  patch: patch,
);

List<int> _pathspecInput(Iterable<GitPath> paths) {
  final bytes = <int>[];
  for (final path in paths) {
    bytes
      ..addAll(path.bytes)
      ..add(0);
  }
  return List<int>.unmodifiable(bytes);
}

List<GitPath> _parseNulPaths(List<int> bytes) {
  if (bytes.isEmpty) return const [];
  if (bytes.last != 0) {
    throw const FormatException('NUL-delimited Git paths require a final NUL.');
  }
  final paths = <GitPath>[];
  var start = 0;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] != 0) continue;
    if (i == start) {
      throw const FormatException('NUL-delimited Git paths cannot be empty.');
    }
    paths.add(GitPath.fromBytes(bytes.sublist(start, i)));
    start = i + 1;
  }
  return List<GitPath>.unmodifiable(paths);
}

abstract interface class GitCommandRunner {
  Future<GitCommandResult> run(List<String> args, {List<int>? stdinBytes});
}

class ProcessGitCommandRunner implements GitCommandRunner {
  const ProcessGitCommandRunner(this.workingDirectory);

  final String workingDirectory;

  @override
  Future<GitCommandResult> run(
    List<String> args, {
    List<int>? stdinBytes,
  }) async {
    final process = await Process.start(
      'git',
      args,
      workingDirectory: workingDirectory,
    );

    final stdoutFuture = _readBytes(process.stdout);
    final stderrFuture = _readBytes(process.stderr);

    if (stdinBytes != null) {
      process.stdin.add(stdinBytes);
    }
    await process.stdin.close();

    final exitCode = await process.exitCode;
    return GitCommandResult(
      exitCode: exitCode,
      stdoutBytes: await stdoutFuture,
      stderrBytes: await stderrFuture,
    );
  }
}

final class GitCommandResult {
  GitCommandResult({
    required this.exitCode,
    required Iterable<int> stdoutBytes,
    required Iterable<int> stderrBytes,
  }) : stdoutBytes = _validatedBytes(stdoutBytes, 'stdoutBytes'),
       stderrBytes = _validatedBytes(stderrBytes, 'stderrBytes');

  final int exitCode;
  final List<int> stdoutBytes;
  final List<int> stderrBytes;
}

enum GitStageOutcome { applied, rejectedUnchanged, failedRefreshRequired }

class GitStageResult {
  const GitStageResult({
    required this.outcome,
    required this.stdout,
    required this.stderr,
    required this.patch,
  });

  final GitStageOutcome outcome;
  final String stdout;
  final String stderr;
  final String patch;
}

class GitPatchException implements Exception {
  const GitPatchException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<List<int>> _readBytes(Stream<List<int>> stream) async {
  final output = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    output.add(chunk);
  }
  return output.takeBytes();
}

List<int> _validatedBytes(Iterable<int> source, String name) {
  final bytes = source.toList(growable: false);
  for (var i = 0; i < bytes.length; i++) {
    final byte = bytes[i];
    if (byte < 0 || byte > 0xff) {
      throw RangeError.range(byte, 0, 0xff, '$name[$i]');
    }
  }
  return List<int>.unmodifiable(bytes);
}

String? _joinWorktreePath(String root, GitPath relativePath) {
  final parts = <String>[];
  for (final component in gitPathComponents(relativePath)) {
    try {
      parts.add(utf8.decode(component));
    } on FormatException {
      return null;
    }
  }
  final buffer = StringBuffer(root);
  for (final part in parts) {
    buffer
      ..write(Platform.pathSeparator)
      ..write(part);
  }
  return buffer.toString();
}
