import 'dart:async';
import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:noir_mcp_fixtures/greeting_server.dart';
import 'package:noir_mcp_fixtures/legacy_elicit_server.dart';
import 'package:noir_mcp_inspector/noir_mcp_inspector.dart';
import 'package:test/test.dart';

import 'fake_mcp_session.dart';

const _calculateForm = FormSpec(<FormFieldSpec>[
  FormFieldSpec(
    name: 'operation',
    kind: FormFieldKind.select,
    isRequired: true,
    options: <String>['add', 'subtract'],
  ),
  FormFieldSpec(name: 'a', kind: FormFieldKind.number, isRequired: true),
  FormFieldSpec(name: 'b', kind: FormFieldKind.number, isRequired: true),
]);

const _calculate = McpToolInfo(
  name: 'calculate',
  form: _calculateForm,
  description: 'Perform basic arithmetic operations',
  schema: <String, dynamic>{
    'type': 'object',
    'required': <String>['operation', 'a', 'b'],
  },
);

const _echo = McpToolInfo(name: 'echo', form: FormSpec(<FormFieldSpec>[]));

const _logs = McpResourceInfo(uri: 'file:///logs', name: 'Application Logs');

const _analyze = McpPromptInfo(
  name: 'analyze-code',
  form: FormSpec(<FormFieldSpec>[
    FormFieldSpec(name: 'language', kind: FormFieldKind.text, isRequired: true),
  ]),
);

FakeMcpSession _session() => FakeMcpSession(
  tools: const <McpToolInfo>[_calculate],
  resources: const <McpResourceInfo>[_logs],
  prompts: const <McpPromptInfo>[_analyze],
);

