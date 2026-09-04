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
}
