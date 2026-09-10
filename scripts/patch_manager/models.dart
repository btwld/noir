// ignore_for_file: public_member_api_docs

import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'git_path.dart';

enum DiffChangeKind { modified, added, deleted, renamed, copied, typeChanged }

enum DiffPayloadKind { text, binary, unsupportedTextEncoding }

enum DiffLineType { context, addition, deletion, noNewlineMarker }

enum UntrackedEntityKind { regularFile, symbolicLink, unknown }

enum UntrackedPreviewState {
  completeText,
  truncatedText,
  binary,
  unavailable,
  omitted,
}

enum WholeFileChangeReason {
  modified,
  contentAndMode,
  modeOnly,
  binary,
  unsupportedTextEncoding,
  added,
  deleted,
  renamed,
  copied,
  typeChanged,
  untracked,
}

sealed class PatchReviewTarget {
  const PatchReviewTarget();

  String get id;
}

final class ContentPatchHeader {
  const ContentPatchHeader({
    required this.diffGitLine,
    required this.oldFileLine,
    required this.newFileLine,
  });

  final String diffGitLine;
  final String oldFileLine;
  final String newFileLine;
}

class GitDiffMetadata {
  const GitDiffMetadata({
    required this.oldMode,
    required this.newMode,
    required this.oldObjectId,
    required this.newObjectId,
    required this.status,
    required this.score,
  });

  final String oldMode;
  final String newMode;
  final String oldObjectId;
  final String newObjectId;
  final String status;
  final int? score;
}

final class ContentStageSelection {
  factory ContentStageSelection({
    required DiffFile file,
    required Iterable<DiffSection> sections,
  }) {
    final copied = List<DiffSection>.of(sections);
    if (copied.isEmpty) {
      throw ArgumentError.value(
        copied,
        'sections',
        'A content staging selection cannot be empty.',
      );
    }

    final canonicalById = <String, DiffSection>{
      for (final section in file.contentStageUnits) section.id: section,
    };
    final selectedIds = <String>{};
    for (final section in copied) {
      if (!selectedIds.add(section.id)) {
        throw ArgumentError.value(
          copied,
          'sections',
          'A content staging selection cannot contain duplicates.',
        );
      }
      final canonical = canonicalById[section.id];
      if (canonical == null || !identical(canonical, section)) {
        throw ArgumentError.value(
          section,
          'sections',
          'Every section must be the canonical instance from the file.',
        );
      }
    }

    final normalized = List<DiffSection>.unmodifiable([
      for (final section in file.contentStageUnits)
        if (selectedIds.contains(section.id)) section,
    ]);
    return ContentStageSelection._(file: file, sections: normalized);
  }

  const ContentStageSelection._({required this.file, required this.sections});

  final DiffFile file;
  final List<DiffSection> sections;
}

final class WholeFileChange extends PatchReviewTarget {
  factory WholeFileChange({
    required String id,
    required Iterable<GitPath> pathspecs,
    required WholeFileChangeReason reason,
  }) {
    final copied = List<GitPath>.of(pathspecs);
    if (copied.isEmpty) {
      throw ArgumentError.value(
        copied,
        'pathspecs',
        'A whole-file change requires at least one path.',
      );
    }
    final identities = <GitPath>{};
    for (final path in copied) {
      if (!identities.add(path)) {
        throw ArgumentError.value(
          copied,
          'pathspecs',
          'A whole-file change cannot contain duplicate path identities.',
        );
      }
    }
    final frozen = List<GitPath>.unmodifiable(copied);
    final expected = canonicalId(reason: reason, pathspecs: frozen);
    if (id != expected) {
      throw ArgumentError.value(
        id,
        'id',
        'Whole-file ID must equal the canonical reason/path identity.',
      );
    }
    return WholeFileChange._(id: id, pathspecs: frozen, reason: reason);
  }

  const WholeFileChange._({
    required this.id,
    required this.pathspecs,
    required this.reason,
  });

  @override
  final String id;
  final List<GitPath> pathspecs;
  final WholeFileChangeReason reason;

  static String canonicalId({
    required WholeFileChangeReason reason,
    required Iterable<GitPath> pathspecs,
  }) =>
      'whole:${reason.name}:'
      '${pathspecs.map((path) => path.identityKey).join(':')}';
}

