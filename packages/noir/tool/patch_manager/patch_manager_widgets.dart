// ignore_for_file: public_member_api_docs

import 'dart:math' as math;

import 'package:noir/noir.dart'
    hide DiffFile, DiffHunk, DiffLine, UnifiedDiffParser;
import 'package:noir/noir.dart' as noir_diff;
import 'display_models.dart';
import 'git_path.dart';
import 'models.dart';
import 'patch_theme.dart';
import 'review_controller.dart';

class PatchHeader extends StatelessWidget {
  const PatchHeader({
    required this.controller,
    required this.mode,
    required this.stagingEnabled,
    this.onSkip,
    this.onStageContent,
    this.onStageWholeFile,
  });

  final PatchReviewController controller;
  final PatchLayoutMode mode;
  final bool stagingEnabled;
  final VoidCallback? onSkip;
  final VoidCallback? onStageContent;
  final VoidCallback? onStageWholeFile;

  @override
  Widget build(BuildContext context) {
    final model = PatchWorkstationHeader.fromController(controller);
    final stagesContent =
        controller.hasFiles && controller.currentFile.canStageContent;
    final actions = PatchActionSet.header(
      stagesContent: stagesContent,
      stagingEnabled: stagingEnabled && controller.hasFiles,
    ).items;
    final compact = mode.isMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              model.title,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: PatchTheme.textHi,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                compact ? '' : model.subtitle,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(color: PatchTheme.subtitle),
              ),
            ),
            for (final action in actions) ...[
              const SizedBox(width: 1),
              PatchChipButton(
                label: action.label,
                primary: action.primary,
                selected: action.selected,
                enabled: action.enabled,
                color: action.color,
                onTap: switch (action.kind) {
                  PatchActionKind.stage =>
                    stagesContent ? onStageContent : onStageWholeFile,
                  PatchActionKind.skip => onSkip,
                  _ => null,
                },
              ),
            ],
          ],
        ),
        Row(
          children: [
            Text(
              '${model.progressBar}  ${model.metrics}',
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(color: PatchTheme.muted),
            ),
          ],
        ),
      ],
    );
  }
}

class PatchFileList extends StatefulWidget {
  const PatchFileList({
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.height,
    required this.mode,
    required this.onChanged,
    required this.onSelect,
  });

  final PatchReviewController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final int height;
  final PatchLayoutMode mode;
  final void Function(int index) onChanged;
  final void Function(int index) onSelect;

  @override
  State<PatchFileList> createState() => _PatchFileListState();
}

class _PatchFileListState extends State<PatchFileList> {
  static const _rowHeight = 1;
  late final ViewportController _viewport;

  List<DiffFile> get _files => widget.controller.diff.files;

  int get _selectedIndex => widget.controller.selectedFileIndex;

  int get _visibleRows => math.max(1, widget.height ~/ _rowHeight);

  @override
  void initState() {
    super.initState();
    final order = _orderedFileIndexes();
    _viewport =
        ViewportController(
          contentExtent: order.length,
          viewportExtent: _visibleRows,
        )..ensureVisible(
          _selectedVisibleIndex(order),
          _selectedVisibleIndex(order) + 1,
        );
  }

  @override
  void didUpdateWidget(PatchFileList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final order = _orderedFileIndexes();
    final selected = _selectedVisibleIndex(order);
    _viewport
      ..contentExtent = order.length
      ..viewportExtent = _visibleRows
      ..ensureVisible(selected, selected + 1);
  }

