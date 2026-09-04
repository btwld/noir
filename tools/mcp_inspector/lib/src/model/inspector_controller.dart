import 'dart:async';

import 'package:noir/noir.dart';

import '../session/mcp_session.dart';
import '../session/protocol_log.dart';
import 'form_model.dart';

/// Greatest number of console lines the controller retains.
const consoleLineLimit = 500;

/// The five panes the inspector presents.
enum InspectorTab {
  /// The server's tools.
  tools,

  /// The server's resources.
  resources,

  /// The server's prompts.
  prompts,

  /// The recorded JSON-RPC traffic.
  protocol,

  /// The server's standard error output and notifications.
  console,
}

/// Where the session stands.
enum InspectorConnectionState {
  /// The handshake is in progress.
  connecting,

  /// The handshake succeeded and the inventory is loaded.
  connected,

  /// The handshake or the first inventory load failed.
  failed,

  /// The session is closed.
  closed,
}

/// One server-initiated input request awaiting the user's answer.
final class PendingElicitation {
  /// Creates a pending request over [prompt].
  PendingElicitation(this.prompt) : form = FormModel(prompt.form);

  /// What the server asked for.
  final ElicitationPrompt prompt;

  /// The editable form generated from the requested schema.
  final FormModel form;

  final Completer<ElicitationOutcome> _completer =
      Completer<ElicitationOutcome>();

  /// Completes when the user answers.
  Future<ElicitationOutcome> get future => _completer.future;

  /// Whether the user has already answered.
  bool get isResolved => _completer.isCompleted;

  /// Answers the request with [outcome]; a second call is a no-op.
  void resolve(ElicitationOutcome outcome) {
    if (_completer.isCompleted) return;
    _completer.complete(outcome);
  }
}

/// Owns every piece of inspector state the screen reads.
///
/// The controller is the only listener on the session's streams. The screen
/// listens to the controller, exactly as `example/src/chat/app.dart` listens to
/// its session controller and opens a modal from the notification.
final class InspectorController extends ChangeNotifier {
  /// Creates a controller over [session] and installs the elicitation handler.
  InspectorController({required this.session}) {
    session.elicitationHandler = _handleElicitation;
  }

  /// The boundary this controller drives.
  final McpSession session;

  final ProtocolLog _protocolLog = ProtocolLog();
  final List<String> _consoleLines = <String>[];
  final Map<InspectorTab, int> _selection = <InspectorTab, int>{
    for (final tab in InspectorTab.values) tab: 0,
  };
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  List<McpToolInfo> _tools = const <McpToolInfo>[];
  List<McpResourceInfo> _resources = const <McpResourceInfo>[];
  List<McpPromptInfo> _prompts = const <McpPromptInfo>[];
  InspectorConnectionState _connectionState =
      InspectorConnectionState.connecting;
  InspectorTab _activeTab = InspectorTab.tools;
  FormModel? _form;
  CallOutcome? _outcome;
  PendingElicitation? _pendingElicitation;
  String? _errorMessage;
  bool _isRunning = false;
  bool _closed = false;

  /// Where the session stands.
  InspectorConnectionState get connectionState => _connectionState;

  /// Identity of the connected server, or null before the handshake.
  McpServerInfo? get serverInfo => session.serverInfo;

  /// The negotiated MCP protocol version, or null before the handshake.
  String? get protocolVersion => session.protocolVersion;

  /// The capability names the server advertised.
  Set<String> get capabilities => session.capabilities;

  /// The server's usage instructions, when it supplies them.
  String? get instructions => session.instructions;

  /// Why the session failed, when it did.
  String? get errorMessage => _errorMessage;

  /// The pane the user is looking at.
  InspectorTab get activeTab => _activeTab;

  /// The server's tools, empty until the inventory loads.
  List<McpToolInfo> get tools => List<McpToolInfo>.unmodifiable(_tools);

  /// The server's resources, empty until the inventory loads.
  List<McpResourceInfo> get resources =>
      List<McpResourceInfo>.unmodifiable(_resources);

  /// The server's prompts, empty until the inventory loads.
  List<McpPromptInfo> get prompts => List<McpPromptInfo>.unmodifiable(_prompts);

  /// The recorded JSON-RPC traffic, oldest first.
  List<ProtocolEntry> get protocolEntries => _protocolLog.entries;

