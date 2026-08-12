// ignore_for_file: avoid_setters_without_getters, public_member_api_docs

import 'dart:async';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../core/input.dart';
import '../../framework/build_context.dart';
import '../../framework/focus_manager.dart';
import '../../framework/widget.dart';
import '../../painting/box_border.dart';
import '../../painting/box_decoration.dart';
import '../../render/geometry.dart';
import '../../rendering/object.dart';
import '../../rendering/proxy_box.dart';
import '../../widgets/container.dart';
import '../../widgets/flexible.dart';
import '../../widgets/focus.dart';
import '../../widgets/row_column.dart';
import '../../widgets/scroll_box.dart';
import '../../widgets/sized_box.dart';
import '../../widgets/text.dart';
import '../../widgets/text_style.dart';
import 'display_models.dart';
import 'git_path.dart';
import 'git_repository.dart';
import 'models.dart';
import 'patch_manager_widgets.dart';
import 'patch_theme.dart';
import 'review_controller.dart';

typedef StagePatchContent =
    Future<GitStageResult> Function(ContentStageSelection selection);

typedef StageWholeFileChange =
    Future<GitStageResult> Function(WholeFileChange change);

typedef RefreshPatchWorkspace = Future<DiffSet> Function();

class PatchManagerApp extends StatefulWidget {
  const PatchManagerApp({
    required this.repository,
    required this.onQuit,
    super.key,
  });

  final GitPatchRepository repository;
  final void Function() onQuit;

  @override
  State<PatchManagerApp> createState() => _PatchManagerAppState();
}

class _PatchManagerAppState extends State<PatchManagerApp> {
  PatchReviewController? _controller;
  String _status = 'Loading workspace changes...';
  bool _loading = true;
  int _workspaceLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final token = _claimWorkspaceLoad();
    // Initial values already describe loading; no setState needed.
    _scheduleWorkspaceLoad(token);
  }

  @override
  void didUpdateWidget(PatchManagerApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.repository, oldWidget.repository)) {
      return;
    }
    final token = _claimWorkspaceLoad();
    _controller = null;
    _loading = true;
    _status = 'Loading workspace changes...';
    _scheduleWorkspaceLoad(token);
  }

  @override
  void dispose() {
    _workspaceLoadGeneration++;
    super.dispose();
  }

  _WorkspaceLoadToken _claimWorkspaceLoad() =>
      (generation: ++_workspaceLoadGeneration, repository: widget.repository);

  bool _ownsWorkspaceLoad(_WorkspaceLoadToken token) {
    if (!mounted || token.generation != _workspaceLoadGeneration) {
      return false;
    }
    return identical(widget.repository, token.repository);
  }

  void _scheduleWorkspaceLoad(_WorkspaceLoadToken token) {
    unawaited(Future<void>.microtask(() => _completeWorkspaceLoad(token)));
  }

  void _startUserWorkspaceLoad({required bool afterFailure}) {
    final token = _claimWorkspaceLoad();
    setState(() {
      _controller = null;
      _loading = true;
      _status = afterFailure
          ? 'Retrying workspace load...'
          : 'Starting another workspace load...';
    });
    _scheduleWorkspaceLoad(token);
  }

  Future<void> _completeWorkspaceLoad(_WorkspaceLoadToken token) async {
    try {
      final diff = await token.repository.loadWorkspace();
      if (!_ownsWorkspaceLoad(token)) return;
      setState(() {
        _controller = PatchReviewController(diff);
        _loading = false;
        _status = _loadedStatus(diff);
      });
    } on Object catch (error) {
      if (!_ownsWorkspaceLoad(token)) return;
      final diagnostic = GitDiagnosticText.fromObject(error).text;
      setState(() {
        _controller = null;
        _loading = false;
        _status = 'Git error: $diagnostic';
      });
    }
  }

  String _loadedStatus(DiffSet diff) => diff.files.isEmpty
      ? 'No unstaged tracked changes or untracked files.'
      : 'Loaded ${diff.files.length} files, '
            '${diff.stageableReviewTargetCount} review changes.';

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return _MessageScreen(
        title: 'Patch Manager',
        message: _status,
        loading: _loading,
        onQuit: widget.onQuit,
        onRefresh: () => _startUserWorkspaceLoad(afterFailure: !_loading),
      );
    }

    return PatchManagerView(
      controller: controller,
      onQuit: widget.onQuit,
      initialStatus: _status,
      onRefresh: widget.repository.loadWorkspace,
      onStageContent: widget.repository.stageContent,
      onStageWholeFile: widget.repository.stageWholeFile,
    );
  }
}