  @override
  void dispose() {
    _viewport.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!event.isPress) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.character == 'j') {
      _move(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.character == 'k') {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      _move(_visibleRows);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      _move(-_visibleRows);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onSelect(_selectedIndex);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _move(int delta) {
    if (_files.isEmpty) return;
    final order = _orderedFileIndexes();
    final selected = _selectedVisibleIndex(order);
    final next = (selected + delta).clamp(0, order.length - 1);
    if (next == selected) return;
    _viewport.ensureVisible(next, next + 1);
    widget.onChanged(order[next]);
  }

  void _handlePointerDown(MouseEvent event) {
    if (event.button != MouseButton.left || _files.isEmpty) return;
    if (!widget.focusNode.hasFocus) widget.focusNode.requestFocus();
    final order = _orderedFileIndexes();
    final visibleIndex =
        _viewport.scrollOffset + event.localPosition.dy ~/ _rowHeight;
    if (visibleIndex < 0 || visibleIndex >= order.length) return;
    _viewport.ensureVisible(visibleIndex, visibleIndex + 1);
    widget.onChanged(order[visibleIndex]);
    // Single click only selects. The user keeps keyboard focus on the file
    // pane so they can continue navigating with arrows. Pressing Enter (or
    // Tab) is the explicit "activate" gesture that calls onSelect.
  }

  List<int> _orderedFileIndexes() {
    final indexes = List<int>.generate(_files.length, (index) => index)
      ..sort((a, b) {
        final left = GitPathPresentation.asciiSafe(_files[a].pathIdentity);
        final right = GitPathPresentation.asciiSafe(_files[b].pathIdentity);
        final byBasename = left.basename.toLowerCase().compareTo(
          right.basename.toLowerCase(),
        );
        if (byBasename != 0) return byBasename;
        final byParent = left.parentPath.toLowerCase().compareTo(
          right.parentPath.toLowerCase(),
        );
        if (byParent != 0) return byParent;
        final byPath = left.full.toLowerCase().compareTo(
          right.full.toLowerCase(),
        );
        if (byPath != 0) return byPath;
        final byIdentity = compareGitPaths(
          _files[a].pathIdentity,
          _files[b].pathIdentity,
        );
        if (byIdentity != 0) return byIdentity;
        return a.compareTo(b);
      });
    return indexes;
  }

  int _selectedVisibleIndex(List<int> order) {
    final index = order.indexOf(_selectedIndex);
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final order = _orderedFileIndexes();
    final start = _viewport.scrollOffset;
    final end = math.min(order.length, start + _visibleRows);
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKey,
      child: PointerListener(
        onPointerDown: _handlePointerDown,
        child: SizedBox(
          height: widget.height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var visibleIndex = start; visibleIndex < end; visibleIndex++)
                PatchFileRow(
                  model: PatchFileRowModel.fromFile(
                    _files[order[visibleIndex]],
                    status: widget.controller.statusForFile(
                      _files[order[visibleIndex]],
                    ),
                    mode: widget.mode,
                  ),
                  selected: order[visibleIndex] == _selectedIndex,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PatchFileRow extends StatelessWidget {
  const PatchFileRow({required this.model, required this.selected});

  final PatchFileRowModel model;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final rowColor = selected ? PatchTheme.bgPanelAlt : PatchTheme.bgPanel;
    return Container(
      color: rowColor,
      child: Row(
        children: [
          Text(
            PatchTheme.accentBar,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(color: selected ? PatchTheme.accent : rowColor),
          ),
          const SizedBox(width: 1),
          Text(
            model.fileKindGlyph,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: model.fileKindColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 1),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  flex: model.parentHint.isEmpty ? 1 : 5,
                  fit: FlexFit.tight,
                  child: Text(
                    model.basename,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: selected ? PatchTheme.textHi : PatchTheme.text,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (model.parentHint.isNotEmpty) ...[
                  const SizedBox(width: 1),
                  Flexible(
                    flex: 2,
                    fit: FlexFit.tight,
                    child: Text(
                      model.parentHint,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(color: PatchTheme.muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 1),
          if (model.hasLineTotals) ...[
            Text(
              '+${model.additionCount}',
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: PatchTheme.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 1),
            Text(
              '-${model.deletionCount}',
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: PatchTheme.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 1),
          ] else if (model.fallbackMetadata case final metadata?
              when metadata.isNotEmpty) ...[
            Text(
              metadata,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(color: PatchTheme.muted),
            ),
            const SizedBox(width: 1),
          ],
          Container(
            color: _fileStatusPillColor(model.fileStatusLetter),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Text(
              model.fileStatusLetter,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: _fileStatusPillTextColor(model.fileStatusLetter),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 1),
        ],
      ),
    );
  }
}

class PatchDiffSurface extends StatelessWidget {
  const PatchDiffSurface({
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.diffViewController,
    required this.stagingEnabled,
    this.onSkipHunk,
    this.onStageHunk,
    this.onSkipWholeFile,
    this.onStageWholeFile,
    this.onRefresh,
  });

  final PatchReviewController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final noir_diff.DiffViewController diffViewController;
  final bool stagingEnabled;
  final void Function(DiffHunk hunk)? onSkipHunk;
  final void Function(DiffHunk hunk)? onStageHunk;
  final void Function(WholeFileChange change)? onSkipWholeFile;
  final void Function(WholeFileChange change)? onStageWholeFile;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final file = controller.currentFile;
    if (!file.canStageContent && !file.canStageWholeFile) {
      return const Text(
        'This file has no reviewable changes.',
        style: TextStyle(color: PatchTheme.amber),
      );
    }

    final hunkLabel = file.canStageContent
        ? 'hunk ${controller.selectedHunkIndex + 1} of ${file.hunks.length}'
        : WholeFileChangeDisplay.fromChange(
            file.wholeFileStageUnit!,
          ).title.toLowerCase();
    final incompletePreviewLabel = _incompletePreviewHeaderLabel(file);
    final diffAdapter = file.canStageContent ? _PatchDiffAdapter(file) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          GitPathPresentation.asciiSafe(file.pathIdentity).full,
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(
            color: PatchTheme.textHi,
            fontWeight: FontWeight.bold,
          ),
        ),
        Row(
          children: [
            Text(
              '$hunkLabel  '
              '${_plural(file.reviewTargets.length, 'change')}  ',
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(color: PatchTheme.subtitle),
            ),
            if (incompletePreviewLabel != null)
              Text(
                incompletePreviewLabel,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(color: PatchTheme.amber),
              )
            else ...[
              Text(
                '${file.isPreviewTruncated ? 'preview ' : ''}'
                '+${file.additionCount}',
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(color: PatchTheme.green),
              ),
              const SizedBox(width: 1),
              Text(
                '-${file.deletionCount}',
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(color: PatchTheme.red),
              ),
            ],
          ],
        ),
        PatchDiffFilterBar(controller: controller, file: file),
        const SizedBox(height: 1),
        Expanded(
          child: diffAdapter == null
              ? ScrollBox(
                  focusNode: focusNode,
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _wholeFileWidgets(file),
                  ),
                )
              : noir_diff.DiffView(
                  document: diffAdapter.document,
                  controller: diffViewController,
                  scrollController: scrollController,
                  focusNode: focusNode,
                  selectable: false,
                  showLineNumbers: false,
                  rowBuilder: (_, _, hunk, line, _) => diffAdapter.buildRow(
                    hunk: hunk,
                    line: line,
                    controller: controller,
                    stagingEnabled: stagingEnabled,
                    onSkipHunk: onSkipHunk,
                    onStageHunk: onStageHunk,
                    onRefresh: onRefresh,
                  ),
                ),
        ),
      ],
    );
  }

  List<Widget> _wholeFileWidgets(DiffFile file) {
    final change = file.wholeFileStageUnit!;
    final widgets = <Widget>[
      PatchWholeFileCard(
        controller: controller,
        change: change,
        stagingEnabled: stagingEnabled,
        onSkip: onSkipWholeFile,
        onStage: onStageWholeFile,
        onRefresh: onRefresh,
      ),
    ];
    final notice = _untrackedPreviewNotice(file);
    if (notice != null) {
      widgets
        ..add(const SizedBox(height: 1))
        ..add(
          Text(
            notice,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(color: PatchTheme.amber),
          ),
        );
    }
    if (file.untrackedPreviewLines.isNotEmpty) {
      widgets.add(const SizedBox(height: 1));
      for (final line in file.untrackedPreviewLines) {
        widgets.add(
          Text(
            line,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(color: PatchTheme.text),
          ),
        );
      }
    }
    return widgets;
  }
}

final class _PatchDiffAdapter {
  _PatchDiffAdapter(DiffFile file) {
    final presentationHunks = <noir_diff.DiffHunk>[];
    for (var hunkIndex = 0; hunkIndex < file.hunks.length; hunkIndex++) {
      final hunk = file.hunks[hunkIndex];
      final presentationLines = <noir_diff.DiffLine>[];
      for (var lineIndex = 0; lineIndex < hunk.lines.length; lineIndex++) {
        final line = hunk.lines[lineIndex];
        final presentation = noir_diff.DiffLine(
          kind: switch (line.type) {
            DiffLineType.context => noir_diff.DiffLineKind.context,
            DiffLineType.addition => noir_diff.DiffLineKind.addition,
            DiffLineType.deletion => noir_diff.DiffLineKind.deletion,
            DiffLineType.noNewlineMarker =>
              noir_diff.DiffLineKind.noNewlineMarker,
          },
          text: line.text,
          oldLineNumber: line.oldLineNumber,
          newLineNumber: line.newLineNumber,
        );
        presentationLines.add(presentation);
        _lines[presentation] = (hunk: hunk, lineIndex: lineIndex);
      }
      final presentation = noir_diff.DiffHunk(
        oldStart: hunk.oldStart,
        oldCount: hunk.oldCount,
        newStart: hunk.newStart,
        newCount: hunk.newCount,
        header: hunk.sectionHeading,
        lines: presentationLines,
      );
      presentationHunks.add(presentation);
      _hunks[presentation] = (hunk: hunk, hunkIndex: hunkIndex);
    }
    document = noir_diff.DiffDocument(<noir_diff.DiffFile>[
      noir_diff.DiffFile(
        oldPath: file.oldPath == null
            ? null
            : GitPathPresentation.asciiSafe(file.oldPath!).full,
        newPath: file.newPath == null
            ? null
            : GitPathPresentation.asciiSafe(file.newPath!).full,
        hunks: presentationHunks,
      ),
    ]);
  }

  late final noir_diff.DiffDocument document;
  final Map<noir_diff.DiffHunk, ({DiffHunk hunk, int hunkIndex})> _hunks = {};
  final Map<noir_diff.DiffLine, ({DiffHunk hunk, int lineIndex})> _lines = {};

  Widget buildRow({
    required noir_diff.DiffHunk hunk,
    required noir_diff.DiffLine? line,
    required PatchReviewController controller,
    required bool stagingEnabled,
    required void Function(DiffHunk hunk)? onSkipHunk,
    required void Function(DiffHunk hunk)? onStageHunk,
    required VoidCallback? onRefresh,
  }) {
    final hunkRecord = _hunks[hunk]!;
    final selectedHunk = hunkRecord.hunkIndex == controller.selectedHunkIndex;
    if (line == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PatchHunkBorderRow(selected: selectedHunk, top: true),
          PatchHunkCard(
            controller: controller,
            hunk: hunkRecord.hunk,
            selected: selectedHunk,
            stagingEnabled: stagingEnabled,
            onSkipHunk: onSkipHunk,
            onStageHunk: onStageHunk,
            onRefresh: onRefresh,
          ),
        ],
      );
    }
    final lineRecord = _lines[line]!;
    final last = lineRecord.lineIndex == lineRecord.hunk.lines.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PatchDiffLine(
          controller: controller,
          hunk: lineRecord.hunk,
          lineIndex: lineRecord.lineIndex,
          framed: true,
          selectedHunk: selectedHunk,
        ),
        if (last) ...<Widget>[
          PatchHunkBorderRow(selected: selectedHunk, top: false),
          const SizedBox(height: 1),
        ],
      ],
    );
  }
}

