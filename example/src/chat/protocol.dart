import 'dart:async';
import 'dart:convert';

/// Permission posture applied to subsequent agent requests.
/// How the agent treats an action that would need the user's approval.
///
/// `unattended` means the agent never asks: it proceeds without tools or
/// with a fixed allowance, so no permission request can arrive.
enum AgentPermissionMode { review, autoEdit, plan, unattended }

/// One user request sent to an [AgentBackend].
final class AgentRequest {
  const AgentRequest({required this.id, required this.prompt});

  final String id;
  final String prompt;
}

/// A session shown in the application-owned resume picker.
final class AgentSessionSummary {
  const AgentSessionSummary({
    required this.id,
    required this.title,
    required this.updatedLabel,
    this.parentId,
  });

  final String id;
  final String title;
  final String updatedLabel;
  final String? parentId;
}

/// Kind of one transcript item restored from a session snapshot.
enum AgentSnapshotEntryKind { user, assistant, tool, notice }

/// Semantic presentation for tool output supplied by an agent backend.
enum AgentToolContentKind { plainText, unifiedDiff }

/// One immutable transcript item in a loaded session snapshot.
final class AgentSnapshotEntry {
  const AgentSnapshotEntry({
    required this.id,
    required this.kind,
    required this.text,
    this.title = '',
    this.failed = false,
    this.contentKind = AgentToolContentKind.plainText,
  });

  final String id;
  final AgentSnapshotEntryKind kind;
  final String title;
  final String text;
  final bool failed;
  final AgentToolContentKind contentKind;
}

/// Complete state returned by an atomic session load.
final class AgentSessionSnapshot {
  AgentSessionSnapshot({
    required this.sessionId,
    required this.model,
    required this.permissionMode,
    required List<AgentSnapshotEntry> entries,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.costUsd = 0,
  }) : entries = List<AgentSnapshotEntry>.unmodifiable(entries);

  final String sessionId;
  final String model;
  final AgentPermissionMode permissionMode;
  final List<AgentSnapshotEntry> entries;
  final int inputTokens;
  final int outputTokens;
  final double costUsd;
}

/// Semantic event emitted by an [AgentBackend].
sealed class AgentEvent {
  const AgentEvent({required this.id});

  final String id;

  String? get requestId => null;
}

final class AgentSessionEvent extends AgentEvent {
  const AgentSessionEvent({
    required super.id,
    required this.sessionId,
    required this.model,
    required this.permissionMode,
  });

  final String sessionId;
  final String model;
  final AgentPermissionMode permissionMode;
}

final class AgentTextDeltaEvent extends AgentEvent {
  const AgentTextDeltaEvent({
    required super.id,
    required this.requestId,
    required this.blockId,
    required this.delta,
  });

  final String blockId;
  final String delta;
  @override
  final String requestId;
}

final class AgentTextFinalEvent extends AgentEvent {
  const AgentTextFinalEvent({
    required super.id,
    required this.requestId,
    required this.blockId,
    required this.text,
  });

  final String blockId;
  final String text;
  @override
  final String requestId;
}

final class AgentToolStartedEvent extends AgentEvent {
  const AgentToolStartedEvent({
    required super.id,
    required this.requestId,
    required this.blockId,
    required this.name,
    required this.summary,
  });

  final String blockId;
  final String name;
  final String summary;
  @override
  final String requestId;
}

final class AgentToolProgressEvent extends AgentEvent {
  const AgentToolProgressEvent({
    required super.id,
    required this.requestId,
    required this.blockId,
    required this.message,
  });

  final String blockId;
  final String message;
  @override
  final String requestId;
}

final class AgentToolResultEvent extends AgentEvent {
  const AgentToolResultEvent({
    required super.id,
    required this.requestId,
    required this.blockId,
    required this.output,
    this.isError = false,
    this.contentKind = AgentToolContentKind.plainText,
  });

  final String blockId;
  final String output;
  final bool isError;
  final AgentToolContentKind contentKind;
  @override
  final String requestId;
}

final class AgentRetryEvent extends AgentEvent {
  const AgentRetryEvent({
    required super.id,
    required this.requestId,
    required this.attempt,
    required this.message,
  });

  final int attempt;
  final String message;
  @override
  final String requestId;
}

