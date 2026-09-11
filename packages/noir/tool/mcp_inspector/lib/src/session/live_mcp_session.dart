import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:mcp_dart/mcp_dart.dart';

import 'mcp_session.dart';
import 'protocol_log.dart';
import 'tracing_transport.dart';

/// The client name this inspector reports in its MCP handshake.
const inspectorClientName = 'noir_mcp_inspector';

/// The client version this inspector reports in its MCP handshake.
const inspectorClientVersion = '0.1.0';

/// An [McpSession] backed by a live `package:mcp_dart` [McpClient].
///
/// The session owns the client, the transport decorator, and every stream it
/// publishes. It converts each SDK value into a value type from
/// `mcp_session.dart` before returning it, so the screen never sees an SDK
/// type.
final class LiveMcpSession implements McpSession {
  /// Connects to a server started as a child process over stdio.
  ///
  /// The child's standard error stream is captured rather than inherited, so
  /// the console pane can show it instead of corrupting the terminal frame.
  LiveMcpSession.stdio({
    required String command,
    List<String> args = const <String>[],
    McpProtocol protocol = McpProtocol.stable,
    this.captureSdkLogs = false,
  }) : _protocol = protocol,
       _transportFactory = (() => StdioClientTransport(
         StdioServerParameters(
           command: command,
           args: args,
           stderrMode: io.ProcessStartMode.normal,
         ),
       ));

  /// Connects to a server over Streamable HTTP at [url].
  LiveMcpSession.url(
    Uri url, {
    McpProtocol protocol = McpProtocol.stable,
    this.captureSdkLogs = false,
  }) : _protocol = protocol,
       _transportFactory = (() => StreamableHttpClientTransport(url));

  /// Connects over an already-built [transport].
  ///
  /// This is the seam the in-process protocol test uses to pair the session
  /// with an `McpServer` over [IOStreamTransport].
  LiveMcpSession.transport(
    Transport transport, {
    McpProtocol protocol = McpProtocol.stable,
    this.captureSdkLogs = false,
  }) : _protocol = protocol,
       _transportFactory = (() => transport);

  /// Whether [connect] routes mcp_dart diagnostics into [console].
  ///
  /// The SDK log handler is process-global and writes to standard error by
  /// default, which would corrupt a terminal frame. A hosted session sets this
  /// so the diagnostics land in the console pane instead. [close] restores the
  /// default handler.
  final bool captureSdkLogs;

  final McpProtocol _protocol;
  final Transport Function() _transportFactory;

  final StreamController<ProtocolEntry> _protocolEntries =
      StreamController<ProtocolEntry>.broadcast();
  final StreamController<String> _consoleLines =
      StreamController<String>.broadcast();
  final StreamController<ServerNotice> _serverNotices =
      StreamController<ServerNotice>.broadcast();

  McpClient? _client;
  StreamSubscription<String>? _stderrSubscription;
  bool _closed = false;

  @override
  ElicitationHandler? elicitationHandler;

  @override
  McpServerInfo? get serverInfo {
    final version = _client?.getServerVersion();
    if (version == null) return null;
    return McpServerInfo(
      name: version.name,
      version: version.version,
      title: version.title,
    );
  }

  @override
  String? get protocolVersion => _client?.getProtocolVersion();

  @override
  String? get instructions => _client?.getInstructions();

  @override
  Set<String> get capabilities {
    final advertised = _client?.getServerCapabilities();
    if (advertised == null) return const <String>{};
    return <String>{
      if (advertised.tools != null) 'tools',
      if (advertised.resources != null) 'resources',
      if (advertised.prompts != null) 'prompts',
      if (advertised.completions != null) 'completions',
      if (advertised.logging != null) 'logging',
      if (advertised.tasks != null) 'tasks',
    };
  }

  @override
  Stream<ProtocolEntry> get protocol => _protocolEntries.stream;

  @override
  Stream<String> get console => _consoleLines.stream;

  @override
  Stream<ServerNotice> get notices => _serverNotices.stream;