String? _incompletePreviewHeaderLabel(DiffFile file) =>
    switch (file.untrackedPreviewState) {
      UntrackedPreviewState.binary => 'binary preview',
      UntrackedPreviewState.unavailable => 'preview unavailable',
      UntrackedPreviewState.omitted => 'preview omitted',
      _ => null,
    };

String? _untrackedPreviewNotice(DiffFile file) {
  if (!file.isUntracked) return null;
  return switch (file.untrackedPreviewState!) {
    UntrackedPreviewState.completeText =>
      file.isSymbolicLink
          ? 'Stored symbolic-link target preview. Staging uses the link itself.'
          : null,
    UntrackedPreviewState.truncatedText =>
      file.isSymbolicLink
          ? 'Stored symbolic-link target preview is truncated. Staging uses the complete link.'
          : 'Untracked text preview is truncated. Staging uses the complete file.',
    UntrackedPreviewState.binary =>
      'Untracked binary file. Preview unavailable. Press f to stage the file.',
    UntrackedPreviewState.unavailable =>
      'Untracked preview unavailable. Press f to stage the path.',
    UntrackedPreviewState.omitted =>
      'Untracked preview omitted by workspace limits. Press f to stage the path.',
  };
}

class PatchDiffFilterBar extends StatelessWidget {
  const PatchDiffFilterBar({
    required this.controller,
    required this.file,
    super.key,
  });

