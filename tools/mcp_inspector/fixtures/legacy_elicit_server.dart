/// A stdio MCP server on the 2025-11-25 profile that calls `elicitation/create`.
///
/// `register_user` suspends inside its tool callback until the client answers
/// the elicitation. The inspector serves this request with the same modal and
/// the same handler it uses for the 2026 `input_required` flow, which is what
/// the pair of fixtures exists to prove.
///
/// Run with: `dart run fixtures/legacy_elicit_server.dart`
library;

import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

/// Builds the legacy elicitation server without connecting a transport.
McpServer buildLegacyElicitServer() {
  late final McpServer server;
  server = McpServer(
    const Implementation(name: 'legacy_elicit_server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.legacy,
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );

  server.registerTool(
    'register_user',
    description: 'Ask the client for a name, then confirm the registration.',
    inputSchema: JsonSchema.object(properties: <String, JsonSchema>{}),
    callback: (args, extra) async {
      final answer = await server.elicitInput(
        ElicitRequest.form(
          message: 'What name should the registration use?',
          requestedSchema: JsonSchema.object(
            properties: <String, JsonSchema>{
              'name': JsonSchema.string(
                minLength: 1,
                description: 'The name to register',
              ),
            },
            required: <String>['name'],
          ),
        ),
      );
      if (answer.declined) {
        return CallToolResult.fromContent(<Content>[
          const TextContent(text: 'Registration declined.'),
        ]);
      }
      if (answer.cancelled) {
        return CallToolResult.fromContent(<Content>[
          const TextContent(text: 'Registration cancelled.'),
        ]);
      }
      final name = answer.content?['name'];
      if (name is! String || name.isEmpty) {
        throw McpError(
          ErrorCode.invalidParams.value,
          'The registration response must contain a name.',
        );
      }
      return CallToolResult.fromContent(<Content>[
        TextContent(text: 'Registered $name.'),
      ]);
    },
  );

  return server;
}

/// Starts the legacy elicitation server on stdio.
Future<void> main() async {
  stderr.writeln('legacy_elicit_server ready');
  await buildLegacyElicitServer().connect(StdioServerTransport());
}
