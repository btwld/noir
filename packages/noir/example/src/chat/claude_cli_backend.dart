import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// Launches the isolated process used by [ClaudeCliBackend].
abstract interface class ClaudeProcessLauncher {
  Future<ClaudeProcessHandle> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  });
}

/// Narrow owned-process seam used to keep ordinary tests off the network.
abstract interface class ClaudeProcessHandle {
  Stream<List<int>> get stdoutBytes;

  Stream<List<int>> get stderrBytes;

  Future<int> get exitCode;

  Future<void> writeLine(String line);

  Future<void> interrupt();

  Future<void> close({required Duration gracePeriod});
}

/// Injectable shape of [Process.start] used by the system launcher.
typedef ClaudeSystemProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// Production launcher for the installed Claude Code executable.
final class SystemClaudeProcessLauncher implements ClaudeProcessLauncher {
  const SystemClaudeProcessLauncher({ClaudeSystemProcessStarter? startProcess})
    : _startProcess = startProcess;

  final ClaudeSystemProcessStarter? _startProcess;

  @override
  Future<ClaudeProcessHandle> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    final process = await (_startProcess ?? Process.start)(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    return _SystemClaudeProcessHandle(process);
  }
}

final class _SystemClaudeProcessHandle implements ClaudeProcessHandle {
  _SystemClaudeProcessHandle(this._process);

  final Process _process;
  Future<void>? _closeFuture;
  var _stdinClosed = false;

  @override
  Stream<List<int>> get stdoutBytes => _process.stdout;

  @override
  Stream<List<int>> get stderrBytes => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> writeLine(String line) async {
    if (_stdinClosed) throw StateError('Claude process stdin is closed.');
    _process.stdin.writeln(line);
    await _process.stdin.flush();
  }

  @override
  Future<void> interrupt() async {
    if (!_process.kill(ProcessSignal.sigint)) {
      throw StateError('Claude process is no longer running.');
    }
  }

  @override
  Future<void> close({required Duration gracePeriod}) =>
      _closeFuture ??= _close(gracePeriod);