class DiffSet {
  const DiffSet(this.files);

  final List<DiffFile> files;

  bool get isEmpty => files.isEmpty;

  int get stageableReviewTargetCount =>
      files.fold(0, (count, file) => count + file.reviewTargets.length);

  int get untrackedCount => files.where((file) => file.isUntracked).length;
}

class DiffFile {
  factory DiffFile({
    required GitPath? oldPath,
    required GitPath? newPath,
    required DiffChangeKind changeKind,
    required DiffPayloadKind payloadKind,
    required List<String> headerLines,
    required List<DiffHunk> hunks,
    required GitDiffMetadata? rawMetadata,
    UntrackedEntityKind? untrackedEntityKind,
    UntrackedPreviewState? untrackedPreviewState,
    List<String> untrackedPreviewLines = const [],
    ContentPatchHeader? contentPatchHeader,
  }) {
    if (oldPath == null && newPath == null) {
      throw ArgumentError('A diff file must have an old or new Git path.');
    }
    if ((untrackedEntityKind == null) != (untrackedPreviewState == null)) {
      throw ArgumentError(
        'Untracked entity kind and preview state must be set together.',
      );
    }
    if ((untrackedEntityKind == null) != (rawMetadata != null)) {
      throw ArgumentError(
        'Tracked files require raw metadata; untracked files cannot have it.',
      );
    }
    if (untrackedEntityKind == null && untrackedPreviewLines.isNotEmpty) {
      throw ArgumentError(
        'Only untracked files may retain untracked preview lines.',
      );
    }
    final immutableHeaders = List<String>.unmodifiable(headerLines);
    final immutableHunks = List<DiffHunk>.unmodifiable(hunks);
    final immutableSections = List<DiffSection>.unmodifiable([
      for (final hunk in immutableHunks) ...hunk.sections,
    ]);
    final immutablePreview = List<String>.unmodifiable(untrackedPreviewLines);
    final wholeFileStageUnit = _deriveWholeFileChange(
      oldPath: oldPath,
      newPath: newPath,
      changeKind: changeKind,
      payloadKind: payloadKind,
      rawMetadata: rawMetadata,
      isUntracked: untrackedEntityKind != null,
      hasContent: immutableSections.isNotEmpty,
    );
    final samePath = oldPath != null && newPath != null && oldPath == newPath;
    final canStageContent =
        untrackedEntityKind == null &&
        samePath &&
        changeKind == DiffChangeKind.modified &&
        payloadKind == DiffPayloadKind.text &&
        contentPatchHeader != null &&
        immutableSections.isNotEmpty;
    final contentStageUnits = List<DiffSection>.unmodifiable(
      canStageContent ? immutableSections : const <DiffSection>[],
    );
    final reviewTargets = List<PatchReviewTarget>.unmodifiable(
      canStageContent
          ? contentStageUnits
          : <PatchReviewTarget>[wholeFileStageUnit],
    );
    _requireUniqueTargetIds(reviewTargets);
    return DiffFile._(
      oldPath: oldPath,
      newPath: newPath,
      changeKind: changeKind,
      payloadKind: payloadKind,
      headerLines: immutableHeaders,
      hunks: immutableHunks,
      sections: immutableSections,
      rawMetadata: rawMetadata,
      untrackedEntityKind: untrackedEntityKind,
      untrackedPreviewState: untrackedPreviewState,
      untrackedPreviewLines: immutablePreview,
      contentPatchHeader: contentPatchHeader,
      contentStageUnits: contentStageUnits,
      wholeFileStageUnit: wholeFileStageUnit,
      reviewTargets: reviewTargets,
    );
  }

  const DiffFile._({
    required this.oldPath,
    required this.newPath,
    required this.changeKind,
    required this.payloadKind,
    required this.headerLines,
    required this.hunks,
    required this.sections,
    required this.rawMetadata,
    required this.untrackedEntityKind,
    required this.untrackedPreviewState,
    required this.untrackedPreviewLines,
    required this.contentPatchHeader,
    required this.contentStageUnits,
    required this.wholeFileStageUnit,
    required this.reviewTargets,
  });

