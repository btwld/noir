// ignore_for_file: public_member_api_docs

import 'git_repository.dart';
import 'models.dart';

enum PatchReviewStatus { unreviewed, staged, skipped, failed }

class PatchReviewController {
  PatchReviewController(this.diff);

  DiffSet diff;
  int selectedFileIndex = 0;
  int selectedSectionIndex = 0;

  final Set<String> _staged = <String>{};
  final Set<String> _skipped = <String>{};
  final Set<String> _failed = <String>{};

  bool get hasFiles => diff.files.isNotEmpty;

  DiffFile get currentFile => diff.files[selectedFileIndex];

  DiffSection? get currentSection {
    if (!hasFiles || currentFile.contentStageUnits.isEmpty) return null;
    return currentFile.contentStageUnits[selectedSectionIndex];
  }

  DiffHunk? get currentHunk {
    final section = currentSection;
    if (section == null) return null;
    return _hunkForSection(currentFile, section);
  }

  WholeFileChange? get currentWholeFileChange =>
      hasFiles ? currentFile.wholeFileStageUnit : null;

  int get selectedHunkIndex {
    final hunk = currentHunk;
    if (hunk == null) return 0;
    return currentFile.hunks.indexOf(hunk);
  }

  int get stagedCount => _visibleCount(_staged);

  int get skippedCount => _visibleCount(_skipped);

  int get totalReviewCount => diff.stageableReviewTargetCount;

  int get pendingCount {
    final pending = totalReviewCount - stagedCount - skippedCount;
    return pending < 0 ? 0 : pending;
  }

  int stagedCountFor(DiffFile file) =>
      file.reviewTargets.where((target) => _staged.contains(target.id)).length;

  int skippedCountFor(DiffFile file) => file.reviewTargets
      .where((target) => _statusForId(target.id) == PatchReviewStatus.skipped)
      .length;

  int pendingCountFor(DiffFile file) {
    final pending =
        file.reviewTargets.length -
        stagedCountFor(file) -
        skippedCountFor(file);
    return pending < 0 ? 0 : pending;
  }

  void selectFile(int index) {
    if (!hasFiles) return;
    selectedFileIndex = index.clamp(0, diff.files.length - 1);
    selectedSectionIndex = 0;
    _clampSectionSelection();
  }

  void selectSection(int index) {
    if (!hasFiles || currentFile.contentStageUnits.isEmpty) return;
    selectedSectionIndex = index.clamp(
      0,
      currentFile.contentStageUnits.length - 1,
    );
  }

  void selectNextSection() {
    selectSection(selectedSectionIndex + 1);
  }

  void selectPreviousSection() {
    selectSection(selectedSectionIndex - 1);
  }

  PatchReviewStatus statusForTarget(PatchReviewTarget target) =>
      _statusForId(target.id);

  PatchReviewStatus statusForHunk(DiffHunk hunk) =>
      _aggregateStatus(hunk.sections);

  PatchReviewStatus statusForFile(DiffFile file) =>
      _aggregateStatus(file.reviewTargets);

  PatchReviewStatus statusForWholeFile(WholeFileChange change) =>
      _statusForId(change.id);

  void skipCurrentReviewTarget() {
    if (!hasFiles) return;
    final hunk = currentHunk;
    if (hunk != null) {
      skipHunk(hunk);
      return;
    }
    final whole = currentWholeFileChange;
    if (whole != null && currentFile.reviewTargets.contains(whole)) {
      _markSkippedIds([whole.id]);
    }
  }

  void skipHunk(DiffHunk hunk) {
    final file = _fileForHunk(hunk);
    if (file == null || !file.canStageContent) return;
    _markSkippedIds(hunk.sections.map((section) => section.id));
  }

  void recordContentStageOutcome(
    ContentStageSelection selection,
    GitStageOutcome outcome,
  ) {
    final ids = selection.sections.map((section) => section.id);
    switch (outcome) {
      case GitStageOutcome.applied:
        _markStagedIds(ids);
      case GitStageOutcome.rejectedUnchanged:
      case GitStageOutcome.failedRefreshRequired:
        _markFailedIds(ids);
    }
  }

  void recordWholeFileStageOutcome(
    WholeFileChange change,
    GitStageOutcome outcome,
  ) {
    switch (outcome) {
      case GitStageOutcome.applied:
        final file = _fileForWholeFileChange(change);
        _markStagedIds([
          change.id,
          if (file != null)
            for (final target in file.reviewTargets) target.id,
        ]);
      case GitStageOutcome.rejectedUnchanged:
      case GitStageOutcome.failedRefreshRequired:
        _markFailedIds([change.id]);
    }
  }

