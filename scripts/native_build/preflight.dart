import 'dart:io';

import 'package:path/path.dart' as p;

const String requiredNoirOrigin = 'git@github.com:leoafarias/noir.git';
const String requiredPreparationCommit =
    'c5794b6f104a201a7e9dce9a0955417e7f1ea602';
const String requiredOpenTuiCommit = 'ddbc9edf81a1fa89961135ab0481df15054ed4b0';
const String requiredOpenTuiTree = '3d35a9ef9a77ca7e1768d2fbe7191522fe7f59cc';
const int requiredSourceDateEpoch = 1779265080;

final class NativeBuildRequirements {
  const NativeBuildRequirements({
    this.noirOrigin = requiredNoirOrigin,
    this.preparationCommit = requiredPreparationCommit,
    this.openTuiCommit = requiredOpenTuiCommit,
    this.openTuiTree = requiredOpenTuiTree,
  });

  final String noirOrigin;
  final String preparationCommit;
  final String openTuiCommit;
  final String openTuiTree;
}

enum NativeBuildMode { plan, execute }

NativeBuildMode parseNativeBuildMode(List<String> arguments) {
  if (arguments.length != 1) {
    throw const NativeBuildUsageException();
  }
  return switch (arguments.single) {
    '--plan' => NativeBuildMode.plan,
    '--execute-native-build' => NativeBuildMode.execute,
    _ => throw const NativeBuildUsageException(),
  };
}

final class NativeBuildUsageException implements Exception {
  const NativeBuildUsageException();

  static const String usage =
      'Usage: dart run scripts/build_opentui_candidates.dart '
      '<--plan|--execute-native-build>';

  @override
  String toString() => usage;
}

final class NativeBuildPreflightException implements Exception {
  const NativeBuildPreflightException(this.message);

  final String message;

  @override
  String toString() => 'Native build preflight failed: $message';
}

final class PreflightSnapshot {
  const PreflightSnapshot({
    required this.repoRootMatches,
    required this.originUrl,
    required this.headContainsPreparation,
    required this.worktreeClean,
    required this.recipeCommitted,
    required this.gitlink,
    required this.submoduleHead,
    required this.submoduleClean,
    required this.dockerAvailable,
    required this.contextIgnored,
    this.noirCommit = '',
    this.noirTree = '',
    this.openTuiTree = '',
    this.dockerVersion = '',
  });

  final bool repoRootMatches;
  final String originUrl;
  final bool headContainsPreparation;
  final bool worktreeClean;
  final bool recipeCommitted;
  final String gitlink;
  final String submoduleHead;
  final bool submoduleClean;
  final bool dockerAvailable;
  final bool contextIgnored;
  final String noirCommit;
  final String noirTree;
  final String openTuiTree;
  final String dockerVersion;
}

void validatePreflightSnapshot(
  PreflightSnapshot snapshot, {
  NativeBuildRequirements requirements = const NativeBuildRequirements(),
}) {
  final errors = <String>[
    if (!snapshot.repoRootMatches) 'command was not started at the repo root',
    if (snapshot.originUrl != requirements.noirOrigin)
      'origin must be ${requirements.noirOrigin}',
    if (!snapshot.headContainsPreparation)
      'HEAD does not contain ${requirements.preparationCommit}',
    if (!snapshot.worktreeClean) 'Noir worktree is not clean',
    if (!snapshot.recipeCommitted) 'native build recipe is not committed',
    if (snapshot.gitlink != requirements.openTuiCommit)
      'OpenTUI gitlink is not ${requirements.openTuiCommit}',
    if (snapshot.submoduleHead != requirements.openTuiCommit)
      'OpenTUI checkout is not ${requirements.openTuiCommit}',
    if (!snapshot.submoduleClean) 'OpenTUI checkout is not clean',
    if (!snapshot.dockerAvailable) 'Docker client/server is unavailable',
    if (!snapshot.contextIgnored) '.context/ is not ignored by Git',
  ];
  if (errors.isNotEmpty) {
    throw NativeBuildPreflightException(errors.join('; '));
  }
}

