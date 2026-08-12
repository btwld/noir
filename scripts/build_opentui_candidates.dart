#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'native_build/container.dart';
import 'native_build/driver.dart';
import 'native_build/plan.dart';
import 'native_build/preflight.dart';
import 'native_build/workflow.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runNativeBuildCommand(
    arguments,
    repoRoot: Directory.current,
    checkPreflight: const NativeBuildPreflight().check,
    printPlan: _printPlan,
    executeBuild: _executeBuild,
    emitError: stderr.writeln,
  );
}

typedef PreflightCheck = Future<PreflightSnapshot> Function(Directory repoRoot);
typedef PlanPrinter =
    void Function(Directory repoRoot, PreflightSnapshot snapshot);
typedef BuildExecutor =
    Future<void> Function(Directory repoRoot, PreflightSnapshot snapshot);

Future<int> runNativeBuildCommand(
  List<String> arguments, {
  required Directory repoRoot,
  required PreflightCheck checkPreflight,
  required PlanPrinter printPlan,
  required BuildExecutor executeBuild,
  required void Function(String message) emitError,
}) async {
  late final NativeBuildMode mode;
  try {
    mode = parseNativeBuildMode(arguments);
  } on NativeBuildUsageException catch (error) {
    emitError('$error');
    return 64;
  }

  try {
    final snapshot = await checkPreflight(repoRoot);
    if (mode == NativeBuildMode.plan) {
      printPlan(repoRoot, snapshot);
    } else {
      await executeBuild(repoRoot, snapshot);
    }
    return 0;
  } on Object catch (error) {
    emitError('$error');
    return 1;
  }
}

void _printPlan(Directory repoRoot, PreflightSnapshot snapshot) {
  _validateRecipe(repoRoot);
  stdout.writeln('Noir OpenTUI native candidate plan');
  stdout.writeln('repo=${repoRoot.absolute.path}');
  stdout.writeln('recipe-commit=${snapshot.noirCommit}');
  final recipe = repoRoot.uri
      .resolve('scripts/native_build/recipe/')
      .toFilePath();
  final imageTag =
      'noir-native-builder:${snapshot.noirCommit.substring(0, 12)}';
  stdout.writeln(
    jsonEncode(<String>[
      'docker',
      'build',
      '--platform=linux/arm64',
      '--no-cache',
      '--pull',
      '--tag',
      imageTag,
      '--file',
      '${recipe}Dockerfile',
      recipe,
    ]),
  );
  for (final root in nativeBuildRoots) {
    stdout.writeln('${root.label}: source=${root.sourceMount}');
    for (final target in root.targets) {
      stdout.writeln(
        '  ${target.name}: zig=${target.zigTargetQuery} '
        'output=${target.outputFileName}',
      );
      final invocation = buildTargetContainerInvocation(
        imageReference: imageTag,
        root: root,
        target: target,
        sourcePath: '<RUN_DIR>/sources/${root.label}/opentui',
        outputPath: '<RUN_DIR>/build-roots/${root.label}/output',
        cachePath: '<RUN_DIR>/build-roots/${root.label}/cache',
        globalCachePath: '<RUN_DIR>/build-roots/${root.label}/global-cache',
        sourceDateEpoch: requiredSourceDateEpoch,
      );
      stdout.writeln(
        jsonEncode(<String>[invocation.executable, ...invocation.arguments]),
      );
    }
  }
}

Future<void> _executeBuild(
  Directory repoRoot,
  PreflightSnapshot snapshot,
) async {
  _validateRecipe(repoRoot);
  final driver = IoNativeBuildDriver(repoRoot: repoRoot, preflight: snapshot);
  await NativeBuildWorkflow(driver).execute();
}

void _validateRecipe(Directory repoRoot) {
  final dockerfile = File(
    repoRoot.uri.resolve('scripts/native_build/recipe/Dockerfile').toFilePath(),
  );
  final seed = File(
    repoRoot.uri
        .resolve('scripts/native_build/recipe/seed_zig_cache.sh')
        .toFilePath(),
  );
  if (!dockerfile.existsSync() || !seed.existsSync()) {
    throw const NativeBuildPreflightException('runner recipe is incomplete');
  }
  final recipe = '${dockerfile.readAsStringSync()}\n${seed.readAsStringSync()}';
  for (final pin in const <String>[
    runnerBaseDigest,
    debianSnapshot,
    zigArchiveSha256,
    zigMinisignPublicKey,
    zgPackageHash,
  ]) {
    if (!recipe.contains(pin)) {
      throw NativeBuildPreflightException('runner recipe lacks pin $pin');
    }
  }
}
