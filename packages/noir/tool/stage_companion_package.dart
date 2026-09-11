#!/usr/bin/env dart

/// Stages `packages/noir_signals/` outside this checkout as a standalone
/// package.
///
/// The companion publishes in place from its own directory. The staged copy is
/// what an application outside this Pub workspace resolves, so the
/// companion's consumer check and pre-release verification run against it.
///
/// The staged copy drops `resolution: workspace`, which only resolves inside
/// this repository's Pub workspace, and points `noir` at this checkout through
/// `pubspec_overrides.yaml` so the companion resolves before Noir's matching
/// version is published. `pubspec_overrides.yaml` stays out of the archive.
///
/// Usage:
///
///     dart run tool/stage_companion_package.dart [--output <dir>]
///     dart run tool/stage_companion_package.dart --verify
///
/// `--verify` runs `dart pub get` and `dart pub publish --dry-run` in the
/// staged copy and fails when the dry-run reports a warning.
library;

import 'dart:io';

const _companionPath = '../noir_signals';

/// Entries the staged copy never carries, matched at the package root only.
///
/// `.pubignore` decides the archive; this list only keeps local build state
/// and a stale override out of the copy.
const _skippedRootEntries = <String>{
  '.dart_tool',
  'build',
  'pubspec_overrides.yaml',
};
const _usage =
    'Usage: dart run tool/stage_companion_package.dart '
    '[--output <dir>] [--verify]';

Future<void> main(List<String> arguments) async {
  exitCode = await _stage(arguments);
}

Future<int> _stage(List<String> arguments) async {
  String? output;
  var verify = false;
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--verify') {
      verify = true;
    } else if (argument == '--output') {
      index++;
      if (index >= arguments.length) {
        stderr.writeln(_usage);
        return 64;
      }
      output = arguments[index];
    } else {
      stderr.writeln('Unknown argument: $argument\n$_usage');
      return 64;
    }
  }

  final noirRoot = Directory.current.absolute;
  final companion = Directory('${noirRoot.path}/$_companionPath');
  if (!companion.existsSync()) {
    stderr.writeln(
      'Run this from packages/noir: $_companionPath is '
      'missing.',
    );
    return 66;
  }

  final Directory destination;
  if (output == null) {
    destination = Directory.systemTemp.createTempSync('noir_signals_stage_');
  } else {
    if (File(output).existsSync()) {
      stderr.writeln('Refusing to stage over a file: $output');
      return 73;
    }
    destination = Directory(output)..createSync(recursive: true);
    if (destination.listSync().isNotEmpty) {
      stderr.writeln(
        'Refusing to stage into a non-empty directory: ${destination.path}',
      );
      return 73;
    }
  }

  _copyDirectory(companion, destination, skipRootEntries: true);
  _rewritePubspec(destination);
  _writeNoirOverride(destination, noirRoot);

  stdout.writeln('Staged $_companionPath at ${destination.path}');
  if (!verify) {
    return 0;
  }

  final get = await _run(Platform.resolvedExecutable, <String>[
    'pub',
    'get',
  ], destination);
  if (get != 0) {
    return get;
  }
  return _runPublishDryRun(destination);
}

void _copyDirectory(
  Directory from,
  Directory to, {
  bool skipRootEntries = false,
}) {
  for (final entity in from.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    if (skipRootEntries && _skippedRootEntries.contains(name)) {
      continue;
    }
    final target = '${to.path}${Platform.pathSeparator}$name';
    switch (entity) {
      case final Directory directory:
        _copyDirectory(directory, Directory(target)..createSync());
      case final File file:
        file.copySync(target);
      case final Link link:
        // A published package must not depend on a link this copy would
        // silently resolve or drop.
        throw StateError('$_companionPath cannot contain links: ${link.path}');
    }
  }
}

/// Removes `resolution: workspace`, which is only valid inside the workspace.
void _rewritePubspec(Directory staged) {
  final pubspec = File('${staged.path}/pubspec.yaml');
  final lines = pubspec.readAsLinesSync();
  final kept = <String>[];
  for (final line in lines) {
    if (line.trim() == 'resolution: workspace') {
      continue;
    }
    kept.add(line);
  }
  if (kept.length == lines.length) {
    throw StateError('Staged pubspec has no `resolution: workspace` line.');
  }
  pubspec.writeAsStringSync('${kept.join('\n')}\n');
}

void _writeNoirOverride(Directory staged, Directory noirRoot) {
  File('${staged.path}/pubspec_overrides.yaml').writeAsStringSync(
    'dependency_overrides:\n'
    '  noir:\n'
    '    path: ${noirRoot.path}\n',
  );
}

Future<int> _run(
  String executable,
  List<String> arguments,
  Directory workingDirectory,
) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

Future<int> _runPublishDryRun(Directory staged) async {
  final result = await Process.run(Platform.resolvedExecutable, <String>[
    'pub',
    'publish',
    '--dry-run',
  ], workingDirectory: staged.path);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    return result.exitCode;
  }
  final report = '${result.stdout}\n${result.stderr}';
  if (!report.contains('Package has 0 warnings')) {
    stderr.writeln('Companion publish dry-run reported a warning.');
    return 1;
  }
  return 0;
}
