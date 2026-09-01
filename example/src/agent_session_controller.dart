import 'dart:async';

import 'package:noir/noir.dart' show ChangeNotifier;

import 'agent_chat_protocol.dart';

enum AgentRunPhase {
  starting,
  idle,
  running,
  retrying,
  waitingPermission,
  waitingQuestion,
  loadingSession,
  failed,
  cancelled,
  closed,
}

enum AgentEntryKind { user, assistant, tool, notice, unknown }

enum AgentEntryStatus {
  complete,
  streaming,
  running,
  succeeded,
  failed,
  cancelled,
}

final class AgentTranscriptEntry {
  const AgentTranscriptEntry({
    required this.id,
    required this.kind,
    required this.status,
    required this.text,
    this.requestId,
    this.title = '',
    this.expanded = false,
    this.contentKind = AgentToolContentKind.plainText,
  });

  final String id;
  final String? requestId;
  final AgentEntryKind kind;
  final AgentEntryStatus status;
  final String title;
  final String text;
  final bool expanded;
  final AgentToolContentKind contentKind;

  AgentTranscriptEntry copyWith({
    AgentEntryStatus? status,
    String? title,
    String? text,
    bool? expanded,
    AgentToolContentKind? contentKind,
  }) => AgentTranscriptEntry(
    id: id,
    requestId: requestId,
    kind: kind,
    status: status ?? this.status,
    title: title ?? this.title,
    text: text ?? this.text,
    expanded: expanded ?? this.expanded,
    contentKind: contentKind ?? this.contentKind,
  );
}

final class AgentPermissionRequest {
  const AgentPermissionRequest({
    required this.requestId,
    required this.permissionId,
    required this.toolName,
    required this.reason,
    this.preview,
    this.previewContentKind = AgentToolContentKind.plainText,
  });

  final String requestId;
  final String permissionId;
  final String toolName;
  final String reason;
  final String? preview;
  final AgentToolContentKind previewContentKind;
}

final class AgentQuestionRequest {
  AgentQuestionRequest({
    required this.requestId,
    required this.questionId,
    required this.prompt,
    required List<String> choices,
    required this.allowFreeText,
  }) : choices = List<String>.unmodifiable(choices);

  final String requestId;
  final String questionId;
  final String prompt;
  final List<String> choices;
  final bool allowFreeText;
}

/// Pure session-state owner between a semantic backend and the widget tree.
final class AgentSessionController extends ChangeNotifier {
  AgentSessionController({required AgentBackend backend}) : _backend = backend;

  final AgentBackend _backend;
  final List<AgentTranscriptEntry> _entries = [];
  final Map<String, int> _blockIndexes = {};
  final Set<String> _seenEventIds = {};
  final Set<String> _terminalRequestIds = {};
  List<AgentSessionSummary> _sessions = const [];
  StreamSubscription<AgentEvent>? _subscription;
  Future<void>? _startFuture;
  Future<void>? _closeFuture;

  AgentRunPhase _phase = AgentRunPhase.starting;
  String? _activeRequestId;
  String _sessionId = 'local';
  String _model = 'sonnet';
  AgentPermissionMode _permissionMode = AgentPermissionMode.review;
  AgentPermissionRequest? _permissionRequest;
  AgentQuestionRequest? _questionRequest;
  String? _lastError;
  int _inputTokens = 0;
  int _outputTokens = 0;
  double _costUsd = 0;
  int _requestSequence = 0;
  int _noticeSequence = 0;
  int _ignoredEventCount = 0;
  int _sessionLoadGeneration = 0;
  int _snapshotPublicationGeneration = 0;
  int _modelChangeGeneration = 0;
  int _modeChangeGeneration = 0;
  bool _decisionInFlight = false;
  bool _sessionLoadInFlight = false;
  bool _closed = false;

  List<AgentTranscriptEntry> get entries =>
      List<AgentTranscriptEntry>.unmodifiable(_entries);

  List<AgentSessionSummary> get sessions => _sessions;

