// ignore_for_file: public_member_api_docs

import 'dart:collection';

import 'models.dart';

class PatchGenerator {
  String buildContentPatch(ContentStageSelection selection) {
    final file = selection.file;
    final header = file.contentPatchHeader;
    if (header == null) {
      throw StateError('Content staging requires a canonical content header.');
    }
    final buffer = StringBuffer()
      ..writeln(header.diffGitLine)
      ..writeln(header.oldFileLine)
      ..writeln(header.newFileLine);
    final byHunk = <String, List<DiffSection>>{};
    for (final section in selection.sections) {
      byHunk.putIfAbsent(section.hunkId, () => []).add(section);
    }
    var selectedDeltaBefore = 0;
    for (final hunk in file.hunks) {
      final sections = byHunk[hunk.id];
      if (sections == null) continue;
      final encoded = _buildSectionHunk(sections, selectedDeltaBefore);
      buffer.write(encoded.patch);
      selectedDeltaBefore = encoded.selectedDeltaAfter;
    }
    return buffer.toString();
  }

  ({String patch, int selectedDeltaAfter}) _buildSectionHunk(
    List<DiffSection> sections,
    int selectedDeltaBefore,
  ) {
    final first = sections.first;
    final selected = <int>{
      for (final section in sections) ...section.selectedLineIndexes,
    };
    final selectedPositions = selected.toList()..sort();
    final firstSelected = selectedPositions.first;
    final lastSelected = selectedPositions.last;
    final start = _contextStart(first.hunkLines, selected, firstSelected);
    final end = _contextEnd(first.hunkLines, selected, lastSelected);

    final rows = <_PatchRow>[];
    for (var i = start; i <= end; i++) {
      final line = first.hunkLines[i];
      if (line.type == DiffLineType.noNewlineMarker) {
        if (rows.isNotEmpty) {
          rows.add(_PatchRow(raw: line.raw, oldLineNumber: null));
        }
        continue;
      }

      if (line.isAddition && !selected.contains(i)) {
        continue;
      }

      if (line.isDeletion && !selected.contains(i)) {
        rows.add(
          _PatchRow(raw: ' ${line.text}', oldLineNumber: line.oldLineNumber),
        );
        continue;
      }

      rows.add(_PatchRow(raw: line.raw, oldLineNumber: line.oldLineNumber));
    }

    final oldStart =
        rows.map((row) => row.oldLineNumber).whereType<int>().firstOrNull ??
        first.hunkOldStart;
    final oldCount = rows.where((row) => _countsAsOld(row.raw)).length;
    final newCount = rows.where((row) => _countsAsNew(row.raw)).length;
    final oldBefore = oldCount == 0 ? oldStart : oldStart - 1;
    final newBefore = oldBefore + selectedDeltaBefore;
    final newStart = newCount == 0 ? newBefore : newBefore + 1;
    final heading = first.hunkSectionHeading.isEmpty
        ? ''
        : ' ${first.hunkSectionHeading}';

    final buffer = StringBuffer()
      ..writeln('@@ -$oldStart,$oldCount +$newStart,$newCount @@$heading');
    for (final row in rows) {
      buffer.writeln(row.raw);
    }
    return (
      patch: buffer.toString(),
      selectedDeltaAfter: selectedDeltaBefore + newCount - oldCount,
    );
  }

  int _contextStart(
    List<DiffLine> lines,
    Set<int> selected,
    int selectedIndex,
  ) {
    var context = 0;
    for (var i = selectedIndex - 1; i >= 0; i--) {
      if (_isContextAfterSelection(lines[i], selected.contains(i))) {
        context++;
      }
      if (context == 3) return i;
    }
    return 0;
  }

  int _contextEnd(List<DiffLine> lines, Set<int> selected, int selectedIndex) {
    var context = 0;
    for (var i = selectedIndex + 1; i < lines.length; i++) {
      if (_isContextAfterSelection(lines[i], selected.contains(i))) {
        context++;
      }
      if (context == 3) return i;
    }
    return lines.length - 1;
  }

  bool _countsAsOld(String raw) =>
      raw.startsWith(' ') || raw.startsWith('-') || raw.isEmpty;

  bool _countsAsNew(String raw) =>
      raw.startsWith(' ') || raw.startsWith('+') || raw.isEmpty;

  bool _isContextAfterSelection(DiffLine line, bool selected) {
    if (line.type == DiffLineType.context) return true;
    return line.isDeletion && !selected;
  }
}

class _PatchRow {
  const _PatchRow({required this.raw, required this.oldLineNumber});

  final String raw;
  final int? oldLineNumber;
}
