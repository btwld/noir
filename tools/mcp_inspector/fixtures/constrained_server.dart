import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

/// Builds a server whose one tool declares the constraints a form must show.
///
/// The schema carries two kinds of constraint. The value constraints —
/// `minimum`, `maximum`, `multipleOf`, `minLength`, `maxLength`, `pattern`,
/// and `format` — are the common case, and the generated form renders them as
/// hint text. The conditional constraints — `if` / `then` in [JsonObject.extra]
/// and `dependentRequired` — generate no control at all, so this fixture is
/// also the reproduction for entry 24 of `FINDINGS.md`.
McpServer buildConstrainedServer() {
  final server = McpServer(
    const Implementation(name: 'constrained_server', version: '1.0.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );

  server.registerTool(
    'schedule',
    description: 'Schedule a job and report the settings it received',
    inputSchema: JsonObject(
      properties: <String, JsonSchema>{
        'mode': JsonSchema.string(
          enumValues: <String>['once', 'recurring'],
          description: 'How often the job runs',
        ),
        'attempts': JsonSchema.integer(
          minimum: 1,
          maximum: 10,
          description: 'Retry budget',
        ),
        'timeoutSeconds': JsonSchema.number(
          minimum: 0.5,
          maximum: 60,
          multipleOf: 0.5,
          description: 'Seconds before the run is abandoned',
        ),
        'slug': JsonSchema.string(
          minLength: 1,
          maxLength: 32,
          pattern: r'^[a-z0-9-]+$',
          description: 'Job identifier',
        ),
        'webhook': JsonSchema.string(
          format: 'uri',
          description: 'Where the result is posted',
        ),
        'intervalMinutes': JsonSchema.integer(
          minimum: 1,
          description: 'Required only when mode is recurring',
        ),
      },
      required: <String>['mode', 'slug'],
      // `dependentRequired` is a typed field. `if` and `then` are not modeled
      // by the builder hierarchy, so they travel in `extra`, which preserves
      // them across parse and serialize.
      dependentRequired: <String, List<String>>{
        'webhook': <String>['slug'],
      },
      extra: const <String, dynamic>{
        'if': <String, dynamic>{
          'properties': <String, dynamic>{
            'mode': <String, dynamic>{'const': 'recurring'},
          },
        },
        'then': <String, dynamic>{
          'required': <String>['intervalMinutes'],
        },
      },
    ),
    callback: (args, extra) async {
      final mode = args['mode'] as String;
      final slug = args['slug'] as String;
      final interval = args['intervalMinutes'];
      return CallToolResult.fromContent(<Content>[
        TextContent(
          text: interval == null
              ? 'Scheduled $slug ($mode)'
              : 'Scheduled $slug ($mode, every $interval min)',
        ),
      ]);
    },
  );

  return server;
}

/// Starts the constrained server on stdio.
Future<void> main() async {
  stderr.writeln('constrained_server ready');
  await buildConstrainedServer().connect(StdioServerTransport());
}