  final PatchReviewController controller;
  final DiffFile file;

  @override
  Widget build(BuildContext context) {
    final staged = controller.stagedCountFor(file);
    final skipped = controller.skippedCountFor(file);
    final pending = controller.pendingCountFor(file);

    final pills = <Widget>[
      _Pill(
        glyph: PatchTheme.statusGlyph(PatchReviewStatus.staged),
        color: PatchTheme.cyan,
        text: '$staged staged',
      ),
      _Pill(
        glyph: PatchTheme.statusGlyph(PatchReviewStatus.skipped),
        color: PatchTheme.amber,
        text: '$skipped skipped',
      ),
      _Pill(
        glyph: PatchTheme.statusGlyph(PatchReviewStatus.unreviewed),
        color: PatchTheme.grayDot,
        text: '$pending pending',
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < pills.length; i++) ...[
          if (i > 0) const SizedBox(width: 1),
          pills[i],
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.glyph, required this.color, required this.text});

  final String glyph;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    color: PatchTheme.bgPanelAlt,
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: Row(
      children: [
        Text(glyph, style: TextStyle(color: color)),
        const SizedBox(width: 1),
        Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(color: PatchTheme.muted),
        ),
      ],
    ),
  );
}

class PatchWholeFileCard extends StatelessWidget {
  const PatchWholeFileCard({
    required this.controller,
    required this.change,
    required this.stagingEnabled,
    this.onSkip,
    this.onStage,
    this.onRefresh,
  });

