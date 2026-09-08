import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:noir_mcp_fixtures/legacy_elicit_server.dart';

/// Starts the legacy elicitation server on stdio.
Future<void> main() async {
  stderr.writeln('legacy_elicit_server ready');
  await buildLegacyElicitServer().connect(StdioServerTransport());
}
