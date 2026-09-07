#!/usr/bin/env dart

/// Stages `packages/noir_signals/` outside this checkout so pub can archive it.
///
/// Pub applies the ignore files of every ancestor directory, so the root
/// package's `.pubignore` rule that keeps `packages/` out of the `noir`
/// archive also hides the companion's own files when the companion is
/// published in place. Copying the package to a directory outside the
/// repository removes that ancestor and lets the companion's own `.pubignore`
/// decide its archive by itself.
///
/// The staged copy drops `resolution: workspace`, which only resolves inside
/// this repository's Pub workspace, and points `noir` at this checkout through
/// `pubspec_overrides.yaml` so the companion resolves before Noir's matching
/// version is published. `pubspec_overrides.yaml` stays out of the archive.
///
/// Usage:
///
///     dart run scripts/stage_companion_package.dart [--output <dir>]
///     dart run scripts/stage_companion_package.dart --verify
///
/// `--verify` runs `dart pub get` and `dart pub publish --dry-run` in the
/// staged copy and fails when the dry-run reports a warning.
library;

import 'dart:io';

const _companionPath = 'packages/noir_signals';
const _skippedEntries = <String>{
  '.dart_tool',
  'build',
  'pubspec_overrides.yaml',
};
const _usage =
    'Usage: dart run scripts/stage_companion_package.dart '
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

  final repositoryRoot = Directory.current.absolute;
  final companion = Directory('${repositoryRoot.path}/$_companionPath');
  if (!companion.existsSync()) {
    stderr.writeln(
      'Run this from the repository root: $_companionPath is '
      'missing.',
    );
    return 66;
  }

  final destination = output == null
      ? Directory.systemTemp.createTempSync('noir_signals_stage_')
      : (Directory(output)..createSync(recursive: true));
  if (output != null && destination.listSync().isNotEmpty) {
    stderr.writeln(
      'Refusing to stage into a non-empty directory: '
      '${destination.path}',
    );
    return 73;
  }

  _copyDirectory(companion, destination);
  _rewritePubspec(destination);
  _writeNoirOverride(destination, repositoryRoot);

  stdout.writeln('Staged $_companionPath at ${destination.path}');
  if (!verify) {
    return 0;
  }

  final get = await _run('dart', <String>['pub', 'get'], destination);
  if (get != 0) {
    return get;
  }
  return _runPublishDryRun(destination);
}

void _copyDirectory(Directory from, Directory to) {
  for (final entity in from.listSync()) {
    final name = entity.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    if (_skippedEntries.contains(name)) {
      continue;
    }
    final target = '${to.path}${Platform.pathSeparator}$name';
    if (entity is Directory) {
      _copyDirectory(entity, Directory(target)..createSync(recursive: true));
    } else if (entity is File) {
      entity.copySync(target);
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

void _writeNoirOverride(Directory staged, Directory repositoryRoot) {
  File('${staged.path}/pubspec_overrides.yaml').writeAsStringSync(
    'dependency_overrides:\n'
    '  noir:\n'
    '    path: ${repositoryRoot.path}\n',
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
