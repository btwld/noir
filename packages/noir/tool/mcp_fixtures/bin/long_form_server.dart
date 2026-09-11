import 'package:mcp_dart/mcp_dart.dart';

/// Exercises an elicitation form taller than a small terminal viewport.
Future<void> main() async {
  final server = McpServer(
    const Implementation(name: 'long_form_server', version: '1.0.0'),
    options: const McpServerOptions(protocol: McpProtocol.legacy),
  );
  server.registerTool(
    'long_form',
    inputSchema: JsonSchema.object(properties: {}),
    callback: (args, extra) async {
      final answer = await server.elicitInput(
        ElicitRequest.form(
          message: 'Enter all eight values.',
          requestedSchema: JsonSchema.object(
            properties: {
              for (var index = 0; index < 8; index++)
                'f$index': JsonSchema.string(
                  description: 'Value number $index',
                ),
            },
            required: [for (var index = 0; index < 8; index++) 'f$index'],
          ),
        ),
      );
      return CallToolResult.fromContent([
        TextContent(
          text: answer.accepted
              ? 'Accepted ${answer.content!.values.join(',')}'
              : 'Cancelled',
        ),
      ]);
    },
  );
  await server.connect(StdioServerTransport());
}
