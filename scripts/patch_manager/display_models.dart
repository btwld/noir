// ignore_for_file: public_member_api_docs

import 'package:noir/noir.dart' show Color;
import 'git_path.dart';
import 'models.dart';
import 'patch_theme.dart';
import 'review_controller.dart';

enum PatchLayoutMode {
  wide,
  medium;

  static const mediumBreakpoint = 116;

  static PatchLayoutMode fromWidth(int width) =>
      width < mediumBreakpoint ? PatchLayoutMode.medium : PatchLayoutMode.wide;

  bool get isMedium => this == PatchLayoutMode.medium;
}

enum PatchActionKind { skip, stage, refresh, staged }

class PatchActionItem {
  const PatchActionItem({
    required this.kind,
    required this.label,
    this.selected = false,
    this.primary = false,
    this.enabled = true,
    this.color,
  });

  final PatchActionKind kind;
  final String label;
  final bool selected;
  final bool primary;
  final bool enabled;
  final Color? color;
}

class PatchActionSet {
  const PatchActionSet._({required this.items});

  factory PatchActionSet.header({
    required bool stagesContent,
    required bool stagingEnabled,
  }) => PatchActionSet._(
    items: [
      PatchActionItem(
        kind: PatchActionKind.stage,
        label: stagesContent ? 'stage hunk' : 'stage file',
        primary: true,
        enabled: stagingEnabled,
        color: PatchTheme.cyan,
      ),
      const PatchActionItem(
        kind: PatchActionKind.skip,
        label: 'skip',
        color: PatchTheme.amber,
      ),
    ],
  );

  /// Actions for one review target. [stagesContent] selects the stage label
  /// exactly as [PatchActionSet.header] does: `stage hunk` for content
  /// targets, `stage file` for whole-file targets.
  factory PatchActionSet.forTarget(
    PatchReviewStatus status, {
    required bool stagesContent,
    bool stagingEnabled = true,
  }) {
    final stageLabel = stagesContent ? 'stage hunk' : 'stage file';
    return switch (status) {
      PatchReviewStatus.unreviewed => PatchActionSet._(
        items: _decisionItems(
          stageLabel: stageLabel,
          stagingEnabled: stagingEnabled,
        ),
      ),
      PatchReviewStatus.staged => const PatchActionSet._(
        items: [
          PatchActionItem(
            kind: PatchActionKind.staged,
            label: 'staged',
            selected: true,
            enabled: false,
            color: PatchTheme.cyan,
          ),
        ],
      ),
      PatchReviewStatus.skipped => PatchActionSet._(
        items: _decisionItems(
          stageLabel: stageLabel,
          stagingEnabled: stagingEnabled,
          skipSelected: true,
        ),
      ),
      PatchReviewStatus.failed => PatchActionSet._(
        items: [
          PatchActionItem(
            kind: PatchActionKind.stage,
            label: stageLabel,
            primary: true,
            enabled: stagingEnabled,
            color: PatchTheme.cyan,
          ),
          const PatchActionItem(
            kind: PatchActionKind.refresh,
            label: 'failed',
            selected: true,
            enabled: false,
            color: PatchTheme.red,
          ),
        ],
      ),
    };
  }

  static List<PatchActionItem> _decisionItems({
    required String stageLabel,
    required bool stagingEnabled,
    bool skipSelected = false,
  }) => [
    PatchActionItem(
      kind: PatchActionKind.stage,
      label: stageLabel,
      primary: true,
      enabled: stagingEnabled,
      color: PatchTheme.cyan,
    ),
    PatchActionItem(
      kind: PatchActionKind.skip,
      label: 'skip',
      selected: skipSelected,
      color: PatchTheme.amber,
    ),
  ];

  final List<PatchActionItem> items;

  List<String> get labels => [for (final item in items) item.label];
}

class WholeFileChangeDisplay {
  const WholeFileChangeDisplay._({
    required this.title,
    required this.description,
  });

