import 'dart:async';

import 'package:noir_mcp_inspector/noir_mcp_inspector.dart';

/// A scripted [McpSession] for tests that must not start a server.
///
/// The fake records what the screen asked for and lets a test push protocol
/// entries, console lines, notices, and elicitation requests by hand.
final class FakeMcpSession implements McpSession {
  /// Creates a fake that reports [serverInfo] once connected.
  FakeMcpSession({
    this.tools = const <McpToolInfo>[],
    this.resources = const <McpResourceInfo>[],
    this.prompts = const <McpPromptInfo>[],
  });

  /// Tools returned by [listTools].
  List<McpToolInfo> tools;

  /// Resources returned by [listResources].
  List<McpResourceInfo> resources;

  /// Prompts returned by [listPrompts].
  List<McpPromptInfo> prompts;

  /// Fails [connect] with this message when it is not null.
  String? connectFailure;

  /// The outcome every request returns.
  CallOutcome outcome = const CallOutcome(
    blocks: <String>['ok'],
    elapsed: Duration(milliseconds: 7),
  );

  /// Every `callTool` argument map, in call order.
  final List<({String name, Map<String, Object?> arguments})> toolCalls =
      <({String name, Map<String, Object?> arguments})>[];

  /// Every `readResource` URI, in call order.
  final List<String> resourceReads = <String>[];

  /// Every `getPrompt` argument map, in call order.
  final List<({String name, Map<String, String> arguments})> promptGets =
      <({String name, Map<String, String> arguments})>[];

  /// How many times [listTools] ran.
  int listToolsCount = 0;

  /// How many times [close] ran.
  int closeCount = 0;

  final StreamController<ProtocolEntry> _protocol =
      StreamController<ProtocolEntry>.broadcast();
  final StreamController<String> _console =
      StreamController<String>.broadcast();
  final StreamController<ServerNotice> _notices =
      StreamController<ServerNotice>.broadcast();

  bool _connected = false;

  @override
  ElicitationHandler? elicitationHandler;

  @override
  McpServerInfo? get serverInfo => _connected
      ? const McpServerInfo(name: 'fake_server', version: '1.0.0')
      : null;

  @override
  String? get protocolVersion => _connected ? '2026-07-28' : null;

  @override
  String? get instructions => _connected ? 'Fake instructions.' : null;

  @override
  Set<String> get capabilities =>
      _connected ? const <String>{'tools', 'resources', 'prompts'} : const {};

  @override
  Stream<ProtocolEntry> get protocol => _protocol.stream;

  @override
  Stream<String> get console => _console.stream;

  @override
  Stream<ServerNotice> get notices => _notices.stream;

  @override
  Future<void> connect() async {
    final failure = connectFailure;
    if (failure != null) throw McpSessionException(failure);
    _connected = true;
  }

  @override
  Future<void> close() async {
    closeCount++;
    _connected = false;
    await _protocol.close();
    await _console.close();
    await _notices.close();
  }

  @override
  Future<List<McpToolInfo>> listTools() async {
    listToolsCount++;
    return tools;
  }

  @override
  Future<List<McpResourceInfo>> listResources() async => resources;

  @override
  Future<List<McpPromptInfo>> listPrompts() async => prompts;

  @override
  Future<CallOutcome> callTool(
    String name,
    Map<String, Object?> arguments,
  ) async {
    toolCalls.add((name: name, arguments: arguments));
    return outcome;
  }

  @override
  Future<CallOutcome> readResource(String uri) async {
    resourceReads.add(uri);
    return outcome;
  }

  @override
  Future<CallOutcome> getPrompt(
    String name,
    Map<String, String> arguments,
  ) async {
    promptGets.add((name: name, arguments: arguments));
    return outcome;
  }

  /// Pushes [entry] onto the protocol stream.
  void emitProtocol(ProtocolEntry entry) => _protocol.add(entry);

  /// Pushes [line] onto the console stream.
  void emitConsole(String line) => _console.add(line);

  /// Pushes [notice] onto the notice stream.
  void emitNotice(ServerNotice notice) => _notices.add(notice);

  /// Asks the registered handler to answer [prompt], as a server would.
  Future<ElicitationOutcome> requestElicitation(ElicitationPrompt prompt) {
    final handler = elicitationHandler;
    if (handler == null) {
      throw StateError('No elicitation handler is registered.');
    }
    return handler(prompt);
  }
}
