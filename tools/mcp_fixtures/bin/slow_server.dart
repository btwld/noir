import 'package:mcp_dart/mcp_dart.dart';

/// One tool that answers slowly, so a drive check can observe the inspector
/// while a request is still in flight.
///
/// The delay is long enough for several driver round trips and short enough
/// that the check does not dominate the suite.
const _delay = Duration(milliseconds: 2500);

Future<void> main() async {
  final server = McpServer(
    const Implementation(name: 'slow_server', version: '1.0.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );
  server.registerTool(
    'slow',
    description: 'Echo a note after a deliberate delay',
    inputSchema: JsonSchema.object(
      properties: {'note': JsonSchema.string()},
      required: ['note'],
    ),
    callback: (args, extra) async {
      await Future<void>.delayed(_delay);
      return CallToolResult.fromContent([
        TextContent(text: 'slow: ${args['note']}'),
      ]);
    },
  );
  await server.connect(StdioServerTransport());
}