typedef _WorkspaceLoadToken = ({int generation, GitPatchRepository repository});

class PatchManagerView extends StatefulWidget {
  const PatchManagerView({
    required this.controller,
    required this.onQuit,
    this.onStageContent,
    this.onStageWholeFile,
    this.onRefresh,
    this.initialStatus,
    this.autofocus = true,
    this.layoutWidthOverride,
    super.key,
  });

  final PatchReviewController controller;
  final void Function() onQuit;
  final StagePatchContent? onStageContent;
  final StageWholeFileChange? onStageWholeFile;
  final RefreshPatchWorkspace? onRefresh;
  final String? initialStatus;
  final bool autofocus;
  final int? layoutWidthOverride;

  @override
  State<PatchManagerView> createState() => _PatchManagerViewState();
}

class _PatchManagerViewState extends State<PatchManagerView> {
  final _scope = FocusScopeNode();
  final _filesFocus = FocusNode();
  final _diffFocus = FocusNode();
  late final List<FocusNode> _focusRing;
  late ScrollController _diffScroll;
  String? _diffScrollTarget;
  late String _status;
  bool _busy = false;
  bool _refreshRequired = false;
  String? _retainedStageDiagnostic;
  String? _latestRefreshDiagnostic;
  int _workspaceWidth = 140;