final class AgentPermissionRequestEvent extends AgentEvent {
  const AgentPermissionRequestEvent({
    required super.id,
    required this.requestId,
    required this.permissionId,
    required this.toolName,
    required this.reason,
    this.preview,
    this.previewContentKind = AgentToolContentKind.plainText,
  });

  final String permissionId;
  final String toolName;
  final String reason;
  final String? preview;
  final AgentToolContentKind previewContentKind;
  @override
  final String requestId;
}

final class AgentQuestionRequestEvent extends AgentEvent {
  AgentQuestionRequestEvent({
    required super.id,
    required this.requestId,
    required this.questionId,
    required this.prompt,
    required List<String> choices,
    this.allowFreeText = false,
  }) : choices = List<String>.unmodifiable(choices);

  final String questionId;
  final String prompt;
  final List<String> choices;
  final bool allowFreeText;
  @override
  final String requestId;
}

final class AgentRequestCompletedEvent extends AgentEvent {
  const AgentRequestCompletedEvent({
    required super.id,
    required this.requestId,
    required this.inputTokens,
    required this.outputTokens,
    required this.costUsd,
  });

  final int inputTokens;
  final int outputTokens;
  final double costUsd;
  @override
  final String requestId;
}

final class AgentRequestCancelledEvent extends AgentEvent {
  const AgentRequestCancelledEvent({
    required super.id,
    required this.requestId,
    required this.reason,
  });

  final String reason;
  @override
  final String requestId;
}

final class AgentRequestFailedEvent extends AgentEvent {
  const AgentRequestFailedEvent({
    required super.id,
    required this.requestId,
    required this.message,
  });

  final String message;
  @override
  final String requestId;
}

final class AgentStderrEvent extends AgentEvent {
  const AgentStderrEvent({
    required super.id,
    required this.text,
    this.requestId,
  });

  final String text;
  @override
  final String? requestId;
}

final class AgentProcessExitEvent extends AgentEvent {
  const AgentProcessExitEvent({required super.id, required this.exitCode});

  final int exitCode;
}

/// Retains a malformed or unsupported normalized event for diagnostics.
final class AgentUnknownEvent extends AgentEvent {
  AgentUnknownEvent({
    required super.id,
    required this.originalType,
    required Map<String, Object?> payload,
    required this.diagnostic,
    this.requestId,
  }) : payload = Map<String, Object?>.unmodifiable(payload);

  final String originalType;
  final Map<String, Object?> payload;
  final String diagnostic;
  @override
  final String? requestId;
}