  Future<void> _close(Duration gracePeriod) async {
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> attempt(FutureOr<void> Function() action) async {
      try {
        await action();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    if (!_stdinClosed) {
      _stdinClosed = true;
      await attempt(() => _process.stdin.close().timeout(gracePeriod));
    }
    if (!await _waitForExit(gracePeriod)) {
      _process.kill();
      if (!await _waitForExit(gracePeriod)) {
        _process.kill(ProcessSignal.sigkill);
        await attempt(() async {
          await _process.exitCode.timeout(gracePeriod);
        });
      }
    }

    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  Future<bool> _waitForExit(Duration timeout) async {
    try {
      await _process.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }
}

/// Stateful, fail-closed translator for Claude Code stream-JSON records.
final class ClaudeStreamEventDecoder {
  String? _requestId;
  String? _messageId;
  var _fallbackId = 0;
  final Set<String> _finalTextBlocks = {};
  final Set<String> _startedTools = {};

  /// Associates subsequent request-scoped vendor records with [requestId].
  void beginRequest(String? requestId) {
    _requestId = requestId;
    _messageId = null;
    _finalTextBlocks.clear();
    _startedTools.clear();
  }

  /// Decodes one complete vendor JSONL record into zero or more domain events.
  List<AgentEvent> decodeLine(String line) {
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException catch (error) {
      return _malformed(
        AgentUnknownEvent(
          id: _nextId('malformed'),
          requestId: _requestId,
          originalType: 'malformed',
          payload: {'raw': line},
          diagnostic: 'Malformed Claude stream JSON: ${error.message}',
        ),
      );
    }
    if (decoded is! Map<Object?, Object?>) {
      return _malformed(
        AgentUnknownEvent(
          id: _nextId('malformed'),
          requestId: _requestId,
          originalType: 'malformed',
          payload: {'value': decoded},
          diagnostic: 'A Claude stream record must be a JSON object.',
        ),
      );
    }

    final payload = <String, Object?>{
      for (final entry in decoded.entries)
        if (entry.key case final String key) key: entry.value,
    };
    final type = payload['type'];
    if (type is! String) {
      return _malformed(_unknown(payload, 'malformed', 'Missing string type.'));
    }

    try {
      return switch (type) {
        'system' => _decodeSystem(payload),
        'stream_event' => _decodeStreamEvent(payload),
        'assistant' => _decodeAssistant(payload),
        'user' => _decodeUser(payload),
        'result' => _decodeResult(payload),
        'rate_limit_event' => const [],
        _ => [
          _unknown(payload, type, 'Unsupported Claude stream record type.'),
        ],
      };
    } on FormatException catch (error) {
      final diagnostic = 'Invalid Claude $type record: $error';
      final unknown = _unknown(payload, type, diagnostic);
      return _malformed(unknown);
    }
  }

  List<AgentEvent> _malformed(AgentUnknownEvent unknown) {
    final requestId = _requestId;
    if (requestId == null) return [unknown];
    return [
      unknown,
      AgentRequestFailedEvent(
        id: '${unknown.id}:failed',
        requestId: requestId,
        message: unknown.diagnostic,
      ),
    ];
  }

  List<AgentEvent> _decodeSystem(Map<String, Object?> payload) {
    final subtype = _requiredString(payload, 'subtype');
    return switch (subtype) {
      'init' => [
        AgentSessionEvent(
          id: _eventId(payload, 'session'),
          sessionId: _requiredString(payload, 'session_id'),
          model: _requiredString(payload, 'model'),
          permissionMode: _permissionMode(payload['permissionMode']),
        ),
      ],
      'api_retry' => _decodeRetry(payload),
      'status' => const [],
      _ => [
        _unknown(
          payload,
          'system/$subtype',
          'Unsupported Claude system record.',
        ),
      ],
    };
  }

  List<AgentEvent> _decodeRetry(Map<String, Object?> payload) {
    final requestId = _requiredRequestId();
    final attempt = _requiredInt(payload, 'attempt');
    final error = _retryMessage(payload['error']);
    final maxRetries = payload['max_retries'];
    if (maxRetries != null && maxRetries is! int) {
      throw const FormatException('max_retries must be an integer');
    }
    final suffix = maxRetries == null ? '' : ' of $maxRetries';
    return [
      AgentRetryEvent(
        id: _eventId(payload, 'retry'),
        requestId: requestId,
        attempt: attempt,
        message: '$error (attempt $attempt$suffix)',
      ),
    ];
  }

  List<AgentEvent> _decodeStreamEvent(Map<String, Object?> payload) {
    final event = _requiredMap(payload, 'event');
    final eventType = _requiredString(event, 'type');
    return switch (eventType) {
      'message_start' => _decodeMessageStart(event),
      'content_block_start' => _decodeBlockStart(payload, event),
      'content_block_delta' => _decodeBlockDelta(payload, event),
      'content_block_stop' || 'message_delta' || 'message_stop' => const [],
      _ => [
        _unknown(
          payload,
          'stream_event/$eventType',
          'Unsupported Claude protocol stream event.',
        ),
      ],
    };
  }

  List<AgentEvent> _decodeMessageStart(Map<String, Object?> event) {
    final message = _requiredMap(event, 'message');
    _messageId = _requiredString(message, 'id');
    return const [];
  }

  List<AgentEvent> _decodeBlockStart(
    Map<String, Object?> payload,
    Map<String, Object?> event,
  ) {
    final block = _requiredMap(event, 'content_block');
    final type = _requiredString(block, 'type');
    if (type == 'text' || type == 'tool_use') return const [];
    return [
      _unknown(
        payload,
        'content_block/$type',
        'Unsupported Claude content block.',
      ),
    ];
  }

  List<AgentEvent> _decodeBlockDelta(
    Map<String, Object?> payload,
    Map<String, Object?> event,
  ) {
    final delta = _requiredMap(event, 'delta');
    final type = _requiredString(delta, 'type');
    if (type == 'input_json_delta' ||
        type == 'thinking_delta' ||
        type == 'signature_delta') {
      return const [];
    }
    if (type != 'text_delta') {
      return [
        _unknown(
          payload,
          'content_delta/$type',
          'Unsupported Claude content delta.',
        ),
      ];
    }

    final requestId = _requiredRequestId();
    final messageId = _messageId;
    if (messageId == null) {
      throw const FormatException('text delta arrived before message_start');
    }
    final index = _requiredInt(event, 'index');
    return [
      AgentTextDeltaEvent(
        id: _eventId(payload, 'delta:$index'),
        requestId: requestId,
        blockId: '$messageId:$index',
        delta: _requiredString(delta, 'text'),
      ),
    ];
  }

  List<AgentEvent> _decodeAssistant(Map<String, Object?> payload) {
    final requestId = _requiredRequestId();
    final message = _requiredMap(payload, 'message');
    final messageId = _requiredString(message, 'id');
    _messageId = messageId;
    final content = _requiredList(message, 'content');
    final events = <AgentEvent>[];
    for (var index = 0; index < content.length; index++) {
      final rawBlock = content[index];
      if (rawBlock is! Map<Object?, Object?>) {
        throw FormatException('content[$index] must be an object');
      }
      final block = _stringMap(rawBlock);
      final type = _requiredString(block, 'type');
      switch (type) {
        case 'text':
          final blockId = '$messageId:$index';
          if (_finalTextBlocks.add(blockId)) {
            events.add(
              AgentTextFinalEvent(
                id: _eventId(payload, 'text:$index'),
                requestId: requestId,
                blockId: blockId,
                text: _requiredString(block, 'text'),
              ),
            );
          }
        case 'tool_use':
          final toolId = _requiredString(block, 'id');
          if (_startedTools.add(toolId)) {
            events.add(
              AgentToolStartedEvent(
                id: _eventId(payload, 'tool:$toolId'),
                requestId: requestId,
                blockId: toolId,
                name: _requiredString(block, 'name'),
                summary: _toolSummary(block['input']),
              ),
            );
          }
        case 'thinking' || 'redacted_thinking':
          break;
        default:
          events.add(
            _unknown(
              payload,
              'assistant/$type',
              'Unsupported Claude assistant content block.',
              suffix: '$index',
            ),
          );
      }
    }
    return events;
  }

  List<AgentEvent> _decodeUser(Map<String, Object?> payload) {
    final requestId = _requiredRequestId();
    final message = _requiredMap(payload, 'message');
    final content = _requiredList(message, 'content');
    final events = <AgentEvent>[];
    for (var index = 0; index < content.length; index++) {
      final rawBlock = content[index];
      if (rawBlock is! Map<Object?, Object?>) {
        throw FormatException('content[$index] must be an object');
      }
      final block = _stringMap(rawBlock);
      final type = _requiredString(block, 'type');
      if (type != 'tool_result') {
        events.add(
          _unknown(
            payload,
            'user/$type',
            'Unsupported Claude user content block.',
            suffix: '$index',
          ),
        );
        continue;
      }
      final isError = block['is_error'];
      if (isError != null && isError is! bool) {
        throw FormatException('content[$index].is_error must be a boolean');
      }
      final toolId = _requiredString(block, 'tool_use_id');
      events.add(
        AgentToolResultEvent(
          id: _eventId(payload, 'tool-result:$toolId'),
          requestId: requestId,
          blockId: toolId,
          output: _toolOutput(block['content']),
          isError: isError == true,
        ),
      );
    }
    return events;
  }

  List<AgentEvent> _decodeResult(Map<String, Object?> payload) {
    final requestId = _requiredRequestId();
    final subtype = _requiredString(payload, 'subtype');
    final isError = payload['is_error'];
    if (isError != null && isError is! bool) {
      throw const FormatException('is_error must be a boolean');
    }
    if (subtype == 'success' && isError != true) {
      final usage = _optionalMap(payload, 'usage');
      return [
        AgentRequestCompletedEvent(
          id: _eventId(payload, 'complete'),
          requestId: requestId,
          inputTokens:
              _optionalInt(usage, 'input_tokens') +
              _optionalInt(usage, 'cache_creation_input_tokens') +
              _optionalInt(usage, 'cache_read_input_tokens'),
          outputTokens: _optionalInt(usage, 'output_tokens'),
          costUsd: _optionalDouble(payload, 'total_cost_usd'),
        ),
      ];
    }

    final errors = _optionalStrings(payload, 'errors');
    final legacyResult = payload['result'];
    if (legacyResult != null && legacyResult is! String) {
      throw const FormatException('result must be a string');
    }
    final terminalReason = payload['terminal_reason'];
    if (terminalReason != null && terminalReason is! String) {
      throw const FormatException('terminal_reason must be a string');
    }
    final message = errors.isNotEmpty
        ? errors.join('\n')
        : legacyResult is String
        ? legacyResult
        : 'Claude request ended with $subtype.';
    // Classify from the protocol fields only. The free-text message may
    // describe a genuine failure using the word "cancel", and reading it here
    // would report that failure as a cancellation.
    final normalized = '$subtype ${terminalReason ?? ''}'.toLowerCase();
    if ((terminalReason is String && terminalReason.startsWith('aborted_')) ||
        normalized.contains('interrupt') ||
        normalized.contains('cancel')) {
      return [
        AgentRequestCancelledEvent(
          id: _eventId(payload, 'cancelled'),
          requestId: requestId,
          reason: message,
        ),
      ];
    }
    return [
      AgentRequestFailedEvent(
        id: _eventId(payload, 'failed'),
        requestId: requestId,
        message: message,
      ),
    ];
  }

  AgentUnknownEvent _unknown(
    Map<String, Object?> payload,
    String originalType,
    String diagnostic, {
    String? suffix,
  }) => AgentUnknownEvent(
    id: _eventId(payload, suffix ?? 'unknown'),
    requestId: _requestId,
    originalType: originalType,
    payload: payload,
    diagnostic: diagnostic,
  );

  String _eventId(Map<String, Object?> payload, String suffix) {
    final uuid = payload['uuid'];
    return '${uuid is String && uuid.isNotEmpty ? uuid : _nextId('event')}:$suffix';
  }

  String _nextId(String kind) => 'claude-$kind-${++_fallbackId}';

  String _requiredRequestId() {
    final requestId = _requestId;
    if (requestId == null) {
      throw const FormatException('request-scoped event arrived while idle');
    }
    return requestId;
  }

  static Map<String, Object?> _stringMap(Map<Object?, Object?> source) => {
    for (final entry in source.entries)
      if (entry.key case final String key) key: entry.value,
  };

  static Map<String, Object?> _requiredMap(
    Map<String, Object?> source,
    String key,
  ) {
    final value = source[key];
    if (value is Map<Object?, Object?>) return _stringMap(value);
    throw FormatException('$key must be an object');
  }

  static Map<String, Object?> _optionalMap(
    Map<String, Object?> source,
    String key,
  ) {
    final value = source[key];
    if (value == null) return const {};
    if (value is Map<Object?, Object?>) return _stringMap(value);
    throw FormatException('$key must be an object');
  }

  static List<Object?> _requiredList(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is List<Object?>) return value;
    throw FormatException('$key must be a list');
  }

  static String _requiredString(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is String) return value;
    throw FormatException('$key must be a string');
  }

  static int _requiredInt(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is int) return value;
    throw FormatException('$key must be an integer');
  }

  static int _optionalInt(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value == null) return 0;
    if (value is int) return value;
    throw FormatException('$key must be an integer');
  }

