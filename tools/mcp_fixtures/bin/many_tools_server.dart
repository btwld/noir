import 'package:mcp_dart/mcp_dart.dart';

/// Twenty tools, enough to overflow the primitives pane at every grid the
/// drive checks use, so a resize changes how many rows the list shows.
Future<void> main() async {
  final server = McpServer(
    const Implementation(name: 'many_tools_server', version: '1.0.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );
  for (var index = 1; index <= 20; index++) {
    final name = 'tool${index.toString().padLeft(2, '0')}';
    server.registerTool(
      name,
      description: 'Echo a note from $name',
      inputSchema: JsonSchema.object(
        properties: {'note': JsonSchema.string()},
        required: ['note'],
      ),
      callback: (args, extra) async => CallToolResult.fromContent([
        TextContent(text: '$name: ${args['note']}'),
      ]),
    );
  }
  await server.connect(StdioServerTransport());
}