/// Fail-closed decoder for the original normalized replay JSONL format.
abstract final class AgentEventCodec {
  static AgentEvent decodeLine(String line) {
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException catch (error) {
      return AgentUnknownEvent(
        id: 'malformed:$line',
        originalType: 'malformed',
        payload: {'raw': line},
        diagnostic: 'Malformed JSON: ${error.message}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      return AgentUnknownEvent(
        id: 'malformed:${jsonEncode(decoded)}',
        originalType: 'malformed',
        payload: {'value': decoded},
        diagnostic: 'A normalized event must be a JSON object.',
      );
    }

    final type = decoded['type'];
    final originalType = type is String ? type : 'malformed';
    try {
      return switch (originalType) {
        'session' => AgentSessionEvent(
          id: _requiredString(decoded, 'id'),
          sessionId: _requiredString(decoded, 'sessionId'),
          model: _requiredString(decoded, 'model'),
          permissionMode: _permissionMode(
            _requiredString(decoded, 'permissionMode'),
          ),
        ),
        'text_delta' => AgentTextDeltaEvent(
          id: _requiredString(decoded, 'id'),
          requestId: _requiredString(decoded, 'requestId'),
          blockId: _requiredString(decoded, 'blockId'),
          delta: _requiredString(decoded, 'delta'),
        ),
        'text_final' => AgentTextFinalEvent(
          id: _requiredString(decoded, 'id'),
          requestId: _requiredString(decoded, 'requestId'),
          blockId: _requiredString(decoded, 'blockId'),
          text: _requiredString(decoded, 'text'),
        ),
        'tool_start' => AgentToolStartedEvent(
          id: _requiredString(decoded, 'id'),
          requestId: _requiredString(decoded, 'requestId'),
          blockId: _requiredString(decoded, 'blockId'),
          name: _requiredString(decoded, 'name'),
          summary: _requiredString(decoded, 'summary'),
        ),
        'tool_progress' => AgentToolProgressEvent(
          id: _requiredString(decoded, 'id'),
          requestId: _requiredString(decoded, 'requestId'),
          blockId: _requiredString(decoded, 'blockId'),
          message: _requiredString(decoded, 'message'),
        ),
        'tool_result' => AgentToolResultEvent(
          id: _requiredString(decoded, 'id'),
          requestId: _requiredString(decoded, 'requestId'),
          blockId: _requiredString(decoded, 'blockId'),
          output: _requiredString(decoded, 'output'),
          isError: _requiredBool(decoded, 'isError'),
          contentKind: _toolContentKind(decoded['contentKind']),
        ),
        'retry' => AgentRetryEvent(
          id: _requiredString(decoded, 'id'),
          requestId: _requiredString(decoded, 'requestId'),
          attempt: _requiredInt(decoded, 'attempt'),
          message: _requiredString(decoded, 'message'),
        ),
        'permission' => AgentPermissionRequestEvent(
          id: _requiredString(decoded, 'id'),
          requestId: _requiredString(decoded, 'requestId'),
          permissionId: _requiredString(decoded, 'permissionId'),
          toolName: _requiredString(decoded, 'toolName'),
          reason: _requiredString(decoded, 'reason'),
          preview: _optionalString(decoded, 'preview'),
          previewContentKind: _toolContentKind(decoded['previewContentKind']),
        ),
        'question' => AgentQuestionRequestEvent(
          id: _requiredString(decoded, 'id'),
          requestId: _requiredString(decoded, 'requestId'),
          questionId: _requiredString(decoded, 'questionId'),
          prompt: _requiredString(decoded, 'prompt'),
          choices: _stringList(decoded, 'choices'),
          allowFreeText: _requiredBool(decoded, 'allowFreeText'),
        ),
        'request_complete' => AgentRequestCompletedEvent(
          id: _requiredString(decoded, 'id'),
          requestId: _requiredString(decoded, 'requestId'),
          inputTokens: _requiredInt(decoded, 'inputTokens'),
          outputTokens: _requiredInt(decoded, 'outputTokens'),
          costUsd: _requiredDouble(decoded, 'costUsd'),
        ),
        'request_cancelled' => AgentRequestCancelledEvent(
          id: _requiredString(decoded, 'id'),
          requestId: _requiredString(decoded, 'requestId'),
          reason: _requiredString(decoded, 'reason'),
        ),
        'request_failed' => AgentRequestFailedEvent(
          id: _requiredString(decoded, 'id'),
          requestId: _requiredString(decoded, 'requestId'),
          message: _requiredString(decoded, 'message'),
        ),
        'stderr' => AgentStderrEvent(
          id: _requiredString(decoded, 'id'),
          requestId: decoded['requestId'] as String?,
          text: _requiredString(decoded, 'text'),
        ),
        'process_exit' => AgentProcessExitEvent(
          id: _requiredString(decoded, 'id'),
          exitCode: _requiredInt(decoded, 'exitCode'),
        ),
        _ => AgentUnknownEvent(
          id: decoded['id'] is String
              ? decoded['id']! as String
              : 'unknown:${jsonEncode(decoded)}',
          requestId: decoded['requestId'] as String?,
          originalType: originalType,
          payload: decoded,
          diagnostic: 'Unsupported normalized event type.',
        ),
      };
    } on Object catch (error) {
      return AgentUnknownEvent(
        id: decoded['id'] is String
            ? decoded['id']! as String
            : 'malformed:${jsonEncode(decoded)}',
        requestId: decoded['requestId'] is String
            ? decoded['requestId']! as String
            : null,
        originalType: originalType,
        payload: decoded,
        diagnostic: 'Invalid $originalType event: $error',
      );
    }
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is String) return value;
    throw FormatException('$key must be a string');
  }

  static String? _optionalString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null || value is String) return value as String?;
    throw FormatException('$key must be a string when present');
  }

  static int _requiredInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is int) return value;
    throw FormatException('$key must be an integer');
  }

  static double _requiredDouble(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is num) return value.toDouble();
    throw FormatException('$key must be numeric');
  }

  static bool _requiredBool(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is bool) return value;
    throw FormatException('$key must be a boolean');
  }

  static List<String> _stringList(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is List<Object?> && value.every((item) => item is String)) {
      return value.cast<String>();
    }
    throw FormatException('$key must be a string list');
  }

  static AgentPermissionMode _permissionMode(String value) => switch (value) {
    'review' => AgentPermissionMode.review,
    'auto_edit' => AgentPermissionMode.autoEdit,
    'plan' => AgentPermissionMode.plan,
    'unattended' => AgentPermissionMode.unattended,
    _ => throw FormatException('unsupported permissionMode $value'),
  };

  static AgentToolContentKind _toolContentKind(Object? value) =>
      switch (value) {
        null || 'text' => AgentToolContentKind.plainText,
        'unified_diff' => AgentToolContentKind.unifiedDiff,
        _ => throw FormatException('unsupported tool content kind $value'),
      };
}