  factory DiffFile.untracked({
    required GitPath path,
    required UntrackedEntityKind entityKind,
    required UntrackedPreviewState previewState,
    List<String> previewLines = const [],
  }) {
    assert(
      previewLines.isEmpty ||
          previewState == UntrackedPreviewState.completeText ||
          previewState == UntrackedPreviewState.truncatedText,
      'Only text previews may contain preview lines.',
    );
    final lines = List<String>.unmodifiable(previewLines);
    return DiffFile(
      oldPath: null,
      newPath: path,
      changeKind: DiffChangeKind.added,
      payloadKind: previewState == UntrackedPreviewState.binary
          ? DiffPayloadKind.binary
          : DiffPayloadKind.text,
      headerLines: const [],
      hunks: const [],
      rawMetadata: null,
      untrackedEntityKind: entityKind,
      untrackedPreviewState: previewState,
      untrackedPreviewLines: lines,
    );
  }

  final GitPath? oldPath;
  final GitPath? newPath;
  final DiffChangeKind changeKind;
  final DiffPayloadKind payloadKind;
  final List<String> headerLines;
  final List<DiffHunk> hunks;
  final List<DiffSection> sections;
  final GitDiffMetadata? rawMetadata;
  final UntrackedEntityKind? untrackedEntityKind;
  final UntrackedPreviewState? untrackedPreviewState;
  final List<String> untrackedPreviewLines;
  final ContentPatchHeader? contentPatchHeader;
  final List<DiffSection> contentStageUnits;
  final WholeFileChange? wholeFileStageUnit;
  final List<PatchReviewTarget> reviewTargets;

  GitPath get pathIdentity => newPath ?? oldPath!;

  bool get isUntracked => untrackedEntityKind != null;

  bool get isBinary =>
      payloadKind == DiffPayloadKind.binary ||
      untrackedPreviewState == UntrackedPreviewState.binary;

  bool get hasUnsupportedTextEncoding =>
      payloadKind == DiffPayloadKind.unsupportedTextEncoding;

  bool get isPreviewTruncated =>
      untrackedPreviewState == UntrackedPreviewState.truncatedText;

  bool get isSymbolicLink =>
      untrackedEntityKind == UntrackedEntityKind.symbolicLink;

  bool get canStageContent => contentStageUnits.isNotEmpty;

  bool get canStageWholeFile => wholeFileStageUnit != null;

  int get additionCount => isUntracked
      ? untrackedPreviewLines.length
      : hunks.fold(0, (count, hunk) => count + hunk.additionCount);

  int get deletionCount =>
      hunks.fold(0, (count, hunk) => count + hunk.deletionCount);
}

class DiffHunk {
  const DiffHunk({
    required this.id,
    required this.filePath,
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.sectionHeading,
    required this.rawHeader,
    required this.lines,
    required this.sections,
  });

  factory DiffHunk.fromLines({
    required GitPath filePath,
    required int oldStart,
    required int oldCount,
    required int newStart,
    required int newCount,
    required String sectionHeading,
    required String rawHeader,
    required List<DiffLine> lines,
  }) {
    final immutableLines = List<DiffLine>.unmodifiable(lines);
    final hunkId = _hunkId(
      filePath: filePath,
      oldStart: oldStart,
      oldCount: oldCount,
      newStart: newStart,
      newCount: newCount,
      sectionHeading: sectionHeading,
      lines: immutableLines,
    );
    return DiffHunk(
      id: hunkId,
      filePath: filePath,
      oldStart: oldStart,
      oldCount: oldCount,
      newStart: newStart,
      newCount: newCount,
      sectionHeading: sectionHeading,
      rawHeader: rawHeader,
      lines: immutableLines,
      sections: List<DiffSection>.unmodifiable(
        _buildSections(
          filePath: filePath,
          hunkId: hunkId,
          hunkOldStart: oldStart,
          hunkNewStart: newStart,
          hunkSectionHeading: sectionHeading,
          hunkLines: immutableLines,
        ),
      ),
    );
  }

  /// Canonical hunk identity, computed once in [DiffHunk.fromLines].
  final String id;
  final GitPath filePath;
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String sectionHeading;
  final String rawHeader;
  final List<DiffLine> lines;
  final List<DiffSection> sections;