  @override
  Future<void> connect() async {
    if (_client != null) {
      throw const McpSessionException('The session is already connected.');
    }
    final client =
        McpClient(
            const Implementation(
              name: inspectorClientName,
              version: inspectorClientVersion,
            ),
            options: McpClientOptions(
              protocol: _protocol,
              // The mcp_dart CLI advertises sampling only. The inspector adds form
              // elicitation because answering a server-initiated input request from
              // a modal is the flow it exists to show.
              capabilities: const ClientCapabilities(
                sampling: ClientCapabilitiesSampling(),
                elicitation: ClientElicitation.formOnly(),
              ),
            ),
          )
          ..onElicitRequest = _handleElicitRequest
          ..fallbackNotificationHandler = _handleNotification;
    if (captureSdkLogs) {
      setMcpLogHandler((name, level, message) {
        if (!_consoleLines.isClosed) {
          _consoleLines.add('[${level.name}] $name: $message');
        }
      });
    }
    final inner = _transportFactory();
    final traced = TracingTransport(inner, onEntry: _record);
    _client = client;
    try {
      await client.connect(traced);
    } on Object catch (error) {
      _client = null;
      throw McpSessionException('Connect failed: $error');
    }
    if (inner is StdioClientTransport) {
      _listenToChildErrors(inner);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (captureSdkLogs) resetMcpLogHandler();
    await _stderrSubscription?.cancel();
    _stderrSubscription = null;
    final client = _client;
    _client = null;
    if (client != null) {
      try {
        await client.close();
      } on Object {
        // A transport that already failed cannot be closed twice. The session
        // still has to release its own streams below.
      }
    }
    await _protocolEntries.close();
    await _consoleLines.close();
    await _serverNotices.close();
  }

  @override
  Future<List<McpToolInfo>> listTools() async {
    final result = await _require().listTools();
    return <McpToolInfo>[
      for (final tool in result.tools)
        McpToolInfo(
          name: tool.name,
          form: FormSpec.fromJsonSchema(tool.inputSchema),
          title: tool.title,
          description: tool.description,
          schema: tool.inputSchema.toJson(),
        ),
    ];
  }

  @override
  Future<List<McpResourceInfo>> listResources() async {
    final result = await _require().listResources();
    return <McpResourceInfo>[
      for (final resource in result.resources)
        McpResourceInfo(
          uri: resource.uri,
          name: resource.name,
          title: resource.title,
          description: resource.description,
          mimeType: resource.mimeType,
        ),
    ];
  }

  @override
  Future<List<McpPromptInfo>> listPrompts() async {
    final result = await _require().listPrompts();
    return <McpPromptInfo>[
      for (final prompt in result.prompts)
        McpPromptInfo(
          name: prompt.name,
          form: FormSpec.fromPromptArguments(prompt.arguments),
          title: prompt.title,
          description: prompt.description,
        ),
    ];
  }

  @override
  Future<CallOutcome> callTool(
    String name,
    Map<String, Object?> arguments,
  ) => _timed(() async {
    final result = await _require().callTool(
      CallToolRequest(
        name: name,
        arguments: Map<String, dynamic>.of(arguments),
      ),
    );
    return (
      blocks: <String>[
        for (final content in result.content) renderContent(content),
        if (result.hasStructuredContent)
          'structuredContent: ${_encodeJson(result.structuredContentJson?.toJson())}',
      ],
      isError: result.isError,
    );
  });

  @override
  Future<CallOutcome> readResource(String uri) => _timed(() async {
    final result = await _require().readResource(ReadResourceRequest(uri: uri));
    return (
      blocks: <String>[
        for (final contents in result.contents)
          renderResourceContents(contents),
      ],
      isError: false,
    );
  });

  @override
  Future<CallOutcome> getPrompt(String name, Map<String, String> arguments) =>
      _timed(() async {
        final result = await _require().getPrompt(
          GetPromptRequest(
            name: name,
            arguments: Map<String, String>.of(arguments),
          ),
        );
        return (
          blocks: <String>[
            if (result.description != null) result.description!,
            for (final message in result.messages)
              '${message.role.name}: ${renderContent(message.content)}',
          ],
          isError: false,
        );
      });

  McpClient _require() {
    final client = _client;
    if (client == null) {
      throw const McpSessionException('The session is not connected.');
    }
    return client;
  }

  Future<CallOutcome> _timed(
    Future<({List<String> blocks, bool isError})> Function() request,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final result = await request();
      watch.stop();
      return CallOutcome(
        blocks: result.blocks,
        elapsed: watch.elapsed,
        isError: result.isError,
      );
    } on Object catch (error) {
      watch.stop();
      return CallOutcome.failure(_describe(error), watch.elapsed);
    }
  }