/// Commands retained by [ReplayAgentBackend] for behavioral assertions.
enum AgentBackendCommandKind {
  start,
  send,
  interrupt,
  permission,
  answer,
  setModel,
  setPermissionMode,
  listSessions,
  loadSession,
  close,
}

final class AgentBackendCommand {
  const AgentBackendCommand({
    required this.kind,
    this.requestId,
    this.targetId,
    this.value,
    this.allowed,
  });

  final AgentBackendCommandKind kind;
  final String? requestId;
  final String? targetId;
  final String? value;
  final bool? allowed;
}

/// Product-neutral semantic boundary implemented by replay or live adapters.
abstract interface class AgentBackend {
  Stream<AgentEvent> get events;

  Future<void> start();

  Future<void> send(AgentRequest request);

  Future<void> interrupt(String requestId);

  Future<void> respondToPermission({
    required String requestId,
    required String permissionId,
    required bool allow,
  });

  Future<void> answerQuestion({
    required String requestId,
    required String questionId,
    required String answer,
  });

  Future<void> setModel(String model);

  Future<void> setPermissionMode(AgentPermissionMode mode);

  Future<List<AgentSessionSummary>> listSessions();

  Future<AgentSessionSnapshot> loadSession(String sessionId);

  Future<void> close();
}

typedef AgentReplayEventBuilder = AgentEvent Function(String requestId);

/// One delayed semantic event in a replay script.
final class AgentReplayStep {
  AgentReplayStep(this.delay, AgentEvent event) : _build = ((_) => event) {
    _requireNonNegativeDelay(delay);
  }

  AgentReplayStep.forRequest(this.delay, AgentReplayEventBuilder build)
    : _build = build {
    _requireNonNegativeDelay(delay);
  }

  final Duration delay;
  final AgentReplayEventBuilder _build;

  AgentEvent build(String requestId) => _build(requestId);

  static void _requireNonNegativeDelay(Duration delay) {
    if (delay.isNegative) {
      throw ArgumentError.value(delay, 'delay', 'must not be negative');
    }
  }
}

typedef ReplayCommandHandler = FutureOr<void> Function(AgentBackendCommand);
typedef ReplaySessionLoader = FutureOr<AgentSessionSnapshot> Function(String);

/// Deterministic backend used by ordinary application tests and goldens.
final class ReplayAgentBackend implements AgentBackend {
  ReplayAgentBackend({
    Map<String, List<AgentReplayStep>> scripts = const {},
    List<AgentReplayStep> fallbackScript = const [],
    List<AgentEvent> initialEvents = const [],
    List<AgentSessionSummary> sessions = const [],
    Map<String, AgentSessionSnapshot> snapshots = const {},
    this.onCommand,
    this.onLoadSession,
  }) : _scripts = Map<String, List<AgentReplayStep>>.unmodifiable({
         for (final entry in scripts.entries)
           entry.key: List<AgentReplayStep>.unmodifiable(entry.value),
       }),
       _fallbackScript = List<AgentReplayStep>.unmodifiable(fallbackScript),
       _initialEvents = List<AgentEvent>.unmodifiable(initialEvents),
       _sessions = List<AgentSessionSummary>.unmodifiable(sessions),
       _snapshots = Map<String, AgentSessionSnapshot>.unmodifiable(snapshots);

  final Map<String, List<AgentReplayStep>> _scripts;
  final List<AgentReplayStep> _fallbackScript;
  final List<AgentEvent> _initialEvents;
  final List<AgentSessionSummary> _sessions;
  final Map<String, AgentSessionSnapshot> _snapshots;
  final ReplayCommandHandler? onCommand;
  final ReplaySessionLoader? onLoadSession;
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast(sync: true);
  final List<AgentBackendCommand> _commands = [];
  final List<Timer> _timers = [];
  var _started = false;
  var _closed = false;