  int get additionCount => lines.where((line) => line.isAddition).length;

  int get deletionCount => lines.where((line) => line.isDeletion).length;
}

final class DiffSection extends PatchReviewTarget {
  const DiffSection({
    required this.filePath,
    required this.hunkId,
    required this.index,
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.hunkOldStart,
    required this.hunkNewStart,
    required this.hunkSectionHeading,
    required this.hunkLines,
    required this.selectedLineIndexes,
    required this.contentHash,
  });

  final GitPath filePath;
  final String hunkId;
  final int index;
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final int hunkOldStart;
  final int hunkNewStart;
  final String hunkSectionHeading;
  final List<DiffLine> hunkLines;
  final Set<int> selectedLineIndexes;
  final String contentHash;

  @override
  String get id => 'content:$hunkId|section:$index|$contentHash';

  Iterable<DiffLine> get selectedLines =>
      selectedLineIndexes.map((index) => hunkLines[index]);

  int get additionCount =>
      selectedLines.where((line) => line.isAddition).length;

  int get deletionCount =>
      selectedLines.where((line) => line.isDeletion).length;
}

class DiffLine {
  const DiffLine({
    required this.type,
    required this.text,
    required this.raw,
    required this.oldLineNumber,
    required this.newLineNumber,
  });

  final DiffLineType type;
  final String text;
  final String raw;
  final int? oldLineNumber;
  final int? newLineNumber;

  bool get isAddition => type == DiffLineType.addition;

  bool get isDeletion => type == DiffLineType.deletion;

  bool get isChange => isAddition || isDeletion;
}

WholeFileChange _deriveWholeFileChange({
  required GitPath? oldPath,
  required GitPath? newPath,
  required DiffChangeKind changeKind,
  required DiffPayloadKind payloadKind,
  required GitDiffMetadata? rawMetadata,
  required bool isUntracked,
  required bool hasContent,
}) {
  final reason = _wholeFileChangeReason(
    changeKind: changeKind,
    payloadKind: payloadKind,
    rawMetadata: rawMetadata,
    isUntracked: isUntracked,
    hasContent: hasContent,
  );
  final paths = switch (reason) {
    WholeFileChangeReason.added || WholeFileChangeReason.copied => [newPath!],
    WholeFileChangeReason.deleted => [oldPath!],
    WholeFileChangeReason.renamed => _deduplicatePaths([oldPath!, newPath!]),
    WholeFileChangeReason.modified ||
    WholeFileChangeReason.contentAndMode ||
    WholeFileChangeReason.modeOnly ||
    WholeFileChangeReason.binary ||
    WholeFileChangeReason.unsupportedTextEncoding ||
    WholeFileChangeReason.typeChanged ||
    WholeFileChangeReason.untracked => [newPath ?? oldPath!],
  };
  final id = WholeFileChange.canonicalId(reason: reason, pathspecs: paths);
  return WholeFileChange(id: id, pathspecs: paths, reason: reason);
}

WholeFileChangeReason _wholeFileChangeReason({
  required DiffChangeKind changeKind,
  required DiffPayloadKind payloadKind,
  required GitDiffMetadata? rawMetadata,
  required bool isUntracked,
  required bool hasContent,
}) {
  if (isUntracked) return WholeFileChangeReason.untracked;
  switch (changeKind) {
    case DiffChangeKind.added:
      return WholeFileChangeReason.added;
    case DiffChangeKind.deleted:
      return WholeFileChangeReason.deleted;
    case DiffChangeKind.renamed:
      return WholeFileChangeReason.renamed;
    case DiffChangeKind.copied:
      return WholeFileChangeReason.copied;
    case DiffChangeKind.typeChanged:
      return WholeFileChangeReason.typeChanged;
    case DiffChangeKind.modified:
      break;
  }
  if (payloadKind == DiffPayloadKind.binary) {
    return WholeFileChangeReason.binary;
  }
  if (payloadKind == DiffPayloadKind.unsupportedTextEncoding) {
    return WholeFileChangeReason.unsupportedTextEncoding;
  }
  final modeChanged =
      rawMetadata != null && rawMetadata.oldMode != rawMetadata.newMode;
  if (modeChanged && hasContent) {
    return WholeFileChangeReason.contentAndMode;
  }
  if (modeChanged) return WholeFileChangeReason.modeOnly;
  return WholeFileChangeReason.modified;
}