  AgentRunPhase get phase => _phase;
  String? get activeRequestId => _activeRequestId;
  String get sessionId => _sessionId;
  String get model => _model;
  AgentPermissionMode get permissionMode => _permissionMode;
  AgentPermissionRequest? get permissionRequest => _permissionRequest;
  AgentQuestionRequest? get questionRequest => _questionRequest;
  String? get lastError => _lastError;
  int get inputTokens => _inputTokens;
  int get outputTokens => _outputTokens;
  double get costUsd => _costUsd;
  int get ignoredEventCount => _ignoredEventCount;
  bool get decisionInFlight => _decisionInFlight;
  bool get isClosed => _closed;
  bool get isBusy => _activeRequestId != null;

  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    _requireOpen();
    _subscription = _backend.events.listen(
      _handleEvent,
      onError: _handleStreamError,
      onDone: _handleStreamDone,
    );
    try {
      await _backend.start();
      final sessions = await _backend.listSessions();
      if (_closed) return;
      _sessions = List<AgentSessionSummary>.unmodifiable(sessions);
      if (_activeRequestId == null && _phase == AgentRunPhase.starting) {
        _phase = AgentRunPhase.idle;
      }
      notifyListeners();
    } on Object catch (error) {
      if (_closed) return;
      _failBackend('Backend start failed: $error');
      notifyListeners();
    }
  }

  bool submit(String prompt) {
    _requireOpen();
    final normalized = prompt.trim();
    if (normalized.isEmpty ||
        _activeRequestId != null ||
        _sessionLoadInFlight) {
      return false;
    }
    final requestId = 'request-${++_requestSequence}';
    _activeRequestId = requestId;
    _permissionRequest = null;
    _questionRequest = null;
    _lastError = null;
    _phase = AgentRunPhase.running;
    _entries.add(
      AgentTranscriptEntry(
        id: 'user:$requestId',
        requestId: requestId,
        kind: AgentEntryKind.user,
        status: AgentEntryStatus.complete,
        text: normalized,
      ),
    );
    notifyListeners();
    unawaited(_send(AgentRequest(id: requestId, prompt: normalized)));
    return true;
  }

  Future<void> _send(AgentRequest request) async {
    try {
      await _backend.send(request);
    } on Object catch (error) {
      if (_closed || _activeRequestId != request.id) return;
      _failRequest(request.id, 'Send failed: $error');
      notifyListeners();
    }
  }

  Future<void> interrupt() async {
    _requireOpen();
    final requestId = _activeRequestId;
    if (requestId == null) return;
    _terminalRequestIds.add(requestId);
    _activeRequestId = null;
    _permissionRequest = null;
    _questionRequest = null;
    _decisionInFlight = false;
    _phase = AgentRunPhase.cancelled;
    _cancelRunningEntries(requestId);
    _appendNotice('Interrupted.', requestId: requestId);
    notifyListeners();
    final snapshotGeneration = _snapshotPublicationGeneration;
    try {
      await _backend.interrupt(requestId);
    } on Object catch (error) {
      if (_closed || snapshotGeneration != _snapshotPublicationGeneration) {
        return;
      }
      _lastError = 'Interrupt failed: $error';
      _appendNotice(_lastError!, failed: true);
      notifyListeners();
    }
  }

  Future<bool> respondToPermission({required bool allow}) async {
    _requireOpen();
    final request = _permissionRequest;
    if (request == null || _decisionInFlight) return false;
    _decisionInFlight = true;
    _lastError = null;
    notifyListeners();
    try {
      await _backend.respondToPermission(
        requestId: request.requestId,
        permissionId: request.permissionId,
        allow: allow,
      );
      if (_closed || !identical(_permissionRequest, request)) return false;
      _permissionRequest = null;
      _decisionInFlight = false;
      _phase = AgentRunPhase.running;
      notifyListeners();
      return true;
    } on Object catch (error) {
      if (_closed || !identical(_permissionRequest, request)) return false;
      _decisionInFlight = false;
      _lastError = 'Permission response failed: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> answerQuestion(String answer) async {
    _requireOpen();
    final request = _questionRequest;
    final normalized = answer.trim();
    if (request == null || _decisionInFlight || normalized.isEmpty) {
      return false;
    }
    _decisionInFlight = true;
    _lastError = null;
    notifyListeners();
    try {
      await _backend.answerQuestion(
        requestId: request.requestId,
        questionId: request.questionId,
        answer: normalized,
      );
      if (_closed || !identical(_questionRequest, request)) return false;
      _questionRequest = null;
      _decisionInFlight = false;
      _phase = AgentRunPhase.running;
      notifyListeners();
      return true;
    } on Object catch (error) {
      if (_closed || !identical(_questionRequest, request)) return false;
      _decisionInFlight = false;
      _lastError = 'Question response failed: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> selectModel(String model) async {
    _requireOpen();
    final generation = ++_modelChangeGeneration;
    if (model == _model) return true;
    try {
      await _backend.setModel(model);
      if (_closed || generation != _modelChangeGeneration) return false;
      _model = model;
      _lastError = null;
      notifyListeners();
      return true;
    } on Object catch (error) {
      if (_closed || generation != _modelChangeGeneration) return false;
      _lastError = 'Model change failed: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> cyclePermissionMode() async {
    final values = AgentPermissionMode.values;
    final next = values[(values.indexOf(_permissionMode) + 1) % values.length];
    return selectPermissionMode(next);
  }

  Future<bool> selectPermissionMode(AgentPermissionMode mode) async {
    _requireOpen();
    final generation = ++_modeChangeGeneration;
    if (mode == _permissionMode) return true;
    try {
      await _backend.setPermissionMode(mode);
      if (_closed || generation != _modeChangeGeneration) return false;
      _permissionMode = mode;
      _lastError = null;
      notifyListeners();
      return true;
    } on Object catch (error) {
      if (_closed || generation != _modeChangeGeneration) return false;
      _lastError = 'Mode change failed: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> loadSession(String sessionId) async {
    _requireOpen();
    if (_activeRequestId != null) return false;
    final generation = ++_sessionLoadGeneration;
    _sessionLoadInFlight = true;
    _phase = AgentRunPhase.loadingSession;
    _lastError = null;
    notifyListeners();
    try {
      final snapshot = await _backend.loadSession(sessionId);
      if (_closed || generation != _sessionLoadGeneration) return false;
      _applySnapshot(snapshot);
      _sessionLoadInFlight = false;
      _phase = AgentRunPhase.idle;
      notifyListeners();
      return true;
    } on Object catch (error) {
      if (_closed || generation != _sessionLoadGeneration) return false;
      _sessionLoadInFlight = false;
      _lastError = 'Session load failed: $error';
      _phase = AgentRunPhase.idle;
      notifyListeners();
      return false;
    }
  }

  bool toggleToolExpanded(String id) {
    final index = _entries.indexWhere(
      (entry) => entry.id == id && entry.kind == AgentEntryKind.tool,
    );
    if (index < 0) return false;
    final entry = _entries[index];
    _entries[index] = entry.copyWith(expanded: !entry.expanded);
    notifyListeners();
    return true;
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    _phase = AgentRunPhase.closed;
    _invalidateSessionLoad();
    _modelChangeGeneration++;
    _modeChangeGeneration++;
    notifyListeners();
    try {
      await _subscription?.cancel();
    } finally {
      try {
        await _backend.close();
      } finally {
        dispose();
      }
    }
  }

  void _handleEvent(AgentEvent event) {
    if (_closed) return;
    if (!_seenEventIds.add(event.id)) {
      _ignoredEventCount++;
      return;
    }
    final eventRequestId = event.requestId;
    if (eventRequestId != null && eventRequestId != _activeRequestId) {
      _ignoredEventCount++;
      return;
    }

    switch (event) {
      case AgentSessionEvent():
        _sessionId = event.sessionId;
        _model = event.model;
        _permissionMode = event.permissionMode;
      case AgentTextDeltaEvent():
        _applyTextDelta(event);
      case AgentTextFinalEvent():
        _applyTextFinal(event);
      case AgentToolStartedEvent():
        _applyToolStarted(event);
      case AgentToolProgressEvent():
        _applyToolProgress(event);
      case AgentToolResultEvent():
        _applyToolResult(event);
      case AgentRetryEvent():
        _phase = AgentRunPhase.retrying;
        _appendNotice(
          'Retry ${event.attempt}: ${event.message}',
          requestId: event.requestId,
        );
      case AgentPermissionRequestEvent():
        _permissionRequest = AgentPermissionRequest(
          requestId: event.requestId,
          permissionId: event.permissionId,
          toolName: event.toolName,
          reason: event.reason,
          preview: event.preview,
          previewContentKind: event.previewContentKind,
        );
        _phase = AgentRunPhase.waitingPermission;
      case AgentQuestionRequestEvent():
        _questionRequest = AgentQuestionRequest(
          requestId: event.requestId,
          questionId: event.questionId,
          prompt: event.prompt,
          choices: event.choices,
          allowFreeText: event.allowFreeText,
        );
        _phase = AgentRunPhase.waitingQuestion;
      case AgentRequestCompletedEvent():
        _completeRunningEntries(event.requestId);
        _finishRequest(event.requestId, AgentRunPhase.idle);
        _inputTokens += event.inputTokens;
        _outputTokens += event.outputTokens;
        _costUsd += event.costUsd;
      case AgentRequestCancelledEvent():
        _cancelRunningEntries(event.requestId);
        _appendNotice(event.reason, requestId: event.requestId);
        _finishRequest(event.requestId, AgentRunPhase.cancelled);
      case AgentRequestFailedEvent():
        _cancelRunningEntries(event.requestId, failed: true);
        _lastError = event.message;
        _appendNotice(event.message, requestId: event.requestId, failed: true);
        _finishRequest(event.requestId, AgentRunPhase.failed);
      case AgentStderrEvent():
        _appendNotice('Backend: ${event.text}', requestId: event.requestId);
      case AgentProcessExitEvent():
        _failBackend('Backend exited with status ${event.exitCode}.');
      case AgentUnknownEvent():
        _entries.add(
          AgentTranscriptEntry(
            id: 'unknown:${event.id}',
            requestId: event.requestId,
            kind: AgentEntryKind.unknown,
            status: AgentEntryStatus.failed,
            title: 'Unknown event · ${event.originalType}',
            text: '${event.diagnostic} ${event.originalType}',
          ),
        );
    }
    notifyListeners();
  }

  void _applyTextDelta(AgentTextDeltaEvent event) {
    final key = _blockKey(event.requestId, event.blockId);
    final index = _blockIndexes[key];
    if (index == null) {
      _blockIndexes[key] = _entries.length;
      _entries.add(
        AgentTranscriptEntry(
          id: key,
          requestId: event.requestId,
          kind: AgentEntryKind.assistant,
          status: AgentEntryStatus.streaming,
          text: event.delta,
        ),
      );
      return;
    }
    final current = _entries[index];
    if (current.status != AgentEntryStatus.streaming) {
      _ignoredEventCount++;
      return;
    }
    _entries[index] = current.copyWith(text: current.text + event.delta);
  }

  void _applyTextFinal(AgentTextFinalEvent event) {
    final key = _blockKey(event.requestId, event.blockId);
    final index = _blockIndexes[key];
    if (index == null) {
      _blockIndexes[key] = _entries.length;
      _entries.add(
        AgentTranscriptEntry(
          id: key,
          requestId: event.requestId,
          kind: AgentEntryKind.assistant,
          status: AgentEntryStatus.complete,
          text: event.text,
        ),
      );
      return;
    }
    final current = _entries[index];
    if (current.status != AgentEntryStatus.streaming) {
      _ignoredEventCount++;
      return;
    }
    _entries[index] = current.copyWith(
      status: AgentEntryStatus.complete,
      text: event.text,
    );
  }

  void _applyToolStarted(AgentToolStartedEvent event) {
    final key = _blockKey(event.requestId, event.blockId);
    if (_blockIndexes.containsKey(key)) {
      _ignoredEventCount++;
      return;
    }
    _blockIndexes[key] = _entries.length;
    _entries.add(
      AgentTranscriptEntry(
        id: key,
        requestId: event.requestId,
        kind: AgentEntryKind.tool,
        status: AgentEntryStatus.running,
        title: '${event.name} · ${event.summary}',
        text: event.summary,
      ),
    );
  }

  void _applyToolProgress(AgentToolProgressEvent event) {
    final index = _blockIndexes[_blockKey(event.requestId, event.blockId)];
    if (index == null || _entries[index].status != AgentEntryStatus.running) {
      _ignoredEventCount++;
      return;
    }
    _entries[index] = _entries[index].copyWith(text: event.message);
  }

  void _applyToolResult(AgentToolResultEvent event) {
    final index = _blockIndexes[_blockKey(event.requestId, event.blockId)];
    if (index == null || _entries[index].status != AgentEntryStatus.running) {
      _ignoredEventCount++;
      return;
    }
    _entries[index] = _entries[index].copyWith(
      status: event.isError
          ? AgentEntryStatus.failed
          : AgentEntryStatus.succeeded,
      text: event.output,
      contentKind: event.contentKind,
    );
  }

  void _finishRequest(String requestId, AgentRunPhase phase) {
    if (!_terminalRequestIds.add(requestId)) {
      _ignoredEventCount++;
      return;
    }
    _activeRequestId = null;
    _permissionRequest = null;
    _questionRequest = null;
    _decisionInFlight = false;
    _phase = phase;
  }

  void _cancelRunningEntries(String requestId, {bool failed = false}) {
    for (var index = 0; index < _entries.length; index++) {
      final entry = _entries[index];
      if (entry.requestId != requestId) continue;
      if (entry.status != AgentEntryStatus.streaming &&
          entry.status != AgentEntryStatus.running) {
        continue;
      }
      _entries[index] = entry.copyWith(
        status: failed ? AgentEntryStatus.failed : AgentEntryStatus.cancelled,
      );
    }
  }

  /// Closes the blocks a completed request left open.
  ///
  /// Streamed text is kept as the final answer. A tool that never reported a
  /// result is marked cancelled rather than succeeded: the run ended before
  /// the tool confirmed an outcome, and the transcript must not invent one.
  void _completeRunningEntries(String requestId) {
    for (var index = 0; index < _entries.length; index++) {
      final entry = _entries[index];
      if (entry.requestId != requestId) continue;
      final status = switch ((entry.kind, entry.status)) {
        (AgentEntryKind.assistant, AgentEntryStatus.streaming) =>
          AgentEntryStatus.complete,
        (AgentEntryKind.tool, AgentEntryStatus.running) =>
          AgentEntryStatus.cancelled,
        _ => null,
      };
      if (status != null) _entries[index] = entry.copyWith(status: status);
    }
  }

  void _applySnapshot(AgentSessionSnapshot snapshot) {
    _entries
      ..clear()
      ..addAll(snapshot.entries.map(_entryFromSnapshot));
    _blockIndexes.clear();
    _seenEventIds.clear();
    _terminalRequestIds.clear();
    _snapshotPublicationGeneration++;
    _modelChangeGeneration++;
    _modeChangeGeneration++;
    _activeRequestId = null;
    _permissionRequest = null;
    _questionRequest = null;
    _decisionInFlight = false;
    _sessionId = snapshot.sessionId;
    _model = snapshot.model;
    _permissionMode = snapshot.permissionMode;
    _inputTokens = snapshot.inputTokens;
    _outputTokens = snapshot.outputTokens;
    _costUsd = snapshot.costUsd;
    _lastError = null;
  }

  AgentTranscriptEntry _entryFromSnapshot(AgentSnapshotEntry entry) =>
      AgentTranscriptEntry(
        id: entry.id,
        kind: switch (entry.kind) {
          AgentSnapshotEntryKind.user => AgentEntryKind.user,
          AgentSnapshotEntryKind.assistant => AgentEntryKind.assistant,
          AgentSnapshotEntryKind.tool => AgentEntryKind.tool,
          AgentSnapshotEntryKind.notice => AgentEntryKind.notice,
        },
        status: entry.failed
            ? AgentEntryStatus.failed
            : entry.kind == AgentSnapshotEntryKind.tool
            ? AgentEntryStatus.succeeded
            : AgentEntryStatus.complete,
        title: entry.title,
        text: entry.text,
        contentKind: entry.contentKind,
      );

  void _appendNotice(String text, {String? requestId, bool failed = false}) {
    _entries.add(
      AgentTranscriptEntry(
        id: 'notice:${++_noticeSequence}',
        requestId: requestId,
        kind: AgentEntryKind.notice,
        status: failed ? AgentEntryStatus.failed : AgentEntryStatus.complete,
        text: text,
      ),
    );
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _failBackend('Backend stream failed: $error');
    notifyListeners();
  }

  void _handleStreamDone() {
    if (_closed) return;
    _failBackend('Backend event stream closed unexpectedly.');
    notifyListeners();
  }

  void _failBackend(String message) {
    _invalidateSessionLoad();
    final requestId = _activeRequestId;
    if (requestId != null) {
      _failRequest(requestId, message);
      return;
    }
    _activeRequestId = null;
    _permissionRequest = null;
    _questionRequest = null;
    _decisionInFlight = false;
    _lastError = message;
    _appendNotice(message, requestId: requestId, failed: true);
    _phase = AgentRunPhase.failed;
  }

  void _invalidateSessionLoad() {
    _sessionLoadGeneration++;
    _sessionLoadInFlight = false;
  }

  void _failRequest(String requestId, String message) {
    _cancelRunningEntries(requestId, failed: true);
    _terminalRequestIds.add(requestId);
    _activeRequestId = null;
    _permissionRequest = null;
    _questionRequest = null;
    _decisionInFlight = false;
    _lastError = message;
    _appendNotice(message, requestId: requestId, failed: true);
    _phase = AgentRunPhase.failed;
  }

  String _blockKey(String requestId, String blockId) =>
      'block:$requestId:$blockId';

  void _requireOpen() {
    if (_closed) throw StateError('AgentSessionController is closed.');
  }
}
