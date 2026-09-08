import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:noir_mcp_fixtures/calculate_server.dart';

/// Starts the calculate server on stdio.
Future<void> main() async {
  // The inspector captures child stderr into its console pane, so a banner
  // here proves that pane end to end.
  stderr.writeln('calculate_server ready');
  await buildCalculateServer().connect(StdioServerTransport());
}