List<GitPath> _deduplicatePaths(Iterable<GitPath> paths) {
  final seen = <GitPath>{};
  return [
    for (final path in paths)
      if (seen.add(path)) path,
  ];
}

void _requireUniqueTargetIds(Iterable<PatchReviewTarget> targets) {
  final ids = <String>{};
  for (final target in targets) {
    if (!ids.add(target.id)) {
      throw ArgumentError.value(
        target.id,
        'reviewTargets',
        'A diff file cannot contain duplicate review-target IDs.',
      );
    }
  }
}

List<DiffSection> _buildSections({
  required GitPath filePath,
  required String hunkId,
  required int hunkOldStart,
  required int hunkNewStart,
  required String hunkSectionHeading,
  required List<DiffLine> hunkLines,
}) {
  final sections = <DiffSection>[];
  final selected = <int>{};

  void flush() {
    if (selected.isEmpty) return;
    sections.add(
      _sectionFromRange(
        filePath: filePath,
        hunkId: hunkId,
        index: sections.length,
        hunkOldStart: hunkOldStart,
        hunkNewStart: hunkNewStart,
        hunkSectionHeading: hunkSectionHeading,
        hunkLines: hunkLines,
        selectedLineIndexes: selected,
      ),
    );
    selected.clear();
  }

  for (var i = 0; i < hunkLines.length; i++) {
    if (hunkLines[i].isChange) {
      selected.add(i);
    } else {
      flush();
    }
  }
  flush();

  return sections;
}

DiffSection _sectionFromRange({
  required GitPath filePath,
  required String hunkId,
  required int index,
  required int hunkOldStart,
  required int hunkNewStart,
  required String hunkSectionHeading,
  required List<DiffLine> hunkLines,
  required Set<int> selectedLineIndexes,
}) {
  final selectedLines = selectedLineIndexes.map((i) => hunkLines[i]).toList();
  final firstSelectedIndex = selectedLineIndexes.toList()..sort();
  final firstOldLine = selectedLines
      .map((line) => line.oldLineNumber)
      .whereType<int>()
      .firstOrNull;
  final firstNewLine = selectedLines
      .map((line) => line.newLineNumber)
      .whereType<int>()
      .firstOrNull;
  final previousOldLine = _previousOldLine(
    hunkLines,
    firstSelectedIndex.isEmpty ? 0 : firstSelectedIndex.first,
  );
  final oldCount = selectedLines.where((line) => line.isDeletion).length;
  final newCount = selectedLines.where((line) => line.isAddition).length;
  final hashInput = selectedLines.map((line) => line.raw).join('\n');

  return DiffSection(
    filePath: filePath,
    hunkId: hunkId,
    index: index,
    oldStart: firstOldLine ?? previousOldLine ?? hunkOldStart,
    oldCount: oldCount,
    newStart: firstNewLine ?? firstOldLine ?? hunkNewStart,
    newCount: newCount,
    hunkOldStart: hunkOldStart,
    hunkNewStart: hunkNewStart,
    hunkSectionHeading: hunkSectionHeading,
    hunkLines: hunkLines,
    selectedLineIndexes: Set<int>.unmodifiable(selectedLineIndexes),
    contentHash: _shortHash(hashInput),
  );
}

int? _previousOldLine(List<DiffLine> lines, int beforeIndex) {
  for (var i = beforeIndex - 1; i >= 0; i--) {
    final oldLine = lines[i].oldLineNumber;
    if (oldLine != null) return oldLine;
  }
  return null;
}

String _hunkId({
  required GitPath filePath,
  required int oldStart,
  required int oldCount,
  required int newStart,
  required int newCount,
  required String sectionHeading,
  required List<DiffLine> lines,
}) {
  final hash = _shortHash(lines.map((line) => line.raw).join('\n'));
  return '${filePath.identityKey}|$oldStart,$oldCount|'
      '$newStart,$newCount|$sectionHeading|$hash';
}

String _shortHash(String input) =>
    sha1.convert(utf8.encode(input)).toString().substring(0, 12);