  final PatchReviewController controller;
  final WholeFileChange change;
  final bool stagingEnabled;
  final void Function(WholeFileChange change)? onSkip;
  final void Function(WholeFileChange change)? onStage;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final status = controller.statusForWholeFile(change);
    final presentation = WholeFileChangeDisplay.fromChange(change);
    final actions = PatchActionSet.forTarget(
      status,
      stagesContent: false,
      stagingEnabled: stagingEnabled,
    );
    return Container(
      color: PatchTheme.bgPanelAlt,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                PatchTheme.statusGlyph(status),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(color: PatchTheme.statusColor(status)),
              ),
              const SizedBox(width: 1),
              Expanded(
                child: Text(
                  presentation.title,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    color: PatchTheme.textHi,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              for (final action in actions.items) ...[
                const SizedBox(width: 1),
                PatchChipButton(
                  label: action.label,
                  primary: action.primary,
                  selected: action.selected,
                  enabled: action.enabled,
                  color: action.color,
                  onTap: switch (action.kind) {
                    PatchActionKind.stage =>
                      onStage == null ? null : () => onStage!(change),
                    PatchActionKind.skip =>
                      onSkip == null ? null : () => onSkip!(change),
                    PatchActionKind.refresh => onRefresh,
                    PatchActionKind.staged => null,
                  },
                ),
              ],
            ],
          ),
          Text(
            presentation.description,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(color: PatchTheme.subtitle),
          ),
        ],
      ),
    );
  }
}

class PatchHunkCard extends StatelessWidget {
  const PatchHunkCard({
    required this.controller,
    required this.hunk,
    required this.selected,
    required this.stagingEnabled,
    this.onSkipHunk,
    this.onStageHunk,
    this.onRefresh,
  });