  ContentStageSelection? currentHunkContentSelection() {
    final hunk = currentHunk;
    if (hunk == null) return null;
    return contentSelectionForHunk(hunk);
  }

  ContentStageSelection? contentSelectionForHunk(DiffHunk hunk) {
    final file = _fileForHunk(hunk);
    if (file == null || !file.canStageContent) return null;
    final unstaged = hunk.sections
        .where((section) => !_staged.contains(section.id))
        .toList(growable: false);
    if (unstaged.isEmpty) return null;
    return ContentStageSelection(file: file, sections: unstaged);
  }

  void refresh(DiffSet next) {
    final countedIds = <String>{
      for (final file in next.files)
        for (final target in file.reviewTargets) target.id,
    };
    final operationIds = <String>{
      for (final file in next.files)
        if (file.wholeFileStageUnit case final whole?) whole.id,
    };
    final targetUniverse = {...countedIds, ...operationIds};
    _staged.retainWhere(targetUniverse.contains);
    _skipped.retainWhere(countedIds.contains);
    _failed.clear();

    diff = next;
    if (!hasFiles) {
      selectedFileIndex = 0;
      selectedSectionIndex = 0;
      return;
    }
    selectedFileIndex = selectedFileIndex.clamp(0, diff.files.length - 1);
    _clampSectionSelection();
  }

  PatchReviewStatus _statusForId(String id) {
    if (_failed.contains(id)) return PatchReviewStatus.failed;
    if (_staged.contains(id)) return PatchReviewStatus.staged;
    if (_skipped.contains(id)) return PatchReviewStatus.skipped;
    return PatchReviewStatus.unreviewed;
  }

  PatchReviewStatus _aggregateStatus(Iterable<PatchReviewTarget> targets) {
    final statuses = targets.map(statusForTarget).toList(growable: false);
    if (statuses.isEmpty) return PatchReviewStatus.unreviewed;
    if (statuses.contains(PatchReviewStatus.failed)) {
      return PatchReviewStatus.failed;
    }
    if (statuses.every((status) => status == PatchReviewStatus.staged)) {
      return PatchReviewStatus.staged;
    }
    if (statuses.contains(PatchReviewStatus.skipped)) {
      return PatchReviewStatus.skipped;
    }
    return PatchReviewStatus.unreviewed;
  }

  void _clampSectionSelection() {
    if (currentFile.contentStageUnits.isEmpty) {
      selectedSectionIndex = 0;
      return;
    }
    selectedSectionIndex = selectedSectionIndex.clamp(
      0,
      currentFile.contentStageUnits.length - 1,
    );
  }

  DiffHunk _hunkForSection(DiffFile file, DiffSection section) =>
      file.hunks.firstWhere(
        (hunk) => hunk.sections.any((item) => identical(item, section)),
      );

  DiffFile? _fileForHunk(DiffHunk hunk) {
    for (final file in diff.files) {
      if (file.hunks.any((candidate) => identical(candidate, hunk))) {
        return file;
      }
    }
    return null;
  }

  DiffFile? _fileForWholeFileChange(WholeFileChange change) {
    for (final file in diff.files) {
      if (file.wholeFileStageUnit?.id == change.id) return file;
    }
    return null;
  }

  int _visibleCount(Set<String> ids) {
    var count = 0;
    for (final file in diff.files) {
      for (final target in file.reviewTargets) {
        if (ids.contains(target.id)) count++;
      }
    }
    return count;
  }

  void _markSkippedIds(Iterable<String> ids) {
    final countedIds = <String>{
      for (final file in diff.files)
        for (final target in file.reviewTargets) target.id,
    };
    for (final id in ids) {
      if (!countedIds.contains(id) || _staged.contains(id)) continue;
      _failed.remove(id);
      _skipped.add(id);
    }
  }

  void _markStagedIds(Iterable<String> ids) {
    for (final id in ids) {
      _failed.remove(id);
      _skipped.remove(id);
      _staged.add(id);
    }
  }

  void _markFailedIds(Iterable<String> ids) {
    for (final id in ids) {
      _staged.remove(id);
      _skipped.remove(id);
      _failed.add(id);
    }
  }
}