  PatchReviewController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _status =
        widget.initialStatus ??
        'Stage content or whole-file changes directly, or skip them.';
    _workspaceWidth = widget.layoutWidthOverride ?? _workspaceWidth;
    _focusRing = [_filesFocus, _diffFocus];
    for (final node in _focusRing) {
      node.addListener(_focusChanged);
    }
    _diffScroll = ScrollController(
      initialOffset: _selectedSectionScrollOffset().toDouble(),
    );
    _diffScrollTarget = _selectedSectionKey();
  }

  @override
  void didUpdateWidget(PatchManagerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStatus != oldWidget.initialStatus &&
        widget.initialStatus != null) {
      _status = widget.initialStatus!;
    }
    if (widget.layoutWidthOverride != oldWidget.layoutWidthOverride &&
        widget.layoutWidthOverride != null) {
      _workspaceWidth = widget.layoutWidthOverride!;
    }
  }

  @override
  void dispose() {
    _scope.dispose();
    for (final node in _focusRing) {
      node
        ..removeListener(_focusChanged)
        ..dispose();
    }
    _diffScroll.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  KeyEventResult _handleKeys(FocusNode node, KeyEvent event) {
    if (!event.isPress) return KeyEventResult.ignored;

    if (_busy) {
      setState(() {
        _status = 'Working; finish the current operation before reviewing.';
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.character == 'q') {
      widget.onQuit();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _focusNext(event.isShiftPressed ? -1 : 1);
      return KeyEventResult.handled;
    }

    switch (event.character) {
      case ' ' || 's' || 'S':
        _stageCurrentHunk();
        return KeyEventResult.handled;
      case 'x':
        _skipCurrentReviewTarget();
        return KeyEventResult.handled;
      case 'f':
        if (_controller.hasFiles) {
          _stageWholeFile(_controller.currentFile.wholeFileStageUnit);
        }
        return KeyEventResult.handled;
      case 'r':
        _refresh();
        return KeyEventResult.handled;
      case 'j':
        _selectNextSection();
        return KeyEventResult.handled;
      case 'k':
        _selectPreviousSection();
        return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _selectNextSection();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _selectPreviousSection();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _selectFile(int index) {
    setState(() {
      _controller.selectFile(index);
      _resetDiffScrollForSelection();
    });
  }

  void _selectNextSection() {
    setState(() {
      _controller.selectNextSection();
      _resetDiffScrollForSelection();
    });
  }

  void _selectPreviousSection() {
    setState(() {
      _controller.selectPreviousSection();
      _resetDiffScrollForSelection();
    });
  }

  void _focusNext(int delta) {
    final current = _focusRing.indexWhere((node) => node.hasFocus);
    final start = current == -1 ? 0 : current;
    final next = (start + delta) % _focusRing.length;
    _focusRing[next].requestFocus();
  }

  void _resetDiffScrollForSelection() {
    final target = _selectedSectionKey();
    _diffScrollTarget = target;
    _diffScroll.dispose();
    _diffScroll = ScrollController(
      initialOffset: _selectedSectionScrollOffset().toDouble(),
    );
  }

  void _syncDiffScrollWithExternalSelection() {
    final target = _selectedSectionKey();
    if (target == _diffScrollTarget) return;
    _resetDiffScrollForSelection();
  }

  String? _selectedSectionKey() {
    if (!_controller.hasFiles) return null;
    return _controller.currentSection?.id;
  }

  int _selectedSectionScrollOffset() {
    if (!_controller.hasFiles) return 0;
    final file = _controller.currentFile;
    final selected = _controller.currentSection;
    if (selected == null) return 0;
    var row = 0;
    for (final hunk in file.hunks) {
      row++;
      if (hunk.id == selected.hunkId) {
        final firstLine = selected.selectedLineIndexes.isEmpty
            ? 0
            : selected.selectedLineIndexes.reduce(math.min);
        final target = row + firstLine;
        return target <= 4 ? 0 : target;
      }
      row += hunk.lines.length + 1;
    }
    return 0;
  }

  void _skipCurrentReviewTarget() {
    if (_busy) return;
    if (!_controller.hasFiles) return;
    setState(() {
      _controller.skipCurrentReviewTarget();
      final hunk = _controller.currentHunk;
      final status = hunk == null
          ? _controller.statusForWholeFile(_controller.currentWholeFileChange!)
          : _controller.statusForHunk(hunk);
      _status = 'Current change is ${patchStatusLabel(status)}.';
    });
  }

  void _skipHunk(DiffHunk hunk) {
    if (_busy) return;
    setState(() {
      _controller.skipHunk(hunk);
      final status = patchStatusLabel(_controller.statusForHunk(hunk));
      _status = 'Hunk is $status.';
    });
  }

  void _stageCurrentHunk() {
    if (_busy) return;
    if (!_controller.hasFiles) return;
    final file = _controller.currentFile;
    final selection = _controller.currentHunkContentSelection();
    _stageContentSelection(
      selection,
      emptyStatus: file.canStageContent
          ? 'Current hunk is already staged.'
          : 'This change requires whole-file staging; use stage file.',
    );
  }

  void _stageHunk(DiffHunk hunk) {
    if (_busy) return;
    final selection = _controller.contentSelectionForHunk(hunk);
    _stageContentSelection(selection, emptyStatus: 'Hunk is already staged.');
  }

  Future<void> _stageContentSelection(
    ContentStageSelection? selection, {
    String emptyStatus = 'No unstaged changes to stage.',
  }) async {
    if (_busy) return;
    if (_refreshRequired) {
      setState(() => _status = 'Refresh before staging another change.');
      return;
    }
    final onStage = widget.onStageContent;
    if (selection == null) {
      setState(() => _status = emptyStatus);
      return;
    }
    if (onStage == null) {
      setState(() => _status = 'No staging adapter configured.');
      return;
    }

    setState(() {
      _busy = true;
      _status = _stagePendingStatus(selection.sections.length);
    });

    late final GitStageResult result;
    try {
      result = await onStage(selection);
    } on Object catch (error) {
      if (!mounted) return;
      final diagnostic = GitDiagnosticText.fromObject(error).text;
      setState(() {
        _busy = false;
        _controller.recordContentStageOutcome(
          selection,
          GitStageOutcome.failedRefreshRequired,
        );
        _enterRefreshRequired(diagnostic);
      });
      return;
    }
    if (!mounted) return;

    setState(() {
      _controller.recordContentStageOutcome(selection, result.outcome);
      _busy = false;
      switch (result.outcome) {
        case GitStageOutcome.applied:
          _status = _stageCompleteStatus(selection.sections.length);
        case GitStageOutcome.rejectedUnchanged:
          _status = result.stderr.trim().isEmpty
              ? 'Stage rejected; the index was not changed.'
              : 'Stage rejected: '
                    '${GitDiagnosticText.fromObject(result.stderr)}';
        case GitStageOutcome.failedRefreshRequired:
          _enterRefreshRequired(
            result.stderr.trim().isEmpty
                ? 'Content staging returned an uncertain index state.'
                : GitDiagnosticText.fromObject(result.stderr).text,
          );
      }
    });
  }

  Future<void> _stageWholeFile(WholeFileChange? change) async {
    if (_busy) return;
    if (_refreshRequired) {
      setState(() => _status = 'Refresh before staging another change.');
      return;
    }
    if (change == null) {
      setState(() => _status = 'Current file has no whole-file stage target.');
      return;
    }
    final onStage = widget.onStageWholeFile;
    if (onStage == null) {
      setState(() => _status = 'No whole-file staging adapter configured.');
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Staging whole file...';
    });

    late final GitStageResult result;
    try {
      result = await onStage(change);
    } on Object catch (error) {
      if (!mounted) return;
      final diagnostic = GitDiagnosticText.fromObject(error).text;
      setState(() {
        _busy = false;
        _controller.recordWholeFileStageOutcome(
          change,
          GitStageOutcome.failedRefreshRequired,
        );
        _enterRefreshRequired(diagnostic);
      });
      return;
    }
    if (!mounted) return;

    setState(() {
      _controller.recordWholeFileStageOutcome(change, result.outcome);
      _busy = false;
      switch (result.outcome) {
        case GitStageOutcome.applied:
          _status = 'Staged whole file.';
        case GitStageOutcome.rejectedUnchanged:
          _status = result.stderr.trim().isEmpty
              ? 'Whole-file stage rejected; the index was not changed.'
              : 'Whole-file stage rejected: '
                    '${GitDiagnosticText.fromObject(result.stderr)}';
        case GitStageOutcome.failedRefreshRequired:
          _enterRefreshRequired(
            result.stderr.trim().isEmpty
                ? 'Whole-file staging returned an uncertain index state.'
                : GitDiagnosticText.fromObject(result.stderr).text,
          );
      }
    });
  }

  Future<void> _refresh() async {
    if (_busy) return;
    final onRefresh = widget.onRefresh;
    if (onRefresh == null) {
      setState(() => _status = 'Refresh is not configured.');
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Refreshing workspace diff...';
    });

    try {
      final diff = await onRefresh();
      if (!mounted) return;
      setState(() {
        _controller.refresh(diff);
        _busy = false;
        _refreshRequired = false;
        _retainedStageDiagnostic = null;
        _latestRefreshDiagnostic = null;
        _status =
            'Refreshed ${diff.stageableReviewTargetCount} '
            '${diff.stageableReviewTargetCount == 1 ? 'change' : 'changes'}.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      final diagnostic = GitDiagnosticText.fromObject(error).text;
      setState(() {
        _busy = false;
        if (_refreshRequired) {
          _latestRefreshDiagnostic = diagnostic;
        } else {
          _status = 'Refresh failed: $diagnostic';
        }
      });
    }
  }

  void _enterRefreshRequired(String diagnostic) {
    _refreshRequired = true;
    _retainedStageDiagnostic ??= diagnostic;
    _status = 'Refresh required.';
  }

  String get _visibleStatus {
    if (!_refreshRequired) return _status;
    final original =
        _retainedStageDiagnostic ?? 'Staging returned an uncertain result.';
    final latest = _latestRefreshDiagnostic;
    return 'Staging locked: index may have changed; refresh required. '
        'Original stage failure: $original'
        '${latest == null ? '' : '  Latest refresh failed: $latest'}';
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    node: _scope,
    onKeyEvent: _handleKeys,
    child: Container(
      padding: const EdgeInsets.all(1),
      color: PatchTheme.bgBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PatchHeader(
            controller: _controller,
            mode: PatchLayoutMode.fromWidth(_workspaceWidth),
            stagingEnabled: !_refreshRequired,
            onSkip: _skipCurrentReviewTarget,
            onStageContent: _stageCurrentHunk,
            onStageWholeFile: () =>
                _stageWholeFile(_controller.currentWholeFileChange),
          ),
          const SizedBox(height: 1),
          Expanded(
            child: LayoutProbe(
              onSizeChanged: _handleWorkspaceSize,
              child: _controller.hasFiles ? _workspace() : _emptyWorkspace(),
            ),
          ),
          const SizedBox(height: 1),
          PatchStatusFooter(
            status: _visibleStatus,
            busy: _busy,
            mode: PatchLayoutMode.fromWidth(_workspaceWidth),
          ),
        ],
      ),
    ),
  );

  void _handleWorkspaceSize(Size size) {
    if (widget.layoutWidthOverride != null) return;
    final width = size.width;
    if (width == _workspaceWidth) return;
    scheduleMicrotask(() {
      if (!mounted || width == _workspaceWidth) return;
      setState(() => _workspaceWidth = width);
    });
  }

  Widget _workspace() {
    _syncDiffScrollWithExternalSelection();
    final mode = PatchLayoutMode.fromWidth(_workspaceWidth);
    final compact = mode.isMedium;
    final leftWidth = _sidebarWidth(_workspaceWidth, mode);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: leftWidth,
          child: _panel(
            title: 'Changed Files',
            focused: _filesFocus.hasFocus,
            child: PatchFileList(
              controller: _controller,
              focusNode: _filesFocus,
              autofocus: widget.autofocus,
              height: compact ? 20 : 27,
              mode: mode,
              onChanged: _selectFile,
              onSelect: (index) => _diffFocus.requestFocus(),
            ),
          ),
        ),
        const SizedBox(width: 1),
        Expanded(
          child: _panel(
            title: 'Diff Review',
            focused: _diffFocus.hasFocus,
            child: PatchDiffSurface(
              controller: _controller,
              focusNode: _diffFocus,
              scrollController: _diffScroll,
              stagingEnabled: !_refreshRequired,
              onSkipHunk: _skipHunk,
              onStageHunk: _stageHunk,
              onSkipWholeFile: (_) => _skipCurrentReviewTarget(),
              onStageWholeFile: _stageWholeFile,
              onRefresh: _refresh,
            ),
          ),
        ),
      ],
    );
  }

  int _sidebarWidth(int workspaceWidth, PatchLayoutMode mode) {
    final target = (workspaceWidth * 0.30).round();
    if (mode.isMedium) {
      return math.min(34, math.max(30, target));
    }
    return math.min(46, math.max(38, target));
  }

  Widget _emptyWorkspace() => _panel(
    title: 'Workspace',
    focused: false,
    child: const Text(
      'No unstaged tracked changes or untracked files.',
      style: TextStyle(color: PatchTheme.text),
    ),
  );

  Widget _panel({
    required String title,
    required bool focused,
    required Widget child,
  }) {
    final border = focused ? PatchTheme.borderHi : PatchTheme.border;
    return Container(
      decoration: BoxDecoration(
        color: PatchTheme.bgPanel,
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: focused ? PatchTheme.textHi : border,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  String _stagePendingStatus(int sectionCount) =>
      sectionCount == 1 ? 'Staging hunk...' : 'Staging selected changes...';

  String _stageCompleteStatus(int sectionCount) =>
      sectionCount == 1 ? 'Staged hunk.' : 'Staged selected changes.';
}

@internal
class LayoutProbe extends SingleChildRenderObjectWidget {
  const LayoutProbe({required this.onSizeChanged, required super.child});

  final void Function(Size size) onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutProbe(onSizeChanged);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLayoutProbe).onSizeChanged = onSizeChanged;
  }
}

