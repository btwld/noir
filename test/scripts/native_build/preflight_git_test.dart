@Tags(['safe-process-spawning'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../scripts/native_build/preflight.dart';

void main() {
  late Directory sandbox;
  late Directory repo;
  late NativeBuildRequirements requirements;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('noir_native_preflight.');
    final source = Directory(p.join(sandbox.path, 'opentui-source'))
      ..createSync();
    await _git(source, <String>['init']);
    await _configureGit(source);
    File(p.join(source.path, 'source.txt')).writeAsStringSync('source\n');
    await _git(source, <String>['add', 'source.txt']);
    await _git(source, <String>['commit', '-m', 'source']);
    final sourceCommit = await _gitStdout(source, <String>[
      'rev-parse',
      'HEAD',
    ]);
    final sourceTree = await _gitStdout(source, <String>[
      'rev-parse',
      'HEAD^{tree}',
    ]);

    repo = Directory(p.join(sandbox.path, 'repo'))..createSync();
    await _git(repo, <String>['init']);
    await _configureGit(repo);
    await _git(repo, <String>['remote', 'add', 'origin', 'fixture-origin']);
    File(p.join(repo.path, '.gitignore')).writeAsStringSync('.context/\n');
    Directory(
      p.join(repo.path, 'scripts', 'native_build', 'recipe'),
    ).createSync(recursive: true);
    File(
      p.join(repo.path, 'scripts', 'build_opentui_candidates.dart'),
    ).writeAsStringSync('void main() {}\n');
    File(
      p.join(repo.path, 'scripts', 'native_build', 'recipe', 'Dockerfile'),
    ).writeAsStringSync('FROM scratch\n');
    await _git(repo, <String>[
      '-c',
      'protocol.file.allow=always',
      'submodule',
      'add',
      source.path,
      'external/opentui',
    ]);
    await _git(repo, <String>['add', '.']);
    await _git(repo, <String>['commit', '-m', 'fixture']);
    final head = await _gitStdout(repo, <String>['rev-parse', 'HEAD']);
    requirements = NativeBuildRequirements(
      noirOrigin: 'fixture-origin',
      preparationCommit: head,
      openTuiCommit: sourceCommit,
      openTuiTree: sourceTree,
    );
  });

  tearDown(() async {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  test(
    'real Git fixture accepts exact committed state and rejects dirt',
    () async {
      final preflight = NativeBuildPreflight(
        runner: const _DockerAvailableRunner(),
        requirements: requirements,
      );
      final clean = await preflight.check(repo);
      expect(clean.worktreeClean, isTrue);
      expect(clean.submoduleClean, isTrue);

      File(p.join(repo.path, 'untracked.txt')).writeAsStringSync('dirty\n');
      await expectLater(
        preflight.check(repo),
        throwsA(isA<NativeBuildPreflightException>()),
      );
    },
  );
}

final class _DockerAvailableRunner implements CommandRunner {
  const _DockerAvailableRunner();

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    if (executable == 'docker') {
      return Future<CommandResult>.value(
        const CommandResult(
          exitCode: 0,
          stdout: 'fixture-client/fixture-server\n',
          stderr: '',
        ),
      );
    }
    return const IoCommandRunner().run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }
}

Future<void> _configureGit(Directory directory) async {
  await _git(directory, <String>['config', 'user.name', 'Noir Test']);
  await _git(directory, <String>[
    'config',
    'user.email',
    'noir-test@example.invalid',
  ]);
}

Future<void> _git(Directory directory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory.path,
  );
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed:\n${result.stderr}');
  }
}

Future<String> _gitStdout(Directory directory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory.path,
  );
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed:\n${result.stderr}');
  }
  return '${result.stdout}'.trim();
}