  static List<String> _optionalStrings(
    Map<String, Object?> source,
    String key,
  ) {
    final value = source[key];
    if (value == null) return const [];
    if (value is! List<Object?> || value.any((item) => item is! String)) {
      throw FormatException('$key must be a list of strings');
    }
    return value.cast<String>();
  }

  static double _optionalDouble(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    throw FormatException('$key must be numeric');
  }

  /// Names the CLI's permission mode in the semantic protocol.
  ///
  /// The adapter starts every session with `dontAsk`, so that is the value
  /// a live header shows. A mode this table does not name fails the decode
  /// rather than passing as a reviewing session.
  static AgentPermissionMode _permissionMode(Object? value) => switch (value) {
    'default' => AgentPermissionMode.review,
    'acceptEdits' => AgentPermissionMode.autoEdit,
    'plan' => AgentPermissionMode.plan,
    'dontAsk' => AgentPermissionMode.unattended,
    final String mode => throw FormatException(
      'unsupported permissionMode $mode',
    ),
    _ => throw const FormatException('permissionMode must be a string'),
  };

  static String _retryMessage(Object? value) {
    if (value is String) return value;
    if (value is Map<Object?, Object?>) {
      final error = _stringMap(value);
      final message = error['message'];
      if (message is String && message.isNotEmpty) return message;
      final formatted = error['formatted'];
      if (formatted is String && formatted.isNotEmpty) return formatted;
    }
    throw const FormatException(
      'error must be a string or an object with a message',
    );
  }

