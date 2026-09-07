import 'dart:io';

/// Compiles a fixture server once and returns the executable to start.
///
/// A fixture cannot be started with `dart run`. On the minimum supported SDK,
/// `dart run` wraps its build hooks in a progress indicator that writes to
/// **stdout** without regard to `--verbosity`
/// (`pkg/dartdev/lib/src/commands/run.dart` and `pkg/dartdev/lib/src/progress.dart`
/// in Dart 3.10.0; 3.11.0 added the verbosity guard). Stdout is the MCP
/// protocol channel, so that text corrupts the server's first JSON-RPC line
/// and the handshake times out.
///
/// The fixtures therefore live in `tools/mcp_fixtures`, which depends only on
/// `package:mcp_dart` and so has no build hook at all. That also lets
/// `dart compile exe` run: the same SDK rejects it for a package graph that
/// does have hooks. A compiled executable then carries only what the server
/// writes on stdout. Each path compiles once per test process.
class CompiledFixtures {
  /// Compiles into a private directory owned by this instance.
  CompiledFixtures({String? workingDirectory})
    : _workingDirectory = workingDirectory ?? Directory.current.path;

  final String _workingDirectory;
  final Map<String, Future<String>> _executables = <String, Future<String>>{};
  Directory? _output;

  /// The executable for [fixture], compiling it on the first request.
  ///
  /// [fixture] is resolved against this instance's working directory, which is
  /// the package root that owns the fixture's dependencies.
  Future<String> executableFor(String fixture) =>
      _executables.putIfAbsent(fixture, () => _compile(fixture));

  Future<String> _compile(String fixture) async {
    final output = _output ??= Directory.systemTemp.createTempSync(
      'noir-mcp-fixtures-',
    );
    final name = fixture.split(Platform.pathSeparator).last.split('/').last;
    final base = name.endsWith('.dart')
        ? name.substring(0, name.length - '.dart'.length)
        : name;
    final target =
        '${output.path}${Platform.pathSeparator}$base'
        '${Platform.isWindows ? '.exe' : ''}';
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'compile',
      'exe',
      fixture,
      '-o',
      target,
    ], workingDirectory: _workingDirectory);
    if (result.exitCode != 0) {
      throw StateError(
        'dart compile exe $fixture failed in $_workingDirectory\n'
        'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
    }
    return target;
  }

  /// Removes every executable this instance compiled.
  void dispose() {
    final output = _output;
    _output = null;
    _executables.clear();
    if (output != null && output.existsSync()) {
      output.deleteSync(recursive: true);
    }
  }
}
