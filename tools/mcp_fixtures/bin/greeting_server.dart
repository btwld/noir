import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:noir_mcp_fixtures/greeting_server.dart';

/// Starts the greeting server on stdio.
Future<void> main() async {
  stderr.writeln('greeting_server ready');
  await buildGreetingServer().connect(StdioServerTransport());
}
