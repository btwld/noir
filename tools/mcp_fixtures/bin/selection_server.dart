import 'package:mcp_dart/mcp_dart.dart';

/// Two tools with distinct fields exercise focus across form replacement.
Future<void> main() async {
  final server = McpServer(
    const Implementation(name: 'selection_server', version: '1.0.0'),
    options: const McpServerOptions(protocol: McpProtocol.legacy),
  );
  for (final name in ['first', 'second']) {
    final field = '${name}Value';
    server.registerTool(
      name,
      inputSchema: JsonSchema.object(
        properties: {field: JsonSchema.string()},
        required: [field],
      ),
      callback: (args, extra) async => CallToolResult.fromContent([
        TextContent(text: '$name: ${args[field]}'),
      ]),
    );
  }
  await server.connect(StdioServerTransport());
}