  /// Greatest number of protocol entries the controller retains.
  int get protocolEntryLimit => _protocolLog.limit;

  /// The server's standard error lines and notice summaries, oldest first.
  List<String> get consoleLines => List<String>.unmodifiable(_consoleLines);

  /// The form for the current selection, or null when nothing is selected.
  FormModel? get form => _form;

  /// The result of the last request, or null before the first one.
  CallOutcome? get outcome => _outcome;

  /// Whether a request is in flight.
  bool get isRunning => _isRunning;

  /// The elicitation awaiting an answer, or null when there is none.
  PendingElicitation? get pendingElicitation => _pendingElicitation;

  /// How many rows the active tab lists.
  int get itemCount => switch (_activeTab) {
    InspectorTab.tools => _tools.length,
    InspectorTab.resources => _resources.length,
    InspectorTab.prompts => _prompts.length,
    InspectorTab.protocol => _protocolLog.length,
    InspectorTab.console => _consoleLines.length,
  };

  /// The selected row of [tab], clamped to its current item count.
  int selectionOf(InspectorTab tab) {
    final index = _selection[tab] ?? 0;
    final count = _countOf(tab);
    if (count == 0) return 0;
    return index.clamp(0, count - 1);
  }

  /// The selected row of the active tab.
  int get selectedIndex => selectionOf(_activeTab);

  /// The selected tool, or null when the tools tab has no selection.
  McpToolInfo? get selectedTool =>
      _tools.isEmpty ? null : _tools[selectionOf(InspectorTab.tools)];

  /// The selected resource, or null when the resources tab has no selection.
  McpResourceInfo? get selectedResource => _resources.isEmpty
      ? null
      : _resources[selectionOf(InspectorTab.resources)];

  /// The selected prompt, or null when the prompts tab has no selection.
  McpPromptInfo? get selectedPrompt =>
      _prompts.isEmpty ? null : _prompts[selectionOf(InspectorTab.prompts)];

  /// The selected protocol entry, or null when nothing is recorded.
  ProtocolEntry? get selectedProtocolEntry {
    final entries = _protocolLog.entries;
    if (entries.isEmpty) return null;
    return entries[selectionOf(InspectorTab.protocol)];
  }

  /// Connects the session, then loads the inventory.
  Future<void> connect() async {
    _connectionState = InspectorConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();
    try {
      await session.connect();
      _listen();
      await refreshInventory(notify: false);
      _connectionState = InspectorConnectionState.connected;
    } on Object catch (error) {
      _connectionState = InspectorConnectionState.failed;
      _errorMessage = '$error';
    }
    _rebuildForm();
    notifyListeners();
  }

  /// Reloads the tool, resource, and prompt lists the server advertises.
  Future<void> refreshInventory({bool notify = true}) async {
    final capabilities = session.capabilities;
    if (capabilities.contains('tools')) _tools = await session.listTools();
    if (capabilities.contains('resources')) {
      _resources = await session.listResources();
    }
    if (capabilities.contains('prompts')) {
      _prompts = await session.listPrompts();
    }
    if (notify) {
      _rebuildForm();
      notifyListeners();
    }
  }

  /// Moves to [tab] and rebuilds the form for its selection.
  void selectTab(InspectorTab tab) {
    if (_activeTab == tab) return;
    _activeTab = tab;
    _outcome = null;
    _rebuildForm();
    notifyListeners();
  }

  /// Selects row [index] of the active tab and rebuilds its form.
  void select(int index) {
    final count = _countOf(_activeTab);
    if (count == 0) return;
    final clamped = index.clamp(0, count - 1);
    if (_selection[_activeTab] == clamped) return;
    _selection[_activeTab] = clamped;
    _outcome = null;
    _rebuildForm();
    notifyListeners();
  }

  /// Runs the active selection: a tool call, a resource read, or a prompt get.
  Future<void> run() async {
    if (_isRunning) return;
    final request = _requestForActiveTab();
    if (request == null) return;
    _isRunning = true;
    _outcome = null;
    notifyListeners();
    final outcome = await request();
    _isRunning = false;
    _outcome = outcome;
    notifyListeners();
  }

