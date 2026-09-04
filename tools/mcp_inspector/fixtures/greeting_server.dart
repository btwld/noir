/// A strict MCP 2026-07-28 stdio server that answers with `input_required`.
///
/// `personalized_greeting` returns an [InputRequiredResult] on its first call.
/// The client answers the embedded elicitation, the SDK retries the call, and
/// the second pass returns the greeting. This is the 2026 profile of the same
/// user-input flow that `legacy_elicit_server.dart` performs with
/// `elicitation/create`.
///
/// Run with: `dart run fixtures/greeting_server.dart`
library;

import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

/// Builds the greeting server without connecting a transport.
McpServer buildGreetingServer() {
  final server = McpServer(
    const Implementation(name: 'greeting_server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.require2026,
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );

  server.registerStatelessTool(
    'personalized_greeting',
    description: 'Collect a name, then return a personalized greeting.',
    inputSchema: JsonSchema.object(properties: <String, JsonSchema>{}),
    outputJsonSchema: JsonSchema.string(),
    callback: (args, extra) async {
      final profile = extra.inputResponses?['profile'];
      if (profile == null) {
        return InputRequiredResult(
          requestState: 'greeting-v1',
          inputRequests: <String, InputRequest>{
            'profile': InputRequest.elicit(
              ElicitRequest.form(
                message: 'What name should the greeting use?',
                requestedSchema: JsonSchema.object(
                  properties: <String, JsonSchema>{
                    'name': JsonSchema.string(
                      minLength: 1,
                      description: 'The name to greet',
                    ),
                  },
                  required: <String>['name'],
                ),
              ),
            ),
          },
        );
      }
      if (extra.requestState != 'greeting-v1') {
        throw McpError(
          ErrorCode.invalidParams.value,
          'Unexpected request state.',
        );
      }
      final elicitation = ElicitResult.fromJson(profile.toJson());
      if (elicitation.declined) {
        return CallToolResult.fromStructuredString('Greeting declined.');
      }
      if (elicitation.cancelled) {
        return CallToolResult.fromStructuredString('Greeting cancelled.');
      }
      final name = elicitation.content?['name'];
      if (name is! String || name.isEmpty) {
        throw McpError(
          ErrorCode.invalidParams.value,
          'The profile response must contain a name.',
        );
      }
      return CallToolResult.fromStructuredString('Hello, $name!');
    },
  );

  return server;
}

/// Starts the greeting server on stdio.
Future<void> main() async {
  stderr.writeln('greeting_server ready');
  await buildGreetingServer().connect(StdioServerTransport());
}