class _RenderLayoutProbe extends RenderProxyBox {
  _RenderLayoutProbe(void Function(Size size) onSizeChanged)
    : _onSizeChanged = onSizeChanged;

  void Function(Size size) _onSizeChanged;
  Size? _lastSize;

  set onSizeChanged(void Function(Size size) value) {
    if (identical(_onSizeChanged, value)) return;
    _onSizeChanged = value;
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    super.performBoxLayout(constraints);
    if (size == _lastSize) return;
    _lastSize = size;
    _onSizeChanged(size);
  }
}

class _MessageScreen extends StatelessWidget {
  const _MessageScreen({
    required this.title,
    required this.message,
    required this.loading,
    required this.onQuit,
    required this.onRefresh,
  });

  final String title;
  final String message;
  final bool loading;
  final void Function() onQuit;
  final void Function() onRefresh;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      if (!event.isPress) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.escape ||
          event.character == 'q') {
        onQuit();
        return KeyEventResult.handled;
      }
      if (event.character == 'r') {
        onRefresh();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Container(
      padding: const EdgeInsets.all(1),
      color: PatchTheme.bgBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: PatchTheme.textHi,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          // Owner-supplied status stays visible during loading so load-again
          // and retry feedback are not overwritten by a generic string.
          Text(message, style: const TextStyle(color: PatchTheme.text)),
          const SizedBox(height: 1),
          Text(
            loading ? 'r load again   q/Esc quit' : 'r retry   q/Esc quit',
            style: const TextStyle(color: PatchTheme.muted),
          ),
        ],
      ),
    ),
  );
}