  factory WholeFileChangeDisplay.fromChange(WholeFileChange change) =>
      switch (change.reason) {
        WholeFileChangeReason.modified => const WholeFileChangeDisplay._(
          title: 'Whole-file content change',
          description: 'Stage every working-tree change for this file.',
        ),
        WholeFileChangeReason.contentAndMode => const WholeFileChangeDisplay._(
          title: 'Content and mode change',
          description: 'Stage the file content and executable mode together.',
        ),
        WholeFileChangeReason.modeOnly => const WholeFileChangeDisplay._(
          title: 'File mode change',
          description: 'Stage the executable-mode change for this file.',
        ),
        WholeFileChangeReason.binary => const WholeFileChangeDisplay._(
          title: 'Binary file change',
          description: 'Stage the complete binary file change.',
        ),
        WholeFileChangeReason.unsupportedTextEncoding =>
          const WholeFileChangeDisplay._(
            title: 'Unsupported text encoding',
            description: 'Stage the complete file without a text patch.',
          ),
        WholeFileChangeReason.added => const WholeFileChangeDisplay._(
          title: 'Added file',
          description: 'Stage the complete added file.',
        ),
        WholeFileChangeReason.deleted => const WholeFileChangeDisplay._(
          title: 'Deleted file',
          description: 'Stage deletion of this file.',
        ),
        WholeFileChangeReason.renamed => const WholeFileChangeDisplay._(
          title: 'Renamed file',
          description: 'Stage the old and new paths as one file change.',
        ),
        WholeFileChangeReason.copied => const WholeFileChangeDisplay._(
          title: 'Copied file',
          description: 'Stage the copied file at its new path.',
        ),
        WholeFileChangeReason.typeChanged => const WholeFileChangeDisplay._(
          title: 'File type change',
          description: 'Stage the complete file-type change.',
        ),
        WholeFileChangeReason.untracked => const WholeFileChangeDisplay._(
          title: 'Untracked file',
          description: 'Stage this untracked path as a complete file.',
        ),
      };

  final String title;
  final String description;
}

class PatchFileRowModel {
  const PatchFileRowModel({
    required this.basename,
    required this.fileStatusLetter,
    required this.fileKindGlyph,
    required this.fileKindColor,
    required this.additionCount,
    required this.deletionCount,
    required this.fallbackMetadata,
    required this.parentHint,
  });

  factory PatchFileRowModel.fromFile(
    DiffFile file, {
    required PatchReviewStatus status,
    required PatchLayoutMode mode,
  }) {
    final compact = mode.isMedium;
    final maxBasenameWidth = compact ? 24 : 40;
    final presentation = GitPathPresentation.asciiSafe(file.pathIdentity);
    final basename = presentation.truncateBasename(maxBasenameWidth);
    final parent = presentation.parentHint;
    final fileStatusLetter = _fileStatusGlyph(file, status);
    final fileKind = _fileKind(file);

    final int? additionCount;
    final int? deletionCount;
    final String? fallbackMetadata;
    final previewState = file.untrackedPreviewState;
    if (previewState == UntrackedPreviewState.binary) {
      additionCount = null;
      deletionCount = null;
      fallbackMetadata = 'untracked binary';
    } else if (previewState == UntrackedPreviewState.unavailable) {
      additionCount = null;
      deletionCount = null;
      fallbackMetadata = compact ? 'unavailable' : 'preview unavailable';
    } else if (previewState == UntrackedPreviewState.omitted) {
      additionCount = null;
      deletionCount = null;
      fallbackMetadata = compact ? 'omitted' : 'preview omitted';
    } else if (previewState == UntrackedPreviewState.truncatedText) {
      additionCount = null;
      deletionCount = null;
      fallbackMetadata = file.isSymbolicLink
          ? (compact ? 'link preview' : 'link preview truncated')
          : (compact
                ? 'preview +${file.additionCount}'
                : 'preview ${file.additionCount} '
                      '${file.additionCount == 1 ? 'line' : 'lines'}');
    } else if (file.isSymbolicLink) {
      additionCount = null;
      deletionCount = null;
      fallbackMetadata = compact ? 'link' : 'link target';
    } else if (file.isBinary) {
      additionCount = null;
      deletionCount = null;
      fallbackMetadata = compact ? 'binary' : 'binary file';
    } else if (!file.canStageContent && !file.canStageWholeFile) {
      additionCount = null;
      deletionCount = null;
      fallbackMetadata = compact ? 'preview' : 'preview only';
    } else {
      additionCount = file.additionCount;
      deletionCount = file.deletionCount;
      fallbackMetadata = null;
    }

    return PatchFileRowModel(
      basename: basename,
      fileStatusLetter: fileStatusLetter,
      fileKindGlyph: fileKind.glyph,
      fileKindColor: fileKind.color,
      additionCount: additionCount,
      deletionCount: deletionCount,
      fallbackMetadata: fallbackMetadata,
      parentHint: parent,
    );
  }

  /// Short basename of the file, already truncated to fit the current layout.
  final String basename;

  /// Single-letter file-status glyph (M/A/D/R/B/!/U/S/K) — derived from both
  /// the diff status and the review status.
  final String fileStatusLetter;

  /// One-cell file-kind glyph shown before the basename.
  final String fileKindGlyph;

  /// Color paired with [fileKindGlyph].
  final Color fileKindColor;