void main() {
  test('connect loads the inventory and builds the first form', () async {
    final session = _session();
    final controller = InspectorController(session: session);
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.connect();

    expect(controller.connectionState, InspectorConnectionState.connected);
    expect(controller.tools.single.name, 'calculate');
    expect(controller.resources.single.uri, 'file:///logs');
    expect(controller.prompts.single.name, 'analyze-code');
    expect(controller.selectedTool?.name, 'calculate');
    expect(controller.form?.spec.fields.map((field) => field.name), <String>[
      'operation',
      'a',
      'b',
    ]);
    expect(notifications, greaterThanOrEqualTo(2));
  });

  test('the schema view toggles and notifies', () async {
    final session = _session();
    final controller = InspectorController(session: session);
    addTearDown(controller.dispose);
    await controller.connect();
    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(controller.isSchemaVisible, isFalse);
    expect(controller.visibleSchema, isNull);

    controller.toggleSchema();

    expect(controller.isSchemaVisible, isTrue);
    expect(controller.visibleSchema, _calculate.schema);
    expect(notifications, 1);

    controller.toggleSchema();

    expect(controller.isSchemaVisible, isFalse);
    expect(controller.visibleSchema, isNull);
  });

  test('a tab without schemas ignores the toggle', () async {
    final session = _session();
    final controller = InspectorController(session: session);
    addTearDown(controller.dispose);
    await controller.connect();
    controller.selectTab(InspectorTab.prompts);

    controller.toggleSchema();

    // Flipping hidden state here would make the schema appear later, on a
    // tools tab the reader never asked to change.
    expect(controller.isSchemaVisible, isFalse);
  });

  test('a tool that carries no schema shows none', () async {
    final session = FakeMcpSession(tools: const <McpToolInfo>[_echo]);
    final controller = InspectorController(session: session);
    addTearDown(controller.dispose);
    await controller.connect();

    controller.toggleSchema();

    expect(controller.isSchemaVisible, isFalse);
    expect(controller.visibleSchema, isNull);
    expect(controller.visibleSchemaText, isNull);
  });

  test('an empty tool list ignores the schema toggle', () async {
    final controller = InspectorController(session: FakeMcpSession());
    addTearDown(controller.dispose);
    await controller.connect();
    controller.toggleSchema();
    expect(controller.isSchemaVisible, isFalse);
  });

  test('an unencodable schema reports the limitation without throwing', () async {
    final controller = InspectorController(
      session: FakeMcpSession(
        tools: [
          McpToolInfo(
            name: 'large',
            form: const FormSpec([]),
            schema:
                jsonDecode(
                      '{"type":"object","properties":{"n":{"type":"number","maximum":1e400}}}',
                    )
                    as Map<String, dynamic>,
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await controller.connect();
    controller.toggleSchema();
    expect(controller.visibleSchemaText, contains('cannot be displayed'));
    expect(controller.visibleSchemaText, contains('non-finite'));
    expect(
      controller.visibleSchemaText,
      isNotNull,
      reason: 'repeated reads must retain the explanation',
    );
  });

  test(
    'the schema view stays empty for a tab that carries no schema',
    () async {
      final session = _session();
      final controller = InspectorController(session: session);
      addTearDown(controller.dispose);
      await controller.connect();

      controller
        ..toggleSchema()
        ..selectTab(InspectorTab.resources);

      expect(controller.isSchemaVisible, isTrue);
      expect(controller.visibleSchema, isNull);
    },
  );

  test('a failed connect keeps the message and stays disconnected', () async {
    final session = _session()..connectFailure = 'no such command';
    final controller = InspectorController(session: session);
    addTearDown(controller.dispose);

    await controller.connect();

    expect(controller.connectionState, InspectorConnectionState.failed);
    expect(controller.errorMessage, contains('no such command'));
    expect(controller.tools, isEmpty);
  });

  test('selecting a tool rebuilds the form and clears the outcome', () async {
    final session = _session()..tools = const <McpToolInfo>[_calculate, _echo];
    final controller = InspectorController(session: session);
    addTearDown(controller.dispose);
    await controller.connect();
    await controller.run();
    expect(controller.outcome, isNotNull);

    controller.select(1);

    expect(controller.selectedTool?.name, 'echo');
    expect(controller.form?.spec.isEmpty, isTrue);
    expect(controller.outcome, isNull);
  });

  test('run sends the coerced arguments and stores the outcome', () async {
    final session = _session();
    final controller = InspectorController(session: session);
    addTearDown(controller.dispose);
    await controller.connect();
    controller.form!
      ..setText('a', '5')
      ..setText('b', '3');

    await controller.run();

    expect(session.toolCalls.single.name, 'calculate');
    expect(session.toolCalls.single.arguments, <String, Object?>{
      'operation': 'add',
      'a': 5,
      'b': 3,
    });
    expect(controller.outcome?.blocks, <String>['ok']);
    expect(controller.outcome?.elapsed, const Duration(milliseconds: 7));
    expect(controller.isRunning, isFalse);
  });

  test(
    'run rejects an incomplete form without contacting the server',
    () async {
      final session = _session();
      final controller = InspectorController(session: session);
      addTearDown(controller.dispose);
      await controller.connect();

      await controller.run();

      expect(session.toolCalls, isEmpty);
      expect(controller.outcome?.isError, isTrue);
      expect(controller.outcome?.text, contains('Missing required: a, b'));
    },
  );

  test('run reads a resource and gets a prompt from their tabs', () async {
    final session = _session();
    final controller = InspectorController(session: session);
    addTearDown(controller.dispose);
    await controller.connect();

    controller.selectTab(InspectorTab.resources);
    await controller.run();
    controller.selectTab(InspectorTab.prompts);
    controller.form!.setText('language', 'dart');
    await controller.run();

    expect(session.resourceReads, <String>['file:///logs']);
    expect(session.promptGets.single.name, 'analyze-code');
    expect(session.promptGets.single.arguments, <String, String>{
      'language': 'dart',
    });
  });

  test('a protocol entry and a console line reach the controller', () async {
    final session = _session();
    final controller = InspectorController(session: session);
    addTearDown(controller.dispose);
    await controller.connect();

    session
      ..emitProtocol(
        ProtocolEntry(
          sequence: 1,
          direction: ProtocolDirection.outgoing,
          message: const <String, dynamic>{'id': 1, 'method': 'tools/call'},
          timestamp: DateTime(2026, 9, 3, 12),
        ),
      )
      ..emitConsole('calculate_server ready');
    await Future<void>.delayed(Duration.zero);

    expect(controller.protocolEntries.single.label, '-> tools/call #1');
    expect(controller.consoleLines, <String>['calculate_server ready']);
    expect(controller.protocolEntryLimit, 500);
  });

  test('a list_changed notice reloads the tool list', () async {
    final session = _session();
    final controller = InspectorController(session: session);
    addTearDown(controller.dispose);
    await controller.connect();
    expect(session.listToolsCount, 1);
    session.tools = const <McpToolInfo>[_calculate, _echo];

    session.emitNotice(
      const ServerNotice(
        kind: ServerNoticeKind.toolsChanged,
        method: 'notifications/tools/list_changed',
        summary: 'notifications/tools/list_changed',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(session.listToolsCount, 2);
    expect(controller.tools, hasLength(2));
    expect(controller.consoleLines, <String>[
      '! notifications/tools/list_changed',
    ]);
  });

  test('an elicitation enqueues, notifies, and resolves on accept', () async {
    final session = _session();
    final controller = InspectorController(session: session);
    addTearDown(controller.dispose);
    await controller.connect();
    var notifications = 0;
    controller.addListener(() => notifications++);

    final answer = session.requestElicitation(
      const ElicitationPrompt(
        message: 'What name should the greeting use?',
        form: FormSpec(<FormFieldSpec>[
          FormFieldSpec(
            name: 'name',
            kind: FormFieldKind.text,
            isRequired: true,
          ),
        ]),
      ),
    );

    expect(notifications, 1);
    final pending = controller.pendingElicitation;
    expect(pending, isNotNull);
    expect(pending!.prompt.message, 'What name should the greeting use?');
    pending.form.setText('name', 'Leo');
    controller.resolveElicitation(ElicitationAction.accept);

    final outcome = await answer;
    expect(outcome.action, ElicitationAction.accept);
    expect(outcome.content, <String, Object?>{'name': 'Leo'});
    expect(controller.pendingElicitation, isNull);
  });

  test('declining an elicitation resolves it without content', () async {
    final session = _session();
    final controller = InspectorController(session: session);
    addTearDown(controller.dispose);
    await controller.connect();

    final answer = session.requestElicitation(
      const ElicitationPrompt(
        message: 'Name?',
        form: FormSpec(<FormFieldSpec>[]),
      ),
    );
    controller.resolveElicitation(ElicitationAction.decline);

    final outcome = await answer;
    expect(outcome.action, ElicitationAction.decline);
    expect(outcome.content, isNull);
  });

  test('dispose cancels a pending elicitation and closes once', () async {
    final session = _session();
    final controller = InspectorController(session: session);
    await controller.connect();
    final answer = session.requestElicitation(
      const ElicitationPrompt(
        message: 'Name?',
        form: FormSpec(<FormFieldSpec>[]),
      ),
    );

    controller.dispose();
    controller.dispose();

    expect((await answer).action, ElicitationAction.cancel);
    expect(session.closeCount, 1);
    expect(controller.connectionState, InspectorConnectionState.closed);
  });

  group('server-initiated input over a live session', () {
    test('a 2026 input_required call waits for the accepted form', () async {
      final live = await _LiveFixture.start(
        buildGreetingServer(),
        protocol: McpProtocol.require2026,
      );
      addTearDown(live.stop);

      expect(live.controller.tools.single.name, 'personalized_greeting');
      final running = live.controller.run();
      await _until(() => live.controller.pendingElicitation != null);
      final pending = live.controller.pendingElicitation!;
      expect(pending.prompt.message, 'What name should the greeting use?');
      expect(pending.form.spec.fields.single.name, 'name');
      pending.form.setText('name', 'Leo');
      live.controller.resolveElicitation(ElicitationAction.accept);
      await running;

      expect(live.controller.outcome?.isError, isFalse);
      expect(live.controller.outcome?.text, contains('Hello, Leo!'));
      expect(live.controller.pendingElicitation, isNull);
    });

    test('declining a 2026 input_required call returns the refusal', () async {
      final live = await _LiveFixture.start(
        buildGreetingServer(),
        protocol: McpProtocol.require2026,
      );
      addTearDown(live.stop);

      final running = live.controller.run();
      await _until(() => live.controller.pendingElicitation != null);
      live.controller.resolveElicitation(ElicitationAction.decline);
      await running;

      expect(live.controller.outcome?.text, contains('Greeting declined.'));
    });

    test('the same handler answers a 2025-11-25 elicitation/create', () async {
      final live = await _LiveFixture.start(
        buildLegacyElicitServer(),
        protocol: McpProtocol.legacy,
      );
      addTearDown(live.stop);

      expect(live.controller.tools.single.name, 'register_user');
      final running = live.controller.run();
      await _until(() => live.controller.pendingElicitation != null);
      final pending = live.controller.pendingElicitation!;
      expect(pending.prompt.message, 'What name should the registration use?');
      pending.form.setText('name', 'Leo');
      live.controller.resolveElicitation(ElicitationAction.accept);
      await running;

      expect(live.controller.outcome?.text, 'Registered Leo.');
    });

    test('cancelling a 2025-11-25 elicitation returns the refusal', () async {
      final live = await _LiveFixture.start(
        buildLegacyElicitServer(),
        protocol: McpProtocol.legacy,
      );
      addTearDown(live.stop);

      final running = live.controller.run();
      await _until(() => live.controller.pendingElicitation != null);
      live.controller.resolveElicitation(ElicitationAction.cancel);
      await running;

      expect(live.controller.outcome?.text, 'Registration cancelled.');
    });
  });
}

/// One in-process server, session, and controller wired over `IOStreamTransport`.
final class _LiveFixture {
  _LiveFixture._(this.server, this.controller, this._toClient, this._toServer);

  /// Starts [server] and a connected controller on [protocol].
  static Future<_LiveFixture> start(
    McpServer server, {
    required McpProtocol protocol,
  }) async {
    // `stop()` owns both pipes; the lint only sees one function at a time.
    // ignore: close_sinks
    final toClient = StreamController<List<int>>();
    // ignore: close_sinks
    final toServer = StreamController<List<int>>();
    await server.connect(
      IOStreamTransport(stream: toServer.stream, sink: toClient.sink),
    );
    final controller = InspectorController(
      session: LiveMcpSession.transport(
        IOStreamTransport(stream: toClient.stream, sink: toServer.sink),
        protocol: protocol,
      ),
    );
    await controller.connect();
    expect(
      controller.connectionState,
      InspectorConnectionState.connected,
      reason: controller.errorMessage,
    );
    return _LiveFixture._(server, controller, toClient, toServer);
  }

  /// The in-process MCP server.
  final McpServer server;

  /// The controller under test.
  final InspectorController controller;

  final StreamController<List<int>> _toClient;
  final StreamController<List<int>> _toServer;

  /// Releases the controller, the server, and both pipes.
  Future<void> stop() async {
    controller.dispose();
    await server.close();
    await _toClient.close();
    await _toServer.close();
  }
}

/// Polls [condition] until it holds or the deadline passes.
Future<void> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Timed out waiting for the expected state.');
}