final class CommandResult {
  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

abstract interface class CommandRunner {
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

final class IoCommandRunner implements CommandRunner {
  const IoCommandRunner();

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    return CommandResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }
}

final class NativeBuildPreflight {
  const NativeBuildPreflight({
    this.runner = const IoCommandRunner(),
    this.requirements = const NativeBuildRequirements(),
  });

  final CommandRunner runner;
  final NativeBuildRequirements requirements;

  Future<PreflightSnapshot> check(Directory repoRoot) async {
    final root = p.normalize(repoRoot.resolveSymbolicLinksSync());
    final actualRoot = await _stdout('git', const <String>[
      'rev-parse',
      '--show-toplevel',
    ], workingDirectory: root);
    final origin = await _stdout('git', const <String>[
      'remote',
      'get-url',
      'origin',
    ], workingDirectory: root);
    final containsPreparation = await runner.run('git', <String>[
      'merge-base',
      '--is-ancestor',
      requirements.preparationCommit,
      'HEAD',
    ], workingDirectory: root);
    final status = await _run('git', const <String>[
      'status',
      '--porcelain',
      '--untracked-files=all',
    ], workingDirectory: root);
    final recipeDiff = await runner.run('git', const <String>[
      'diff',
      '--quiet',
      'HEAD',
      '--',
      'scripts/build_opentui_candidates.dart',
      'scripts/native_build',
    ], workingDirectory: root);
    final gitlinkOutput = await _stdout('git', const <String>[
      'ls-tree',
      'HEAD',
      'external/opentui',
    ], workingDirectory: root);
    final gitlinkParts = gitlinkOutput.split(RegExp(r'\s+'));
    final submoduleRoot = p.join(root, 'external', 'opentui');
    final submoduleHead = await _stdout('git', const <String>[
      'rev-parse',
      'HEAD',
    ], workingDirectory: submoduleRoot);
    final submoduleTree = await _stdout('git', const <String>[
      'rev-parse',
      'HEAD^{tree}',
    ], workingDirectory: submoduleRoot);
    final submoduleStatus = await _run('git', const <String>[
      'status',
      '--porcelain',
      '--untracked-files=all',
    ], workingDirectory: submoduleRoot);
    final docker = await runner.run('docker', const <String>[
      'version',
      '--format',
      '{{.Client.Version}}/{{.Server.Version}}',
    ], workingDirectory: root);
    final ignored = await runner.run('git', const <String>[
      'check-ignore',
      '.context/native-build-probe',
    ], workingDirectory: root);
    final noirCommit = await _stdout('git', const <String>[
      'rev-parse',
      'HEAD',
    ], workingDirectory: root);
    final noirTree = await _stdout('git', const <String>[
      'rev-parse',
      'HEAD^{tree}',
    ], workingDirectory: root);

    final snapshot = PreflightSnapshot(
      repoRootMatches: p.equals(
        p.normalize(Directory(actualRoot).resolveSymbolicLinksSync()),
        root,
      ),
      originUrl: origin,
      headContainsPreparation: containsPreparation.exitCode == 0,
      worktreeClean: status.stdout.trim().isEmpty,
      recipeCommitted: recipeDiff.exitCode == 0,
      gitlink: gitlinkParts.length >= 3 ? gitlinkParts[2] : '',
      submoduleHead: submoduleHead,
      submoduleClean: submoduleStatus.stdout.trim().isEmpty,
      dockerAvailable: docker.exitCode == 0,
      contextIgnored: ignored.exitCode == 0,
      noirCommit: noirCommit,
      noirTree: noirTree,
      openTuiTree: submoduleTree,
      dockerVersion: docker.stdout.trim(),
    );
    validatePreflightSnapshot(snapshot, requirements: requirements);
    if (snapshot.openTuiTree != requirements.openTuiTree) {
      throw NativeBuildPreflightException(
        'OpenTUI tree is ${snapshot.openTuiTree}, '
        'expected ${requirements.openTuiTree}',
      );
    }
    return snapshot;
  }

  Future<CommandResult> _run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    final result = await runner.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    if (result.exitCode != 0) {
      throw NativeBuildPreflightException(
        '$executable ${arguments.join(' ')} failed: ${result.stderr.trim()}',
      );
    }
    return result;
  }

  Future<String> _stdout(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async => (await _run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  )).stdout.trim();
}