  static String _toolSummary(Object? input) {
    if (input == null) return 'requested';
    if (input is Map<Object?, Object?> && input.isEmpty) return 'requested';
    return jsonEncode(input);
  }

  static String _toolOutput(Object? content) {
    if (content is String) return content;
    if (content is List<Object?>) {
      final parts = <String>[];
      for (final item in content) {
        if (item is Map<Object?, Object?>) {
          final block = _stringMap(item);
          if (block['type'] == 'text' && block['text'] is String) {
            parts.add(block['text']! as String);
            continue;
          }
        }
        parts.add(jsonEncode(item));
      }
      return parts.join('\n');
    }
    return jsonEncode(content);
  }
}

/// Bounded live adapter validated against Claude Code 2.1.258 stream-JSON mode.
final class ClaudeCliBackend implements AgentBackend {
  ClaudeCliBackend({
    required this.workingDirectory,
    this.executable = 'claude',
    this.model = 'sonnet',
    this.maxBudgetUsd = 0.05,
    ClaudeProcessLauncher launcher = const SystemClaudeProcessLauncher(),
    this.shutdownGracePeriod = const Duration(seconds: 2),
    this.interruptTimeout = const Duration(seconds: 3),
  }) : _launcher = launcher {
    _validateConfiguration();
  }