  void _record(ProtocolEntry entry) {
    if (_protocolEntries.isClosed) return;
    _protocolEntries.add(entry);
  }

  void _listenToChildErrors(StdioClientTransport transport) {
    final stderr = transport.stderr;
    if (stderr == null) return;
    _stderrSubscription = stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!_consoleLines.isClosed) _consoleLines.add(line);
        });
  }

  Future<ElicitResult> _handleElicitRequest(ElicitRequest request) async {
    final handler = elicitationHandler;
    if (handler == null) {
      return const ElicitResult(action: 'decline');
    }
    final outcome = await handler(
      ElicitationPrompt(
        message: request.message,
        form: FormSpec.fromJsonSchema(request.requestedSchema),
        url: request.url,
      ),
    );
    return switch (outcome.action) {
      ElicitationAction.accept => ElicitResult(
        action: 'accept',
        content: Map<String, dynamic>.of(outcome.content ?? const {}),
      ),
      ElicitationAction.decline => const ElicitResult(action: 'decline'),
      ElicitationAction.cancel => const ElicitResult(action: 'cancel'),
    };
  }

  Future<void> _handleNotification(JsonRpcNotification notification) async {
    if (_serverNotices.isClosed) return;
    _serverNotices.add(describeNotification(notification));
  }

  static String _describe(Object error) => switch (error) {
    McpSessionException() => error.message,
    McpError() => 'MCP error ${error.code}: ${error.message}',
    _ => '$error',
  };
}

/// Reduces [notification] to the notice the console pane shows.
ServerNotice describeNotification(JsonRpcNotification notification) {
  final method = notification.method;
  final kind = switch (method) {
    Method.notificationsToolsListChanged => ServerNoticeKind.toolsChanged,
    Method.notificationsResourcesListChanged =>
      ServerNoticeKind.resourcesChanged,
    Method.notificationsPromptsListChanged => ServerNoticeKind.promptsChanged,
    Method.notificationsResourcesUpdated => ServerNoticeKind.resourceUpdated,
    Method.notificationsMessage => ServerNoticeKind.message,
    _ => ServerNoticeKind.other,
  };
  final params = notification.params;
  final detail = switch (kind) {
    ServerNoticeKind.message => '${params?['data'] ?? ''}',
    ServerNoticeKind.resourceUpdated => '${params?['uri'] ?? ''}',
    _ => '',
  };
  return ServerNotice(
    kind: kind,
    method: method,
    summary: detail.isEmpty ? method : '$method $detail',
  );
}

/// Renders one MCP content block as the text the result view shows.
String renderContent(Content content) => switch (content) {
  TextContent() => content.text,
  ImageContent() => '[image ${content.mimeType}, ${content.data.length} bytes]',
  AudioContent() => '[audio ${content.mimeType}, ${content.data.length} bytes]',
  ResourceLink() => '[resource_link ${content.uri}]',
  EmbeddedResource() => renderResourceContents(content.resource),
  UnknownContent() => '[${content.type}]',
};

/// Renders one MCP resource body as the text the result view shows.
String renderResourceContents(ResourceContents contents) => switch (contents) {
  TextResourceContents() => contents.text,
  BlobResourceContents() =>
    '[blob ${contents.mimeType ?? 'application/octet-stream'}, '
        '${contents.blob.length} bytes]',
  UnknownResourceContents() => '[unknown contents ${contents.uri}]',
};

String _encodeJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);