  List<AgentBackendCommand> get commands =>
      List<AgentBackendCommand>.unmodifiable(_commands);

  /// Whether [close] has completed its synchronous ownership transition.
  bool get isClosed => _closed;

  @override
  Stream<AgentEvent> get events => _events.stream;

  void emit(AgentEvent event) {
    _requireOpen();
    _requireEventStreamOpen();
    _events.add(event);
  }

  void emitError(Object error, [StackTrace? stackTrace]) {
    _requireOpen();
    _requireEventStreamOpen();
    _events.addError(error, stackTrace);
  }

  Future<void> finishEvents() async {
    _requireOpen();
    if (!_events.isClosed) await _events.close();
  }

  @override
  Future<void> start() async {
    _requireOpen();
    if (_started) return;
    _started = true;
    await _record(
      const AgentBackendCommand(kind: AgentBackendCommandKind.start),
    );
    for (final event in _initialEvents) {
      emit(event);
    }
  }

  @override
  Future<void> send(AgentRequest request) async {
    _requireStarted();
    await _record(
      AgentBackendCommand(
        kind: AgentBackendCommandKind.send,
        requestId: request.id,
        value: request.prompt,
      ),
    );
    var elapsed = Duration.zero;
    for (final step in _scripts[request.prompt] ?? _fallbackScript) {
      elapsed += step.delay;
      late final Timer timer;
      timer = Timer(elapsed, () {
        _timers.remove(timer);
        if (!_closed && !_events.isClosed) emit(step.build(request.id));
      });
      _timers.add(timer);
    }
  }

  @override
  Future<void> interrupt(String requestId) => _record(
    AgentBackendCommand(
      kind: AgentBackendCommandKind.interrupt,
      requestId: requestId,
    ),
  );

  @override
  Future<void> respondToPermission({
    required String requestId,
    required String permissionId,
    required bool allow,
  }) => _record(
    AgentBackendCommand(
      kind: AgentBackendCommandKind.permission,
      requestId: requestId,
      targetId: permissionId,
      allowed: allow,
    ),
  );

  @override
  Future<void> answerQuestion({
    required String requestId,
    required String questionId,
    required String answer,
  }) => _record(
    AgentBackendCommand(
      kind: AgentBackendCommandKind.answer,
      requestId: requestId,
      targetId: questionId,
      value: answer,
    ),
  );

  @override
  Future<void> setModel(String model) => _record(
    AgentBackendCommand(kind: AgentBackendCommandKind.setModel, value: model),
  );

  @override
  Future<void> setPermissionMode(AgentPermissionMode mode) => _record(
    AgentBackendCommand(
      kind: AgentBackendCommandKind.setPermissionMode,
      value: mode.name,
    ),
  );

  @override
  Future<List<AgentSessionSummary>> listSessions() async {
    await _record(
      const AgentBackendCommand(kind: AgentBackendCommandKind.listSessions),
    );
    return _sessions;
  }

  @override
  Future<AgentSessionSnapshot> loadSession(String sessionId) async {
    await _record(
      AgentBackendCommand(
        kind: AgentBackendCommandKind.loadSession,
        value: sessionId,
      ),
    );
    final loader = onLoadSession;
    if (loader != null) return loader(sessionId);
    final snapshot = _snapshots[sessionId];
    if (snapshot == null) {
      throw StateError('No replay snapshot for session $sessionId.');
    }
    return snapshot;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final timer in List<Timer>.of(_timers)) {
      timer.cancel();
    }
    _timers.clear();
    _commands.add(
      const AgentBackendCommand(kind: AgentBackendCommandKind.close),
    );
    if (!_events.isClosed) await _events.close();
  }

  Future<void> _record(AgentBackendCommand command) async {
    _requireOpen();
    _commands.add(command);
    await onCommand?.call(command);
    _requireOpen();
  }

  void _requireStarted() {
    _requireOpen();
    if (!_started) throw StateError('ReplayAgentBackend has not started.');
  }

  void _requireOpen() {
    if (_closed) throw StateError('ReplayAgentBackend is closed.');
  }

  void _requireEventStreamOpen() {
    if (_events.isClosed) {
      throw StateError('ReplayAgentBackend event stream is closed.');
    }
  }
}