  /// Answers the pending elicitation with [action].
  void resolveElicitation(ElicitationAction action) {
    final pending = _pendingElicitation;
    if (pending == null) return;
    _pendingElicitation = null;
    pending.resolve(_outcomeFor(pending, action));
    pending.form.dispose();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    final pending = _pendingElicitation;
    _pendingElicitation = null;
    if (pending != null) {
      pending.resolve(const ElicitationOutcome.cancel());
      pending.form.dispose();
    }
    _form?.dispose();
    _form = null;
    _connectionState = InspectorConnectionState.closed;
    unawaited(session.close());
    super.dispose();
  }

  void _listen() {
    _subscriptions.addAll(<StreamSubscription<Object?>>[
      session.protocol.listen(_onProtocolEntry),
      session.console.listen(_onConsoleLine),
      session.notices.listen(_onNotice),
    ]);
  }

  void _onProtocolEntry(ProtocolEntry entry) {
    _protocolLog.add(entry);
    notifyListeners();
  }

  void _onConsoleLine(String line) {
    _appendConsole(line);
    notifyListeners();
  }

  void _onNotice(ServerNotice notice) {
    _appendConsole('! ${notice.summary}');
    final refreshes = <ServerNoticeKind>{
      ServerNoticeKind.toolsChanged,
      ServerNoticeKind.resourcesChanged,
      ServerNoticeKind.promptsChanged,
    };
    if (refreshes.contains(notice.kind)) {
      unawaited(_refreshAfterNotice());
    } else {
      notifyListeners();
    }
  }

  Future<void> _refreshAfterNotice() async {
    if (_closed) return;
    try {
      await refreshInventory();
    } on Object catch (error) {
      _appendConsole('! refresh failed: $error');
      notifyListeners();
    }
  }

  void _appendConsole(String line) {
    _consoleLines.add(line);
    while (_consoleLines.length > consoleLineLimit) {
      _consoleLines.removeAt(0);
    }
  }

  Future<ElicitationOutcome> _handleElicitation(ElicitationPrompt prompt) {
    final pending = PendingElicitation(prompt);
    _pendingElicitation = pending;
    notifyListeners();
    return pending.future;
  }

  ElicitationOutcome _outcomeFor(
    PendingElicitation pending,
    ElicitationAction action,
  ) => switch (action) {
    ElicitationAction.accept => ElicitationOutcome.accept(
      pending.form.toArguments().values,
    ),
    ElicitationAction.decline => const ElicitationOutcome.decline(),
    ElicitationAction.cancel => const ElicitationOutcome.cancel(),
  };

  Future<CallOutcome> Function()? _requestForActiveTab() {
    switch (_activeTab) {
      case InspectorTab.tools:
        final tool = selectedTool;
        final form = _form;
        if (tool == null || form == null) return null;
        final arguments = form.toArguments();
        if (!arguments.isValid) return () async => _rejected(arguments);
        return () => session.callTool(tool.name, arguments.values);
      case InspectorTab.resources:
        final resource = selectedResource;
        if (resource == null) return null;
        return () => session.readResource(resource.uri);
      case InspectorTab.prompts:
        final prompt = selectedPrompt;
        final form = _form;
        if (prompt == null || form == null) return null;
        final arguments = form.toArguments();
        if (!arguments.isValid) return () async => _rejected(arguments);
        return () => session.getPrompt(prompt.name, arguments.asStrings);
      case InspectorTab.protocol:
      case InspectorTab.console:
        return null;
    }
  }

  CallOutcome _rejected(FormArguments arguments) =>
      CallOutcome.failure(arguments.problem, Duration.zero);

  void _rebuildForm() {
    final spec = switch (_activeTab) {
      InspectorTab.tools => selectedTool?.form,
      InspectorTab.prompts => selectedPrompt?.form,
      InspectorTab.resources ||
      InspectorTab.protocol ||
      InspectorTab.console => null,
    };
    _form?.dispose();
    _form = spec == null ? null : FormModel(spec);
  }

  int _countOf(InspectorTab tab) => switch (tab) {
    InspectorTab.tools => _tools.length,
    InspectorTab.resources => _resources.length,
    InspectorTab.prompts => _prompts.length,
    InspectorTab.protocol => _protocolLog.length,
    InspectorTab.console => _consoleLines.length,
  };
}