  final String executable;
  final String workingDirectory;
  final String model;
  final double maxBudgetUsd;
  final Duration shutdownGracePeriod;
  final Duration interruptTimeout;
  final ClaudeProcessLauncher _launcher;
  final ClaudeStreamEventDecoder _decoder = ClaudeStreamEventDecoder();
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast(sync: true);
  final Set<_ClaudeProcessBinding> _ownedBindings = {};

  _ClaudeProcessBinding? _binding;
  Future<void>? _spawnFuture;
  Future<void>? _startFuture;
  Future<void>? _closeFuture;
  Completer<void>? _turnTerminal;
  String? _activeRequestId;
  Object? _lateSpawnCloseError;
  StackTrace? _lateSpawnCloseStackTrace;
  var _stderrSequence = 0;
  var _started = false;
  var _interruptPending = false;
  var _closed = false;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> start() {
    _requireOpen();
    return _startFuture ??= _start();
  }

  Future<void> _start() async {
    await _ensureProcess();
    _requireOpen();
    _started = true;
  }

  @override
  Future<void> send(AgentRequest request) async {
    _requireStarted();
    if (_activeRequestId != null) {
      if (!_interruptPending) {
        throw StateError('ClaudeCliBackend already has an active request.');
      }
      final interruptedTurn = _turnTerminal;
      if (interruptedTurn != null && !interruptedTurn.isCompleted) {
        await interruptedTurn.future;
      }
    }
    _requireOpen();
    if (_activeRequestId != null) {
      throw StateError('ClaudeCliBackend already has an active request.');
    }
    final terminal = Completer<void>();
    _activeRequestId = request.id;
    _turnTerminal = terminal;
    _decoder.beginRequest(request.id);
    _ClaudeProcessBinding? binding;
    Future<void>? write;
    try {
      await _ensureProcess();
      _requireOpen();
      if (!identical(_turnTerminal, terminal) ||
          _activeRequestId != request.id) {
        return;
      }
      final activeBinding = _binding;
      if (activeBinding == null) {
        throw StateError('Claude process exited before the request write.');
      }
      binding = activeBinding;
      write = activeBinding.process.writeLine(
        jsonEncode({
          'type': 'user',
          'message': {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': request.prompt},
            ],
          },
          'parent_tool_use_id': null,
        }),
      );
      activeBinding.pendingWrite = write;
      await write;
    } on Object {
      _finishTurn(terminal);
      rethrow;
    } finally {
      if (binding != null &&
          write != null &&
          identical(binding.pendingWrite, write)) {
        binding.pendingWrite = null;
      }
    }
  }

  @override
  Future<void> interrupt(String requestId) async {
    _requireStarted();
    if (_activeRequestId != requestId) return;
    final terminal = _turnTerminal;
    if (terminal == null) return;

    _interruptPending = true;
    final binding = _binding;
    if (binding == null) {
      _finishTurn(terminal);
      return;
    }
    binding
      ..expectedExit = true
      ..retireAfterTurn = true
      ..retirementRequestId = requestId;
    try {
      await binding.process.interrupt();
    } on Object catch (error, stackTrace) {
      _retireBinding(binding, requestId: requestId);
      _finishTurn(terminal);
      try {
        await _closeBinding(binding);
      } on Object {
        // Preserve the signal failure; cleanup is best-effort on this path.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    try {
      await terminal.future.timeout(interruptTimeout);
    } on TimeoutException {
      if (!identical(_binding, binding) || terminal.isCompleted) return;
      _retireBinding(binding, requestId: requestId);
      _finishTurn(terminal);
      await _closeBinding(binding);
    }
  }

  @override
  Future<void> respondToPermission({
    required String requestId,
    required String permissionId,
    required bool allow,
  }) => Future<void>.error(
    UnsupportedError(
      'Claude CLI mode does not expose live permission callbacks.',
    ),
  );

  @override
  Future<void> answerQuestion({
    required String requestId,
    required String questionId,
    required String answer,
  }) => Future<void>.error(
    UnsupportedError(
      'Claude CLI mode does not expose live AskUserQuestion callbacks.',
    ),
  );

  @override
  Future<void> setModel(String model) => Future<void>.error(
    UnsupportedError(
      'Changing models requires a new isolated Claude CLI backend.',
    ),
  );

  @override
  Future<void> setPermissionMode(
    AgentPermissionMode mode,
  ) => Future<void>.error(
    UnsupportedError(
      'Changing permission mode requires a new isolated Claude CLI backend.',
    ),
  );

  @override
  Future<List<AgentSessionSummary>> listSessions() async {
    _requireStarted();
    return const [];
  }

  @override
  Future<AgentSessionSnapshot> loadSession(
    String sessionId,
  ) => Future<AgentSessionSnapshot>.error(
    UnsupportedError(
      'Session persistence is disabled for the isolated Claude CLI backend.',
    ),
  );

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    Object? firstError;
    StackTrace? firstStackTrace;
    final pendingSpawn = _spawnFuture;
    if (pendingSpawn != null) {
      try {
        await pendingSpawn;
      } on Object {
        // Launcher failures own no process. A late handle cleanup records its
        // own error below so close remains an ownership barrier.
      }
    }
    if (_lateSpawnCloseError case final error?) {
      firstError = error;
      firstStackTrace = _lateSpawnCloseStackTrace;
    }

    _binding = null;
    final terminal = _turnTerminal;
    if (terminal != null) _finishTurn(terminal);

    for (final binding in _ownedBindings.toList()) {
      binding.expectedExit = true;
      try {
        await _closeBinding(binding);
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (!_events.isClosed) await _events.close();
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  Future<void> _ensureProcess() async {
    if (_binding != null) return;
    final pending = _spawnFuture;
    if (pending != null) return pending;

    final spawn = _spawn();
    _spawnFuture = spawn;
    try {
      await spawn;
    } finally {
      if (identical(_spawnFuture, spawn)) _spawnFuture = null;
    }
  }

  Future<void> _spawn() async {
    final process = await _launcher.start(
      executable,
      _arguments,
      workingDirectory: workingDirectory,
    );
    if (_closed) {
      try {
        await process.close(gracePeriod: shutdownGracePeriod);
      } on Object catch (error, stackTrace) {
        _lateSpawnCloseError = error;
        _lateSpawnCloseStackTrace = stackTrace;
        rethrow;
      }
      throw StateError('ClaudeCliBackend is closed.');
    }

    final binding = _ClaudeProcessBinding(process: process);
    _ownedBindings.add(binding);
    _binding = binding;
    try {
      binding.stdoutSubscription = process.stdoutBytes
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => _handleStdoutLine(binding, line),
            onError: (Object error, StackTrace stackTrace) {
              _handleStdoutError(binding, error);
            },
            onDone: () => _handleStdoutDone(binding),
          );
      binding.stderrSubscription = process.stderrBytes
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => _handleStderrLine(binding, line),
            onError: (Object error, StackTrace stackTrace) {
              if (identical(_binding, binding)) {
                _handleDrainError('stderr', error, requestId: _activeRequestId);
              }
            },
          );
    } on Object {
      binding.expectedExit = true;
      _binding = null;
      await _closeBinding(binding);
      rethrow;
    }
    unawaited(
      process.exitCode.then(
        (exitCode) => _handleProcessExit(binding, exitCode),
        onError: (Object error, StackTrace stackTrace) =>
            _handleExitError(binding, error),
      ),
    );
  }

  void _handleStdoutLine(_ClaudeProcessBinding binding, String line) {
    if (_closed || !identical(_binding, binding)) return;
    for (final event in _decoder.decodeLine(line)) {
      final requestId = event.requestId;
      if (requestId != null && requestId != _activeRequestId) continue;
      final isTerminal =
          event is AgentRequestCompletedEvent ||
          event is AgentRequestCancelledEvent ||
          event is AgentRequestFailedEvent;
      if (isTerminal) {
        if (binding.retireAfterTurn || event is AgentRequestFailedEvent) {
          _retireBinding(binding, requestId: requestId);
        }
        final terminal = _turnTerminal;
        if (terminal != null) _finishTurn(terminal);
      }
      _emit(event);
    }
  }

  void _handleStderrLine(_ClaudeProcessBinding binding, String line) {
    if (_closed || !identical(_binding, binding) || line.isEmpty) return;
    _emit(
      AgentStderrEvent(
        id: 'claude-stderr-${++_stderrSequence}',
        requestId: _activeRequestId,
        text: line,
      ),
    );
  }

  void _handleStdoutError(_ClaudeProcessBinding binding, Object error) {
    _handleStdoutFailure(binding, 'Claude stdout stream failed: $error');
  }

  void _handleStdoutDone(_ClaudeProcessBinding binding) {
    _handleStdoutFailure(binding, 'Claude stdout closed unexpectedly.');
  }

  void _handleStdoutFailure(_ClaudeProcessBinding binding, String message) {
    if (_closed || !identical(_binding, binding)) return;
    final requestId = _activeRequestId;
    final terminal = _turnTerminal;
    _retireBinding(binding, requestId: requestId);
    if (terminal != null) _finishTurn(terminal);
    if (requestId != null) {
      _emit(
        AgentRequestFailedEvent(
          id: 'claude-stdout-${++_stderrSequence}',
          requestId: requestId,
          message: message,
        ),
      );
    } else {
      _handleDrainError('stdout', message, requestId: null);
    }
  }

  void _handleDrainError(
    String stream,
    Object error, {
    required String? requestId,
  }) {
    if (_closed) return;
    _emit(
      AgentStderrEvent(
        id: 'claude-stderr-${++_stderrSequence}',
        requestId: requestId,
        text: '$stream stream failed: $error',
      ),
    );
  }

  Future<void> _handleProcessExit(
    _ClaudeProcessBinding binding,
    int exitCode,
  ) async {
    final wasCurrent = identical(_binding, binding);
    final requestId = wasCurrent
        ? _activeRequestId
        : binding.retirementRequestId;
    if (wasCurrent) {
      _binding = null;
      final terminal = _turnTerminal;
      if (terminal != null) _finishTurn(terminal);
    }
    if (wasCurrent && !_closed && !binding.expectedExit) {
      _emit(
        AgentProcessExitEvent(
          id: 'claude-exit-${++_stderrSequence}',
          exitCode: exitCode,
        ),
      );
    }
    try {
      await _closeBinding(binding);
    } on Object catch (error) {
      _handleDrainError('process cleanup', error, requestId: requestId);
    }
  }

  Future<void> _handleExitError(
    _ClaudeProcessBinding binding,
    Object error,
  ) async {
    final wasCurrent = identical(_binding, binding);
    final requestId = wasCurrent
        ? _activeRequestId
        : binding.retirementRequestId;
    if (wasCurrent) {
      _binding = null;
      final terminal = _turnTerminal;
      if (terminal != null) _finishTurn(terminal);
    }
    if (wasCurrent && !_closed && !binding.expectedExit) {
      if (requestId != null) {
        _emit(
          AgentRequestFailedEvent(
            id: 'claude-exit-${++_stderrSequence}',
            requestId: requestId,
            message: 'Claude exit status failed: $error',
          ),
        );
      } else {
        _handleDrainError('exit', error, requestId: null);
      }
    }
    try {
      await _closeBinding(binding);
    } on Object catch (closeError) {
      _handleDrainError('process cleanup', closeError, requestId: requestId);
    }
  }

  void _retireBinding(
    _ClaudeProcessBinding binding, {
    required String? requestId,
  }) {
    binding
      ..expectedExit = true
      ..retirementRequestId ??= requestId;
    if (identical(_binding, binding)) _binding = null;
    unawaited(
      _closeBinding(binding).catchError((Object error) {
        _handleDrainError(
          'process cleanup',
          error,
          requestId: binding.retirementRequestId,
        );
      }),
    );
  }

  Future<void> _closeBinding(_ClaudeProcessBinding binding) =>
      binding.closeFuture ??= _closeBindingOnce(binding);

  Future<void> _closeBindingOnce(_ClaudeProcessBinding binding) async {
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      final pendingWrite = binding.pendingWrite;
      if (pendingWrite != null) {
        try {
          await pendingWrite.timeout(shutdownGracePeriod);
        } on Object catch (error, stackTrace) {
          firstError = error;
          firstStackTrace = stackTrace;
        } finally {
          if (identical(binding.pendingWrite, pendingWrite)) {
            binding.pendingWrite = null;
          }
        }
      }
      try {
        await binding.process.close(gracePeriod: shutdownGracePeriod);
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      } finally {
        try {
          await binding.cancelSubscriptions();
        } on Object catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }
    } finally {
      _ownedBindings.remove(binding);
    }
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  void _finishTurn(Completer<void> terminal) {
    if (identical(_turnTerminal, terminal)) {
      _activeRequestId = null;
      _turnTerminal = null;
      _interruptPending = false;
    }
    if (!terminal.isCompleted) terminal.complete();
  }

  void _emit(AgentEvent event) {
    if (!_closed && !_events.isClosed) _events.add(event);
  }

  List<String> get _arguments => [
    '--safe-mode',
    '-p',
    '--input-format',
    'stream-json',
    '--output-format',
    'stream-json',
    '--verbose',
    '--include-partial-messages',
    '--disable-slash-commands',
    '--strict-mcp-config',
    '--mcp-config',
    '{"mcpServers":{}}',
    // This adapter exposes no permission channel: respondToPermission always
    // throws. Tools must therefore stay off, and no caller may turn them on.
    '--tools',
    '',
    '--permission-mode',
    'dontAsk',
    '--no-session-persistence',
    '--max-budget-usd',
    maxBudgetUsd.toString(),
    '--model',
    model,
  ];

  void _validateConfiguration() {
    if (executable.trim().isEmpty) {
      throw ArgumentError.value(executable, 'executable', 'must not be empty');
    }
    if (workingDirectory.trim().isEmpty) {
      throw ArgumentError.value(
        workingDirectory,
        'workingDirectory',
        'must not be empty',
      );
    }
    // A relative directory resolves against the caller's own project, which
    // is exactly the context this adapter must never hand to a live run.
    if (!workingDirectory.startsWith('/') &&
        !Directory(workingDirectory).isAbsolute) {
      throw ArgumentError.value(
        workingDirectory,
        'workingDirectory',
        'must be an absolute path',
      );
    }
    if (model.trim().isEmpty) {
      throw ArgumentError.value(model, 'model', 'must not be empty');
    }
    if (!maxBudgetUsd.isFinite || maxBudgetUsd <= 0) {
      throw ArgumentError.value(
        maxBudgetUsd,
        'maxBudgetUsd',
        'must be finite and greater than zero',
      );
    }
    if (shutdownGracePeriod <= Duration.zero) {
      throw ArgumentError.value(
        shutdownGracePeriod,
        'shutdownGracePeriod',
        'must be greater than zero',
      );
    }
    if (interruptTimeout <= Duration.zero) {
      throw ArgumentError.value(
        interruptTimeout,
        'interruptTimeout',
        'must be greater than zero',
      );
    }
  }

  void _requireStarted() {
    _requireOpen();
    if (!_started) throw StateError('ClaudeCliBackend has not started.');
  }

  void _requireOpen() {
    if (_closed) throw StateError('ClaudeCliBackend is closed.');
  }
}

final class _ClaudeProcessBinding {
  _ClaudeProcessBinding({required this.process});

  final ClaudeProcessHandle process;
  // Owned here and cancelled together by [cancelSubscriptions].
  // ignore: cancel_subscriptions
  StreamSubscription<String>? stdoutSubscription;
  // Owned here and cancelled together by [cancelSubscriptions].
  // ignore: cancel_subscriptions
  StreamSubscription<String>? stderrSubscription;
  bool expectedExit = false;
  bool retireAfterTurn = false;
  String? retirementRequestId;
  Future<void>? pendingWrite;
  Future<void>? _cancelFuture;
  Future<void>? closeFuture;

  Future<void> cancelSubscriptions() => _cancelFuture ??= _cancel();

  Future<void> _cancel() async {
    Object? firstError;
    StackTrace? firstStackTrace;
    final stdout = stdoutSubscription;
    stdoutSubscription = null;
    if (stdout != null) {
      try {
        await stdout.cancel();
      } on Object catch (error, stackTrace) {
        firstError = error;
        firstStackTrace = stackTrace;
      }
    }
    final stderr = stderrSubscription;
    stderrSubscription = null;
    if (stderr != null) {
      try {
        await stderr.cancel();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }
}
