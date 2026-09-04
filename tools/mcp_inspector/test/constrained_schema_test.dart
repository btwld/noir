import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:noir_mcp_inspector/noir_mcp_inspector.dart';
import 'package:test/test.dart';

import '../fixtures/constrained_server.dart';

void main() {
  late McpServer server;
  late LiveMcpSession session;
  late StreamController<List<int>> toClient;
  late StreamController<List<int>> toServer;

  setUp(() async {
    toClient = StreamController<List<int>>();
    toServer = StreamController<List<int>>();
    server = buildConstrainedServer();
    session = LiveMcpSession.transport(
      IOStreamTransport(stream: toClient.stream, sink: toServer.sink),
    );
    await server.connect(
      IOStreamTransport(stream: toServer.stream, sink: toClient.sink),
    );
    await session.connect();
  });

  tearDown(() async {
    await session.close();
    await server.close();
    await toClient.close();
    await toServer.close();
  });

  Future<McpToolInfo> schedule() async => (await session.listTools())
      .singleWhere((tool) => tool.name == 'schedule');

  test('every value constraint reaches the form as hint text', () async {
    final tool = await schedule();

    final hints = <String, String?>{
      for (final field in tool.form.fields) field.name: field.hint,
    };
    expect(hints, <String, String?>{
      'mode': 'How often the job runs',
      'attempts': 'Retry budget  (1..10)',
      'timeoutSeconds':
          'Seconds before the run is abandoned  (0.5..60, multiple of 0.5)',
      'slug': r'Job identifier  (length 1..32, pattern ^[a-z0-9-]+$)',
      'webhook': 'Where the result is posted  (format uri)',
      'intervalMinutes': 'Required only when mode is recurring  (>= 1)',
    });
  });

  test('the conditional keywords generate no control', () async {
    final tool = await schedule();

    // The form covers the declared properties and nothing else. `if`, `then`,
    // and `dependentRequired` constrain the arguments but map to no field.
    expect(tool.form.fields.map((field) => field.name), <String>[
      'mode',
      'attempts',
      'timeoutSeconds',
      'slug',
      'webhook',
      'intervalMinutes',
    ]);
  });

  test('the raw schema still carries the conditional keywords', () async {
    final schema = (await schedule()).schema;

    expect(schema, isNotNull);
    expect(schema!['if'], isNotNull);
    expect(schema['then'], <String, dynamic>{
      'required': <String>['intervalMinutes'],
    });
    expect(schema['dependentRequired'], <String, dynamic>{
      'webhook': <String>['slug'],
    });
  });

  test('the tool runs with the conditional branch satisfied', () async {
    final outcome = await session.callTool('schedule', <String, Object?>{
      'mode': 'recurring',
      'slug': 'nightly-sync',
      'intervalMinutes': 30,
    });

    expect(outcome.text, 'Scheduled nightly-sync (recurring, every 30 min)');
  });
}
