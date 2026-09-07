import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:noir_mcp_fixtures/constrained_server.dart';

/// Starts the constrained server on stdio.
Future<void> main() async {
  stderr.writeln('constrained_server ready');
  await buildConstrainedServer().connect(StdioServerTransport());
}
