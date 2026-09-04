/// A stdio MCP server with one tool, one resource, and one prompt.
///
/// The shape follows the `example/server_stdio.dart` fixture that the official
/// MCP Inspector screenshots use, so the two inspectors show the same server.
/// The code is written against the public `package:mcp_dart` API and does not
/// depend on the upstream clone at run time.
///
/// Run with: `dart run fixtures/calculate_server.dart`
library;

import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

/// Builds the calculate server without connecting a transport.
///
/// The in-process protocol test pairs this server with the inspector session
/// over [IOStreamTransport], so the fixture must be reusable without stdio.
McpServer buildCalculateServer() {
  final server = McpServer(
    const Implementation(name: 'example_server', version: '1.0.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(
        resources: ServerCapabilitiesResources(),
        tools: ServerCapabilitiesTools(),
        prompts: ServerCapabilitiesPrompts(),
      ),
    ),
  );

  server.registerTool(
    'calculate',
    description: 'Perform basic arithmetic operations',
    inputSchema: JsonSchema.object(
      properties: <String, JsonSchema>{
        'operation': JsonSchema.string(
          enumValues: <String>['add', 'subtract', 'multiply', 'divide'],
          description: 'The arithmetic operation to apply',
        ),
        'a': JsonSchema.number(description: 'The left operand'),
        'b': JsonSchema.number(description: 'The right operand'),
      },
      required: <String>['operation', 'a', 'b'],
    ),
    callback: (args, extra) async {
      final operation = args['operation'] as String;
      final a = args['a'] as num;
      final b = args['b'] as num;
      return CallToolResult.fromContent(<Content>[
        TextContent(
          text: switch (operation) {
            'add' => 'Result: ${a + b}',
            'subtract' => 'Result: ${a - b}',
            'multiply' => 'Result: ${a * b}',
            'divide' => 'Result: ${a / b}',
            _ => throw StateError('Invalid operation: $operation'),
          },
        ),
      ]);
    },
  );

  server.registerResource(
    'Application Logs',
    'file:///logs',
    (description: 'Recent application log lines', mimeType: 'text/plain'),
    (uri, extra) async => ReadResourceResult(
      contents: <ResourceContents>[
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'text/plain',
          text: 'Sample log content',
        ),
      ],
    ),
  );

  server.registerPrompt(
    'analyze-code',
    description: 'Analyze code for potential improvements',
    argsSchema: <String, PromptArgumentDefinition>{
      'language': const PromptArgumentDefinition(
        description: 'Programming language',
        required: true,
      ),
    },
    callback: (args, extra) async {
      final language = args?['language'] ?? 'python';
      return GetPromptResult(
        messages: <PromptMessage>[
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(
              text:
                  'Please analyze the following $language code for potential '
                  'improvements:\n\n'
                  '```\n'
                  'def calculate_sum(numbers):\n'
                  '    total = 0\n'
                  '    for num in numbers:\n'
                  '        total = total + num\n'
                  '    return total\n'
                  '```',
            ),
          ),
        ],
      );
    },
  );

  return server;
}

/// Starts the calculate server on stdio.
Future<void> main() async {
  // The inspector captures child stderr into its console pane, so a banner
  // here proves that pane end to end.
  stderr.writeln('calculate_server ready');
  await buildCalculateServer().connect(StdioServerTransport());
}
