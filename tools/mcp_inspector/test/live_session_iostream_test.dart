import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:noir_mcp_inspector/noir_mcp_inspector.dart';
import 'package:test/test.dart';

import '../fixtures/calculate_server.dart';

void main() {
  late McpServer server;
  late LiveMcpSession session;
  late ProtocolLog log;
  late StreamSubscription<ProtocolEntry> recording;

  late StreamController<List<int>> toClient;
  late StreamController<List<int>> toServer;

  setUp(() async {
    toClient = StreamController<List<int>>();
    toServer = StreamController<List<int>>();
    final serverTransport = IOStreamTransport(
      stream: toServer.stream,
      sink: toClient.sink,
    );
    final clientTransport = IOStreamTransport(
      stream: toClient.stream,
      sink: toServer.sink,
    );
    server = buildCalculateServer();
    session = LiveMcpSession.transport(clientTransport);
    log = ProtocolLog();
    recording = session.protocol.listen(log.add);
    await server.connect(serverTransport);
    await session.connect();
  });

  tearDown(() async {
    await recording.cancel();
    await session.close();
    await server.close();
    await toClient.close();
    await toServer.close();
  });

  test('the handshake reports the server identity and capabilities', () {
    expect(session.serverInfo?.name, 'example_server');
    expect(session.serverInfo?.version, '1.0.0');
    expect(session.protocolVersion, isNotNull);
    expect(
      session.capabilities,
      containsAll(<String>['tools', 'resources', 'prompts']),
    );
  });

  test('the tool list carries a generated form', () async {
    final tools = await session.listTools();

    final calculate = tools.singleWhere((tool) => tool.name == 'calculate');
    expect(calculate.description, 'Perform basic arithmetic operations');
    expect(calculate.form.fields.map((field) => field.name), <String>[
      'operation',
      'a',
      'b',
    ]);
    expect(calculate.form.fields.first.options, <String>[
      'add',
      'subtract',
      'multiply',
      'divide',
    ]);
  });

  test('calling calculate returns the sum', () async {
    final outcome = await session.callTool('calculate', <String, Object?>{
      'operation': 'add',
      'a': 5,
      'b': 3,
    });

    expect(outcome.isError, isFalse);
    expect(outcome.text, 'Result: 8');
    expect(outcome.elapsed, greaterThan(Duration.zero));
  });

  test('a rejected tool call becomes an error outcome', () async {
    final outcome = await session.callTool('calculate', <String, Object?>{
      'operation': 'add',
    });

    expect(outcome.isError, isTrue);
    expect(outcome.text, isNotEmpty);
  });

  test('reading the log resource returns its text', () async {
    final resources = await session.listResources();
    final outcome = await session.readResource(resources.single.uri);

    expect(resources.single.uri, 'file:///logs');
    expect(resources.single.name, 'Application Logs');
    expect(outcome.text, 'Sample log content');
  });

  test('getting the prompt returns its message text', () async {
    final prompts = await session.listPrompts();
    final outcome = await session.getPrompt('analyze-code', <String, String>{
      'language': 'dart',
    });

    expect(prompts.single.name, 'analyze-code');
    expect(prompts.single.form.fields.single.name, 'language');
    expect(prompts.single.form.fields.single.isRequired, isTrue);
    expect(outcome.text, contains('analyze the following dart code'));
  });

  test('the protocol log pairs every request with its response', () async {
    await session.callTool('calculate', <String, Object?>{
      'operation': 'multiply',
      'a': 6,
      'b': 7,
    });

    final requests = log.entries.where((entry) => entry.isRequest).toList();
    final responses = log.entries
        .where((entry) => entry.isResult || entry.isError)
        .toList();
    expect(requests, isNotEmpty);
    expect(responses, hasLength(requests.length));
    for (final response in responses) {
      expect(response.elapsed, isNotNull, reason: response.label);
    }
    final call = requests.singleWhere((entry) => entry.method == 'tools/call');
    expect(call.label, startsWith('-> tools/call #'));
    final answer = responses.singleWhere((entry) => entry.id == call.id);
    expect(answer.label, matches(RegExp(r'^<- result #\d+ \d+ms$')));
  });
}