  final PatchReviewController controller;
  final DiffHunk hunk;
  final bool selected;
  final bool stagingEnabled;
  final void Function(DiffHunk hunk)? onSkipHunk;
  final void Function(DiffHunk hunk)? onStageHunk;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final hunkStatus = controller.statusForHunk(hunk);
    final actions = PatchActionSet.forTarget(
      hunkStatus,
      stagesContent: true,
      stagingEnabled: stagingEnabled,
    );
    final borderStyle = TextStyle(
      color: selected ? PatchTheme.borderHi : PatchTheme.border,
    );
    return Container(
      color: selected ? PatchTheme.bgSelected : PatchTheme.bgPanelAlt,
      child: Row(
        children: [
          Text('│', maxLines: 1, softWrap: false, style: borderStyle),
          const SizedBox(width: 1),
          Text(
            PatchTheme.statusGlyph(hunkStatus),
            maxLines: 1,
            softWrap: false,
            style: TextStyle(color: PatchTheme.statusColor(hunkStatus)),
          ),
          const SizedBox(width: 1),
          Expanded(
            child: Text(
              _hunkCardTitle(hunk),
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: selected ? PatchTheme.textHi : PatchTheme.subtitle,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          for (final action in actions.items) ...[
            const SizedBox(width: 1),
            PatchChipButton(
              label: action.label,
              primary: action.primary,
              selected: action.selected,
              enabled: action.enabled,
              color: action.color,
              onTap: _chipCallback(action.kind),
            ),
          ],
          const SizedBox(width: 1),
          Text('│', maxLines: 1, softWrap: false, style: borderStyle),
        ],
      ),
    );
  }

  VoidCallback? _chipCallback(PatchActionKind kind) => switch (kind) {
    PatchActionKind.skip => onSkipHunk == null ? null : () => onSkipHunk!(hunk),
    PatchActionKind.stage =>
      onStageHunk == null ? null : () => onStageHunk!(hunk),
    PatchActionKind.refresh => onRefresh,
    PatchActionKind.staged => null,
  };
}

String _hunkCardTitle(DiffHunk hunk) {
  final heading = hunk.sectionHeading.trim();
  if (heading.isNotEmpty) return '@@ $heading @@';
  return hunk.rawHeader;
}

class PatchHunkBorderRow extends StatelessWidget {
  const PatchHunkBorderRow({required this.selected, required this.top});

  final bool selected;
  final bool top;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PatchTheme.borderHi : PatchTheme.border;
    return Row(
      children: [
        Text(
          top ? '╭' : '╰',
          maxLines: 1,
          softWrap: false,
          style: TextStyle(color: color),
        ),
        Expanded(
          child: Text(
            '────────────────────────────────────────────────────────────────────────────────────────────────────────────────',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(color: color),
          ),
        ),
        Text(
          top ? '╮' : '╯',
          maxLines: 1,
          softWrap: false,
          style: TextStyle(color: color),
        ),
      ],
    );
  }
}

class PatchDiffLine extends StatelessWidget {
  const PatchDiffLine({
    required this.controller,
    required this.hunk,
    required this.lineIndex,
    this.framed = false,
    this.selectedHunk = false,
  });

  final PatchReviewController controller;
  final DiffHunk hunk;
  final int lineIndex;
  final bool framed;
  final bool selectedHunk;

  @override
  Widget build(BuildContext context) {
    final line = hunk.lines[lineIndex];
    final currentSection = controller.currentSection;
    final selected =
        currentSection != null &&
        currentSection.hunkId == hunk.id &&
        currentSection.selectedLineIndexes.contains(lineIndex);
    final marker = switch (line.type) {
      DiffLineType.addition => '+',
      DiffLineType.deletion => '-',
      DiffLineType.noNewlineMarker => r'\',
      DiffLineType.context => ' ',
    };
    final stripeColor = switch (line.type) {
      DiffLineType.addition => PatchTheme.diffAddStripe,
      DiffLineType.deletion => PatchTheme.diffDelStripe,
      DiffLineType.noNewlineMarker => PatchTheme.amber,
      DiffLineType.context => PatchTheme.bgPanel,
    };
    // Unified single-column line number: pick the relevant side for each
    // line type so the user reads one number per row instead of an old/new
    // pair. Context lines keep the new-side number (matches `git diff`'s
    // unified output for hunks).
    final lineNumber = switch (line.type) {
      DiffLineType.addition => line.newLineNumber,
      DiffLineType.deletion => line.oldLineNumber,
      DiffLineType.noNewlineMarker => null,
      DiffLineType.context => line.newLineNumber,
    };
    final lineRow = Container(
      color: _lineBackground(line),
      child: Row(
        children: [
          Container(
            color: stripeColor,
            child: const Text(' ', maxLines: 1, softWrap: false),
          ),
          Expanded(
            child: Text(
              '${selected ? PatchTheme.caret : ' '} $marker '
              '${_lineNumber(lineNumber)}  '
              '${line.text}',
              maxLines: 1,
              softWrap: false,
              style: _lineStyle(line),
            ),
          ),
        ],
      ),
    );
    if (!framed) return lineRow;
    final borderStyle = TextStyle(
      color: selectedHunk ? PatchTheme.borderHi : PatchTheme.border,
    );
    return Row(
      children: [
        Text('│', maxLines: 1, softWrap: false, style: borderStyle),
        Expanded(child: lineRow),
        Text('│', maxLines: 1, softWrap: false, style: borderStyle),
      ],
    );
  }
}