  /// Added-line total shown as a right-aligned green cell when available.
  final int? additionCount;

  /// Removed-line total shown as a right-aligned red cell when available.
  final int? deletionCount;

  /// Compact right-side fallback for rows without text line totals.
  final String? fallbackMetadata;

  /// Parent directory hint for files in nested folders (empty for top-level
  /// files). Widgets may render this beneath the row or skip it in 1-line
  /// layouts.
  final String parentHint;

  bool get hasLineTotals => additionCount != null && deletionCount != null;
}

class PatchWorkstationHeader {
  const PatchWorkstationHeader._({
    required this.title,
    required this.subtitle,
    required this.progressBar,
    required this.metrics,
  });

  factory PatchWorkstationHeader.fromController(
    PatchReviewController controller,
  ) {
    final total = controller.totalReviewCount;
    final completed = controller.stagedCount + controller.skippedCount;
    return PatchWorkstationHeader._(
      title: 'Patch Manager',
      subtitle: 'stage or skip unstaged changes intentionally',
      progressBar: _progressBar(completed, total),
      metrics:
          '${controller.diff.files.length} files  '
          '${controller.diff.untrackedCount} untracked  '
          'staged ${controller.stagedCount}/$total  '
          'skipped ${controller.skippedCount}  '
          'pending ${controller.pendingCount}',
    );
  }

  final String title;
  final String subtitle;
  final String progressBar;
  final String metrics;
}

class PatchFooterText {
  const PatchFooterText._(this.text);

  factory PatchFooterText.fromStatus({
    required String status,
    required bool busy,
    required PatchLayoutMode mode,
  }) {
    final core = busy ? 'Working... $status' : status;
    final text = mode.isMedium
        ? '$core  |  More: f file | r refresh | Tab panes | q quit'
        : core;
    return PatchFooterText._(text);
  }

  final String text;
}

String patchStatusLabel(PatchReviewStatus status) => switch (status) {
  PatchReviewStatus.unreviewed => 'pending',
  PatchReviewStatus.staged => 'staged',
  PatchReviewStatus.skipped => 'skipped',
  PatchReviewStatus.failed => 'failed',
};

String _fileStatusGlyph(DiffFile file, PatchReviewStatus status) =>
    switch (status) {
      PatchReviewStatus.staged => 'S',
      PatchReviewStatus.skipped => 'K',
      PatchReviewStatus.failed => '!',
      PatchReviewStatus.unreviewed =>
        file.isUntracked
            ? 'U'
            : (!file.canStageContent && !file.canStageWholeFile
                  ? '!'
                  : _statusLetter(file.changeKind)),
    };

String _statusLetter(DiffChangeKind status) => switch (status) {
  DiffChangeKind.modified => 'M',
  DiffChangeKind.added => 'A',
  DiffChangeKind.deleted => 'D',
  DiffChangeKind.renamed => 'R',
  DiffChangeKind.copied => 'C',
  DiffChangeKind.typeChanged => 'T',
};

({String glyph, Color color}) _fileKind(DiffFile file) {
  if (file.isSymbolicLink) return (glyph: 'L', color: PatchTheme.green);
  if (file.isBinary) return (glyph: 'B', color: PatchTheme.amber);
  if (file.hasUnsupportedTextEncoding) {
    return (glyph: '!', color: PatchTheme.red);
  }

  final path = GitPathPresentation.asciiSafe(
    file.pathIdentity,
  ).full.toLowerCase();
  if (path.endsWith('.dart')) return (glyph: 'D', color: PatchTheme.cyan);
  if (path.endsWith('.tsx')) return (glyph: 'X', color: PatchTheme.cyan);
  if (path.endsWith('.ts')) return (glyph: 'T', color: PatchTheme.cyan);
  if (path.endsWith('.jsx') || path.endsWith('.js')) {
    return (glyph: 'J', color: PatchTheme.amber);
  }
  if (path.endsWith('.md') || path.endsWith('.txt')) {
    return (glyph: 'T', color: PatchTheme.green);
  }
  if (path.endsWith('.json') ||
      path.endsWith('.yaml') ||
      path.endsWith('.yml') ||
      path.endsWith('.toml')) {
    return (glyph: 'C', color: PatchTheme.amber);
  }
  if (file.isUntracked || file.changeKind == DiffChangeKind.added) {
    return (glyph: 'N', color: PatchTheme.green);
  }
  return (glyph: 'F', color: PatchTheme.subtitle);
}

String _progressBar(int completed, int total) {
  const width = 24;
  final filled = total <= 0 ? 0 : ((completed / total) * width).round();
  return '[${List.filled(filled, '#').join()}'
      '${List.filled(width - filled, '-').join()}]';
}
