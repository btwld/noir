/// Command-line entry point for the Noir MCP inspector.
///
/// From `tools/mcp_inspector`, start a server as a child process:
///
/// ```sh
/// dart run bin/mcp_inspector.dart -- \
///   dart run ../mcp_fixtures/bin/calculate_server.dart
/// ```
///
/// Or connect to a Streamable HTTP endpoint:
///
/// ```sh
/// dart run bin/mcp_inspector.dart --url http://localhost:3000/mcp
/// ```
library;

import 'dart:io' as io;

import 'package:mcp_dart/mcp_dart.dart';
import 'package:noir/noir.dart';
import 'package:noir_mcp_inspector/noir_mcp_inspector.dart';

const _usage = '''
Usage:
  mcp_inspector [--protocol stable|legacy|2026] -- <command> [args...]
  mcp_inspector [--protocol stable|legacy|2026] --url <uri>

Options:
  --protocol   MCP compatibility profile. Defaults to stable.
  --url        Streamable HTTP endpoint of a running server.
  --           Everything after this starts a server as a child process.
''';

void main(List<String> arguments) {
  final parsed = parseArguments(arguments);
  switch (parsed) {
    case InspectorUsageError(:final message):
      io.stderr.writeln(message);
      io.stderr.writeln(_usage);
      io.exitCode = 64;
    case InspectorLaunch(:final session):
      runTuiApp(InspectorApp(session: session), enableMouse: true);
  }
}

/// The outcome of reading the command line.
sealed class InspectorArguments {
  /// Allows subclasses to be constant.
  const InspectorArguments();
}

/// The command line named a server the inspector can connect to.
final class InspectorLaunch extends InspectorArguments {
  /// Creates a launch carrying the session to run.
  const InspectorLaunch(this.session);

  /// The session the screen connects and closes.
  final McpSession session;
}

/// The command line could not be understood.
final class InspectorUsageError extends InspectorArguments {
  /// Creates a usage error explaining [message].
  const InspectorUsageError(this.message);

  /// What the user must correct.
  final String message;
}

/// Reads [arguments] into either a session to run or a usage error.
InspectorArguments parseArguments(List<String> arguments) {
  var protocol = McpProtocol.stable;
  String? url;
  List<String>? command;

  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--') {
      command = arguments.sublist(index + 1);
      break;
    }
    if (argument == '--url') {
      if (index + 1 >= arguments.length) {
        return const InspectorUsageError('--url needs a URI.');
      }
      url = arguments[++index];
      continue;
    }
    if (argument == '--protocol') {
      if (index + 1 >= arguments.length) {
        return const InspectorUsageError('--protocol needs a profile.');
      }
      final value = arguments[++index];
      final selected = _protocolFor(value);
      if (selected == null) {
        return InspectorUsageError('Unknown protocol profile "$value".');
      }
      protocol = selected;
      continue;
    }
    return InspectorUsageError('Unknown option "$argument".');
  }

  if (command != null && url != null) {
    return const InspectorUsageError('Use either --url or -- <command>.');
  }
  if (command != null) {
    if (command.isEmpty) {
      return const InspectorUsageError('-- needs a command to run.');
    }
    return InspectorLaunch(
      LiveMcpSession.stdio(
        command: command.first,
        args: command.sublist(1),
        protocol: protocol,
        captureSdkLogs: true,
      ),
    );
  }
  if (url != null) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return InspectorUsageError('"$url" is not an absolute URI.');
    }
    return InspectorLaunch(
      LiveMcpSession.url(uri, protocol: protocol, captureSdkLogs: true),
    );
  }
  return const InspectorUsageError('Name a server with --url or -- <command>.');
}

McpProtocol? _protocolFor(String value) => switch (value) {
  'stable' => McpProtocol.stable,
  'legacy' => McpProtocol.legacy,
  '2026' => McpProtocol.require2026,
  _ => null,
};