class PatchStatusFooter extends StatelessWidget {
  const PatchStatusFooter({
    required this.status,
    required this.busy,
    required this.mode,
  });

  final String status;
  final bool busy;
  final PatchLayoutMode mode;

  @override
  Widget build(BuildContext context) => Text(
    PatchFooterText.fromStatus(status: status, busy: busy, mode: mode).text,
    maxLines: 1,
    softWrap: false,
    style: const TextStyle(color: PatchTheme.text),
  );
}

Color _fileStatusPillColor(String status) => switch (status) {
  'A' || 'U' => PatchTheme.green,
  'S' || 'M' || 'R' || 'B' => PatchTheme.cyan,
  'D' || '!' => PatchTheme.red,
  'K' => PatchTheme.amber,
  _ => PatchTheme.grayDot,
};

Color _fileStatusPillTextColor(String status) =>
    status == '!' ? PatchTheme.textHi : PatchTheme.accentInk;

Color _lineBackground(DiffLine line) => switch (line.type) {
  DiffLineType.addition => PatchTheme.diffAddBg,
  DiffLineType.deletion => PatchTheme.diffDelBg,
  DiffLineType.noNewlineMarker => PatchTheme.diffNoNewlineBg,
  DiffLineType.context => PatchTheme.bgPanel,
};

TextStyle _lineStyle(DiffLine line) {
  final foreground = switch (line.type) {
    DiffLineType.addition => PatchTheme.diffAddFg,
    DiffLineType.deletion => PatchTheme.diffDelFg,
    DiffLineType.noNewlineMarker => PatchTheme.amber,
    DiffLineType.context => PatchTheme.text,
  };
  final background = _lineBackground(line);
  return TextStyle(color: foreground, backgroundColor: background);
}

String _lineNumber(int? value) =>
    value == null ? '   ' : value.toString().padLeft(3);

String _plural(int count, String noun) =>
    '$count $noun${count == 1 ? '' : 's'}';

/// A compact chip-button styled with a background color.
///
/// `primary: true` uses the accent palette (bright cyan + dark ink); the
/// default (secondary) chip uses the alt-panel background so it reads as a
/// pressable surface against the panel background.
class PatchChipButton extends StatelessWidget {
  const PatchChipButton({
    required this.label,
    this.primary = false,
    this.selected = false,
    this.enabled = true,
    this.color,
    this.onTap,
    super.key,
  });

  final String label;
  final bool primary;
  final bool selected;
  final bool enabled;
  final Color? color;

  /// Fires on a left-button click anywhere inside the chip. `null` makes
  /// the chip a non-interactive label.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? PatchTheme.accent;
    final bg = selected
        ? PatchTheme.bgSelected
        : (primary ? PatchTheme.accent : PatchTheme.bgPanelAlt);
    final fg = !enabled
        ? PatchTheme.muted
        : selected
        ? tone
        : (primary ? PatchTheme.accentInk : PatchTheme.text);
    final chip = Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          color: fg,
          fontWeight: primary || selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
    final tap = onTap;
    if (tap == null || !enabled) return chip;
    return PointerListener(
      onPointerDown: (event) {
        if (event.button == MouseButton.left) tap();
      },
      child: chip,
    );
  }
}
