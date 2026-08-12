import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:noir/src/ffi/abi_contract.dart';
import 'package:path/path.dart' as p;

import 'container.dart';
import 'inspect.dart';
import 'plan.dart';
import 'preflight.dart';
import 'provenance.dart';
import 'safe_fs.dart';
import 'workflow.dart';

const String runnerBaseDigest =
    'sha256:817e6cf99d6fc127ff4ffe8580049b60deba0adfbbb2bd65ddc3ef8fbb7aade0';
const String zigArchiveSha256 =
    'f7a654acc967864f7a050ddacfaa778c7504a0eca8d2b678839c21eea47c992b';
const String zigMinisignPublicKey =
    'RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U';
const String zgPackageHash =
    'zg-0.14.1-oGqU3IQ_tALZIiBN026_NTaPJqU-Upm8P_C7QED2Rzm8';
const String debianSnapshot = '20260801T000000Z';

const List<String> protectedNativeBuildPaths = <String>[
  'native_manifest.json',
  'native/linux/arm64/libopentui.so',
  'native/linux/x64/libopentui.so',
  'native/macos/arm64/libopentui.dylib',
  'native/macos/x64/libopentui.dylib',
  'native/windows/arm64/libopentui.dll',
  'native/windows/x64/libopentui.dll',
  'lib/src/ffi/abi_contract.dart',
  'lib/src/ffi/bindings.dart',
  'lib/src/ffi/generated_bindings.dart',
  'lib/src/ffi/native_asset_bindings.dart',
  'lib/src/ffi/native_symbols.dart',
];

final class IoNativeBuildDriver implements NativeBuildDriver {
  IoNativeBuildDriver({
    required Directory repoRoot,
    required this.preflight,
    this.runner = const IoCommandRunner(),
    void Function(String message)? emit,
    DateTime Function()? now,
    String Function()? entropy,
    Directory? recoveryMirrorRoot,
  }) : repoRoot = Directory(repoRoot.resolveSymbolicLinksSync()),
       emit = emit ?? stdout.writeln,
       now = now ?? (() => DateTime.now().toUtc()),
       entropy = entropy ?? _secureEntropy,
       recoveryMirrorRoot = recoveryMirrorRoot ?? _defaultRecoveryMirrorRoot();

  final Directory repoRoot;
  final PreflightSnapshot preflight;
  final CommandRunner runner;
  final void Function(String message) emit;
  final DateTime Function() now;
  final String Function() entropy;
  final Directory recoveryMirrorRoot;

  late final DateTime _startedAt;
  late final String _runId;
  late final Directory _runDirectory;
  late final Directory _evidenceDirectory;
  late final Directory _logsDirectory;
  late final Directory _recoveryDirectory;
  late final String _imageTag;
  late final String _imageDigest;
  late final File _runnerArchive;
  late final String _runnerArchiveHash;
  late final String _recipeDigest;
  late final Map<String, String> _protectedBefore;
  final Map<String, Directory> _sourceRoots = <String, Directory>{};
  final List<List<String>> _commands = <List<String>>[];
  final Map<String, String> _runnerVersions = <String, String>{};
  var _commandSequence = 0;
  var _runCreated = false;

  @override
  Future<void> begin() async {
    _startedAt = now().toUtc();
    _runId = '${_compactUtc(_startedAt)}-${entropy()}';
    _runDirectory = createOwnedRunDirectory(repoRoot: repoRoot, runId: _runId);
    _runCreated = true;
    _evidenceDirectory = Directory(p.join(_runDirectory.path, 'evidence'))
      ..createSync(recursive: true);
    _logsDirectory = Directory(p.join(_evidenceDirectory.path, 'commands'))
      ..createSync(recursive: true);
    _recoveryDirectory = Directory(
      p.join(repoRoot.path, '.context', 'recovery'),
    )..createSync(recursive: true);
    requireUntrackedBuildDestination(
      repoRoot: repoRoot,
      destination: _runDirectory.path,
    );
    requireUntrackedBuildDestination(
      repoRoot: repoRoot,
      destination: _recoveryDirectory.path,
    );
    _protectedBefore = await _hashProtectedPaths();
    _recipeDigest = await _aggregateRecipeDigest();
    _writeJson('preflight.json', <String, Object?>{
      'runId': _runId,
      'noirCommit': preflight.noirCommit,
      'noirTree': preflight.noirTree,
      'openTuiCommit': preflight.submoduleHead,
      'openTuiTree': preflight.openTuiTree,
      'dockerVersion': preflight.dockerVersion,
      'protectedPaths': _protectedBefore,
    });
    emit('Native build run: $_runId');
    await _buildAndPreserveRunner();
  }

  @override
  Future<void> prepareRoot(NativeBuildRoot root) async {
    emit('Preparing ${root.label} at ${root.sourceMount}');
    final rootDirectory = Directory(
      p.join(_runDirectory.path, 'sources', root.label, 'opentui'),
    );
    rootDirectory.parent.createSync(recursive: true);
    await _runChecked('git', <String>[
      'clone',
      '--no-hardlinks',
      '--no-checkout',
      p.join(repoRoot.path, 'external', 'opentui'),
      rootDirectory.path,
    ], workingDirectory: repoRoot.path);
    await _runChecked('git', <String>[
      'checkout',
      '--detach',
      requiredOpenTuiCommit,
    ], workingDirectory: rootDirectory.path);
    _normalizeSourceMtimes(rootDirectory);
    await _verifySourceRoot(rootDirectory, root.label);
    _sourceRoots[root.label] = rootDirectory;

    final output = _rootDirectory(root, 'output')..createSync(recursive: true);
    final cache = _rootDirectory(root, 'cache')..createSync(recursive: true);
    final globalCache = _rootDirectory(root, 'global-cache')
      ..createSync(recursive: true);
    requireUntrackedBuildDestination(
      repoRoot: repoRoot,
      destination: output.path,
    );
    requireUntrackedBuildDestination(
      repoRoot: repoRoot,
      destination: cache.path,
    );
    requireUntrackedBuildDestination(
      repoRoot: repoRoot,
      destination: globalCache.path,
    );
    final seed = _hardenedRunArguments(
      mounts: <String>[
        'type=bind,src=${globalCache.path},dst=${root.globalCacheMount}',
      ],
      command: <String>[
        '/bin/sh',
        '-ceu',
        'umask 022; cp -a /opt/zig-global-cache/. ${root.globalCacheMount}/',
      ],
    );
    await _runChecked('docker', seed, workingDirectory: repoRoot.path);
  }

  @override
  Future<NativeArtifactEvidence> buildAndInspect(
    NativeBuildRoot root,
    NativeBuildTarget target,
  ) async {
    emit('Building ${root.label}/${target.name}');
    final source = _sourceRoots[root.label]!;
    final output = _rootDirectory(root, 'output');
    final cache = _rootDirectory(root, 'cache');
    final globalCache = _rootDirectory(root, 'global-cache');
    final invocation = buildTargetContainerInvocation(
      imageReference: _imageDigest,
      root: root,
      target: target,
      sourcePath: source.path,
      outputPath: output.path,
      cachePath: cache.path,
      globalCachePath: globalCache.path,
      sourceDateEpoch: requiredSourceDateEpoch,
    );
    await _runChecked(
      invocation.executable,
      invocation.arguments,
      workingDirectory: repoRoot.path,
    );

    final builtDirectory = Directory(p.join(output.path, 'lib', target.name));
    if (!builtDirectory.existsSync()) {
      throw NativeBuildWorkflowException(
        '${root.label}/${target.name} produced no output directory',
      );
    }
    final outputFiles =
        builtDirectory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((file) => p.relative(file.path, from: builtDirectory.path))
            .toList()
          ..sort();
    final expectedOutputFiles = <String>[
      target.buildOutputFileName,
      ...target.buildAuxiliaryFileNames,
    ]..sort();
    if (outputFiles.length != expectedOutputFiles.length ||
        outputFiles.indexed.any(
          (entry) => entry.$2 != expectedOutputFiles[entry.$1],
        )) {
      throw NativeBuildWorkflowException(
        '${root.label}/${target.name} expected '
        '${expectedOutputFiles.join(', ')}; found ${outputFiles.join(', ')}',
      );
    }
    final builtFile = File(
      p.join(builtDirectory.path, target.buildOutputFileName),
    );
    final artifactRoot = Directory(
      p.join(_evidenceDirectory.path, 'artifacts', root.label, target.name),
    )..createSync(recursive: true);
    final raw = File(p.join(artifactRoot.path, 'raw', target.outputFileName));
    final normalized = File(
      p.join(artifactRoot.path, 'normalized', target.outputFileName),
    );
    raw.parent.createSync(recursive: true);
    normalized.parent.createSync(recursive: true);
    await builtFile.copy(raw.path);
    await raw.copy(normalized.path);
    final rawHash = await _hashFile(raw);

    await _runTool(normalized.parent, <String>[
      'llvm-strip',
      '--discard-all',
      '/work/artifact/${target.outputFileName}',
    ]);
    final normalizedHash = await _hashFile(normalized);
    final header = await _runTool(normalized.parent, <String>[
      'llvm-readobj',
      '--file-headers',
      '/work/artifact/${target.outputFileName}',
    ]);
    final exports = await _runTool(normalized.parent, <String>[
      'llvm-nm',
      '--defined-only',
      '--extern-only',
      '/work/artifact/${target.outputFileName}',
    ]);
    final strings = await _runTool(normalized.parent, <String>[
      'llvm-strings',
      '/work/artifact/${target.outputFileName}',
    ]);
    final versions = target.isMacOs
        ? await _runTool(normalized.parent, <String>[
            'llvm-objdump',
            '--macho',
            '--private-headers',
            '/work/artifact/${target.outputFileName}',
          ])
        : '';
    inspectArtifact(
      ArtifactInspection(
        target: target,
        executableFileNames: <String>[p.basename(normalized.path)],
        fileHeaderOutput: header,
        exportOutput: exports,
        versionOutput: versions,
        printableStrings: strings,
        forbiddenPathFragments: <String>[
          repoRoot.path,
          _runDirectory.path,
          for (final buildRoot in nativeBuildRoots) ...<String>[
            buildRoot.sourceMount,
            buildRoot.outputMount,
            buildRoot.cacheMount,
            buildRoot.globalCacheMount,
          ],
        ],
      ),
    );
    _writeJson(p.join('inspections', '${root.label}-${target.name}.json'), <
      String,
      Object?
    >{
      'target': target.name,
      'rawSha256': rawHash,
      'normalizedSha256': normalizedHash,
      'header': header,
      'exports': exports.split('\n').where((line) => line.isNotEmpty).toList(),
      'version': versions,
      'pathScan': 'passed',
    });
    return NativeArtifactEvidence(
      targetName: target.name,
      rawSha256: rawHash,
      normalizedSha256: normalizedHash,
    );
  }

  @override
  Future<void> verifyRoot(NativeBuildRoot root) async {
    await _verifySourceRoot(_sourceRoots[root.label]!, root.label);
  }

  @override
  Future<void> verifyHealthAndPackage(NativeBuildResult result) async {
    if (!Platform.isMacOS || Abi.current() != Abi.macosArm64) {
      throw NativeBuildWorkflowException(
        'host health check requires macOS arm64; found ${Abi.current()}',
      );
    }
    final hostCandidate = _normalizedArtifact(
      'root-a',
      nativeBuildTargets.singleWhere(
        (target) => target.name == 'aarch64-macos',
      ),
    );
    await _runHealthCheck(
      workingDirectory: repoRoot.path,
      command: <String>[
        Platform.resolvedExecutable,
        'run',
        'bin/health_check.dart',
      ],
      libraryPath: hostCandidate.path,
      label: 'host-candidate-health',
    );

    final packageSnapshot = Directory(
      p.join(_runDirectory.path, 'package-snapshot'),
    );
    await _runChecked('git', <String>[
      'clone',
      '--no-hardlinks',
      '--no-checkout',
      repoRoot.path,
      packageSnapshot.path,
    ], workingDirectory: repoRoot.path);
    await _runChecked('git', <String>[
      'checkout',
      '--detach',
      preflight.noirCommit,
    ], workingDirectory: packageSnapshot.path);
    final manifestAssets = <String, Object?>{};
    for (final target in nativeBuildTargets) {
      final source = _normalizedArtifact('root-a', target);
      final (os, arch) = _packageTarget(target);
      final relativePath = p.join('native', os, arch, target.outputFileName);
      final destination = File(p.join(packageSnapshot.path, relativePath));
      destination.parent.createSync(recursive: true);
      await source.copy(destination.path);
      manifestAssets['$os-$arch'] = <String, Object?>{
        'os': os,
        'arch': arch,
        'path': relativePath,
        'url': 'candidate-only://${target.name}',
        'archivePath': '',
        if (target.isMacOs) 'minimumOsVersion': '15.0',
        'sha256': result.normalizedHashes[target.name],
      };
    }
    final candidateManifest =
        File(
          p.join(packageSnapshot.path, 'native_manifest.json'),
        )..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'abiVersion': expectedOpenTuiAbiVersion, 'assets': manifestAssets})}\n',
          flush: true,
        );
    final evidenceManifest = File(
      p.join(
        _evidenceDirectory.path,
        'health',
        'candidate-native_manifest.json',
      ),
    );
    evidenceManifest.parent.createSync(recursive: true);
    await candidateManifest.copy(evidenceManifest.path);
    await _runChecked(Platform.resolvedExecutable, const <String>[
      'pub',
      'get',
      '--offline',
    ], workingDirectory: packageSnapshot.path);
    await _runHealthCheck(
      workingDirectory: packageSnapshot.path,
      command: <String>[
        Platform.resolvedExecutable,
        'run',
        'noir:health_check',
      ],
      label: 'package-snapshot-health',
    );
    final buildOutput = p.join(
      packageSnapshot.path,
      'build',
      'noir-health-check',
    );
    await _runChecked(Platform.resolvedExecutable, <String>[
      'build',
      'cli',
      '-t',
      'bin/health_check.dart',
      '-o',
      buildOutput,
    ], workingDirectory: packageSnapshot.path);
    final builtHealth = packagedCliExecutablePath(
      buildOutput,
      'bin/health_check.dart',
    );
    await _runHealthCheck(
      workingDirectory: packageSnapshot.path,
      command: <String>[builtHealth],
      label: 'packaged-cli-health',
    );
  }

  @override
  Future<void> verifyProtectedState() async {
    await _verifySourceRoot(
      Directory(p.join(repoRoot.path, 'external', 'opentui')),
      'original-submodule',
    );
    final protectedAfter = await _hashProtectedPaths();
    if (!_mapsEqual(_protectedBefore, protectedAfter)) {
      throw const NativeBuildWorkflowException(
        'a protected tracked artifact changed during the build',
      );
    }
    final status = await _runChecked('git', const <String>[
      'status',
      '--porcelain',
      '--untracked-files=all',
    ], workingDirectory: repoRoot.path);
    if (status.trim().isNotEmpty) {
      throw NativeBuildWorkflowException(
        'Noir worktree changed during build: $status',
      );
    }
    await _runChecked(Platform.resolvedExecutable, const <String>[
      'run',
      'scripts/fetch_opentui_binaries.dart',
      '--verify-only',
    ], workingDirectory: repoRoot.path);
    _writeJson('protected-paths.json', <String, Object?>{
      'before': _protectedBefore,
      'after': protectedAfter,
      'verified': true,
    });
  }

  @override
  Future<void> finalizeSuccess(NativeBuildResult result) async {
    final finishedAt = now().toUtc();
    final rootAHashes = <String, String>{
      for (final artifact in result.rootA)
        artifact.targetName: artifact.normalizedSha256,
    };
    final rootBHashes = <String, String>{
      for (final artifact in result.rootB)
        artifact.targetName: artifact.normalizedSha256,
    };
    final rootARawHashes = <String, String>{
      for (final artifact in result.rootA)
        artifact.targetName: artifact.rawSha256,
    };
    final rootBRawHashes = <String, String>{
      for (final artifact in result.rootB)
        artifact.targetName: artifact.rawSha256,
    };
    _writeJson('hashes.json', <String, Object?>{
      'rootA': <String, Object?>{
        'raw': rootARawHashes,
        'normalized': rootAHashes,
      },
      'rootB': <String, Object?>{
        'raw': rootBRawHashes,
        'normalized': rootBHashes,
      },
      'identical': true,
    });
    final provenanceInputs = BuildProvenanceInputs(
      runId: _runId,
      startedAtUtc: _startedAt,
      finishedAtUtc: finishedAt,
      noirCommit: preflight.noirCommit,
      noirTree: preflight.noirTree,
      recipeCommit: preflight.noirCommit,
      recipeDigest: _recipeDigest,
      openTuiCommit: preflight.submoduleHead,
      openTuiTree: preflight.openTuiTree,
      runnerImageDigest: _imageDigest,
      runnerArchiveSha256: _runnerArchiveHash,
      versions: <String, String>{
        'dart': Platform.version,
        'docker': preflight.dockerVersion,
        ..._runnerVersions,
        'host': '${Platform.operatingSystem}/${Abi.current()}',
      },
      commands: _commands,
      normalizedHashes: result.normalizedHashes,
      resolvedDependencies: const <String, String>{
        'debianBase': runnerBaseDigest,
        'debianSnapshot': debianSnapshot,
        'zigArchive': zigArchiveSha256,
        'zigMinisignPublicKey': zigMinisignPublicKey,
        'zgPackage': zgPackageHash,
        'openTui': requiredOpenTuiCommit,
      },
    );
    File(
      p.join(_evidenceDirectory.path, 'build-information.json'),
    ).writeAsStringSync(canonicalJson(buildInformation(provenanceInputs)));
    File(
      p.join(_evidenceDirectory.path, 'provenance.slsa.json'),
    ).writeAsStringSync(canonicalJson(slsaProvenance(provenanceInputs)));
    _writeJson('success.json', <String, Object?>{
      'runId': _runId,
      'finishedAtUtc': finishedAt.toIso8601String(),
      'matchedCandidates': result.normalizedHashes,
      'trackedArtifactsReplaced': false,
    });
    final inventory = await inventoryFiles(_evidenceDirectory);
    final inventoryFile =
        File(p.join(_evidenceDirectory.path, 'inventory.json'))
          ..writeAsStringSync(
            canonicalJson(inventory.map((entry) => entry.toJson()).toList()),
            flush: true,
          );
    final inventoryHash = await _hashFile(inventoryFile);
    File(
      p.join(_evidenceDirectory.path, 'inventory.sha256'),
    ).writeAsStringSync('$inventoryHash  inventory.json\n', flush: true);

    final mirror = Directory(p.join(recoveryMirrorRoot.path, _runId));
    final recoveryItems = <RecoveryItem>[
      RecoveryItem(source: _evidenceDirectory, relativeDestination: 'evidence'),
      RecoveryItem(
        source: _runnerArchive,
        relativeDestination: p.join('runner', p.basename(_runnerArchive.path)),
      ),
      RecoveryItem(
        source: File('${_runnerArchive.path}.sha256'),
        relativeDestination: p.join(
          'runner',
          '${p.basename(_runnerArchive.path)}.sha256',
        ),
      ),
      for (final entity in _recoveryDirectory.listSync().where(
        (entity) => p.basename(entity.path).startsWith('noir-prep-c5794b6.'),
      ))
        RecoveryItem(
          source: entity,
          relativeDestination: p.join('phase-1', p.basename(entity.path)),
        ),
    ];
    final mirrorVerification = await mirrorRecoveryItems(
      destination: mirror,
      items: recoveryItems,
      workspaceRoots: <String>[repoRoot.path],
    );
    final mirrorReport =
        File(
          p.join(_recoveryDirectory.path, '$_runId-mirror-verification.json'),
        )..writeAsStringSync(
          canonicalJson(<String, Object?>{
            'mirror': mirror.path,
            'files': mirrorVerification.map((entry) => entry.toJson()).toList(),
          }),
          flush: true,
        );
    emit('Evidence: ${_evidenceDirectory.path}');
    emit('Recovery mirror: ${mirror.path}');
    emit('Mirror verification: ${mirrorReport.path}');
    for (final target in nativeBuildTargets) {
      emit('${target.name}  ${result.normalizedHashes[target.name]}');
    }
  }

  @override
  Future<void> recordFailure(Object error, StackTrace stackTrace) async {
    if (!_runCreated) {
      emit('Native build failed before a run directory was created: $error');
      return;
    }
    _writeJson('failure.json', <String, Object?>{
      'runId': _runId,
      'failedAtUtc': now().toUtc().toIso8601String(),
      'error': '$error',
      'stackTrace': '$stackTrace',
      'matchedCandidateDesignation': false,
    });
    emit(
      'Native build failed; retained evidence at ${_evidenceDirectory.path}',
    );
  }

  Future<void> _buildAndPreserveRunner() async {
    _imageTag = 'noir-native-builder:${preflight.noirCommit.substring(0, 12)}';
    final recipe = p.join(repoRoot.path, 'scripts', 'native_build', 'recipe');
    await _runChecked('docker', <String>[
      'build',
      '--platform=linux/arm64',
      '--no-cache',
      '--pull',
      '--tag',
      _imageTag,
      '--file',
      p.join(recipe, 'Dockerfile'),
      recipe,
    ], workingDirectory: repoRoot.path);
    final imageInfo = await _runChecked('docker', <String>[
      'image',
      'inspect',
      '--format',
      '{{.Id}}|{{.Architecture}}|{{.Os}}',
      _imageTag,
    ], workingDirectory: repoRoot.path);
    final imageParts = imageInfo.trim().split('|');
    if (imageParts.length != 3 ||
        imageParts[0].isEmpty ||
        imageParts[1] != 'arm64' ||
        imageParts[2] != 'linux') {
      throw NativeBuildWorkflowException(
        'runner image has unexpected identity: ${imageInfo.trim()}',
      );
    }
    _imageDigest = imageParts[0];
    final versionOutput = await _runChecked(
      'docker',
      _hardenedRunArguments(
        command: const <String>[
          '/bin/sh',
          '-ceu',
          'cat /opt/noir-runner/tool-versions.txt; cat /opt/noir-runner/debian-packages.txt',
        ],
      ),
      workingDirectory: repoRoot.path,
    );
    if (!versionOutput.split('\n').contains('0.14.1')) {
      throw const NativeBuildWorkflowException(
        'runner did not report exact Zig 0.14.1',
      );
    }
    _runnerVersions['zig'] = '0.14.1';
    _runnerVersions['runnerInventory'] = versionOutput.trim();
    _runnerArchive = File(
      p.join(
        _recoveryDirectory.path,
        'noir-native-runner-${_imageDigest.substring(7, 19)}.tar',
      ),
    );
    await _runChecked('docker', <String>[
      'image',
      'save',
      '--output',
      _runnerArchive.path,
      _imageDigest,
    ], workingDirectory: repoRoot.path);
    _runnerArchiveHash = await _hashFile(_runnerArchive);
    File('${_runnerArchive.path}.sha256').writeAsStringSync(
      '$_runnerArchiveHash  ${p.basename(_runnerArchive.path)}\n',
      flush: true,
    );
    _writeJson('runner.json', <String, Object?>{
      'tag': _imageTag,
      'imageDigest': _imageDigest,
      'baseDigest': runnerBaseDigest,
      'debianSnapshot': debianSnapshot,
      'recipeDigest': _recipeDigest,
      'archive': _runnerArchive.path,
      'archiveSize': _runnerArchive.lengthSync(),
      'archiveSha256': _runnerArchiveHash,
      'toolAndPackageInventory': versionOutput,
    });
  }

  List<String> _hardenedRunArguments({
    required List<String> command,
    List<String> mounts = const <String>[],
  }) => <String>[
    'run',
    '--rm',
    '--platform=linux/arm64',
    '--network=none',
    '--cap-drop=ALL',
    '--security-opt',
    'no-new-privileges',
    '--read-only',
    '--hostname',
    'noir-native-build',
    '--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=512m',
    '--tmpfs=/run:rw,noexec,nosuid,nodev,size=16m',
    '--env',
    'TZ=UTC',
    '--env',
    'LANG=C.UTF-8',
    '--env',
    'LC_ALL=C.UTF-8',
    '--env',
    'SOURCE_DATE_EPOCH=$requiredSourceDateEpoch',
    for (final mount in mounts) ...<String>['--mount', mount],
    _imageDigest,
    ...command,
  ];

  Future<String> _runTool(Directory artifactDirectory, List<String> command) =>
      _runChecked(
        'docker',
        _hardenedRunArguments(
          mounts: <String>[
            'type=bind,src=${artifactDirectory.path},dst=/work/artifact',
          ],
          command: command,
        ),
        workingDirectory: repoRoot.path,
      );

  Future<void> _verifySourceRoot(Directory source, String label) async {
    final head = (await _runChecked('git', const <String>[
      'rev-parse',
      'HEAD',
    ], workingDirectory: source.path)).trim();
    final tree = (await _runChecked('git', const <String>[
      'rev-parse',
      'HEAD^{tree}',
    ], workingDirectory: source.path)).trim();
    final status = (await _runChecked('git', const <String>[
      'status',
      '--porcelain',
      '--untracked-files=all',
    ], workingDirectory: source.path)).trim();
    if (head != requiredOpenTuiCommit ||
        tree != requiredOpenTuiTree ||
        status.isNotEmpty) {
      throw NativeBuildWorkflowException(
        '$label source drifted: head=$head tree=$tree status=$status',
      );
    }
  }

  Future<void> _runHealthCheck({
    required String workingDirectory,
    required List<String> command,
    required String label,
    String? libraryPath,
  }) async {
    final output = await _runChecked(
      command.first,
      command.skip(1).toList(),
      workingDirectory: workingDirectory,
      environment: libraryPath == null
          ? null
          : <String, String>{'OPENTUI_LIBRARY_PATH': libraryPath},
    );
    if (_containsTerminalControl(output)) {
      throw NativeBuildWorkflowException(
        '$label emitted terminal control bytes',
      );
    }
    _writeJson(p.join('health', '$label.json'), <String, Object?>{
      'libraryOverride': libraryPath,
      'output': output,
      'terminalControlBytes': false,
    });
  }

  Future<String> _runChecked(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String>? environment,
  }) async {
    final command = <String>[executable, ...arguments];
    _commands.add(command);
    final startedAt = now().toUtc();
    final result = await runner.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final completedAt = now().toUtc();
    _commandSequence++;
    final logName = '${_commandSequence.toString().padLeft(4, '0')}.json';
    File(p.join(_logsDirectory.path, logName)).writeAsStringSync(
      canonicalJson(<String, Object?>{
        'argv': command,
        'workingDirectory': workingDirectory,
        'environment': environment ?? const <String, String>{},
        'startedAtUtc': startedAt.toIso8601String(),
        'completedAtUtc': completedAt.toIso8601String(),
        'exitCode': result.exitCode,
        'stdout': result.stdout,
        'stderr': result.stderr,
      }),
      flush: true,
    );
    if (result.exitCode != 0) {
      throw NativeBuildWorkflowException(
        '${command.join(' ')} exited ${result.exitCode}: '
        '${result.stderr.trim()}',
      );
    }
    return '${result.stdout}${result.stderr}';
  }

  Future<Map<String, String>> _hashProtectedPaths() async {
    final hashes = <String, String>{};
    for (final relativePath in protectedNativeBuildPaths) {
      final file = File(p.join(repoRoot.path, relativePath));
      if (!file.existsSync()) {
        throw NativeBuildWorkflowException(
          'protected path is missing: $relativePath',
        );
      }
      hashes[relativePath] = await _hashFile(file);
    }
    hashes['external/opentui.gitlink'] = preflight.gitlink;
    return hashes;
  }

  Future<String> _aggregateRecipeDigest() async {
    final recipe = Directory(
      p.join(repoRoot.path, 'scripts', 'native_build', 'recipe'),
    );
    final inventory = await inventoryFiles(recipe);
    final aggregate = inventory
        .map((entry) => '${entry.relativePath}\u0000${entry.sha256}\n')
        .join();
    return sha256.convert(utf8.encode(aggregate)).toString();
  }

  void _normalizeSourceMtimes(Directory source) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      requiredSourceDateEpoch * 1000,
      isUtc: true,
    );
    final gitDirectory = p.join(source.path, '.git');
    final entities = source
        .listSync(recursive: true, followLinks: false)
        .where(
          (entity) =>
              !p.equals(gitDirectory, entity.path) &&
              !p.isWithin(gitDirectory, entity.path),
        )
        .toList();
    for (final entity in entities.whereType<File>()) {
      entity.setLastModifiedSync(timestamp);
    }
  }

  Directory _rootDirectory(NativeBuildRoot root, String name) =>
      Directory(p.join(_runDirectory.path, 'build-roots', root.label, name));

  File _normalizedArtifact(String rootLabel, NativeBuildTarget target) => File(
    p.join(
      _evidenceDirectory.path,
      'artifacts',
      rootLabel,
      target.name,
      'normalized',
      target.outputFileName,
    ),
  );

  void _writeJson(String relativePath, Object? value) {
    final file = File(p.join(_evidenceDirectory.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(canonicalJson(value), flush: true);
  }
}

Future<String> _hashFile(File file) async =>
    sha256.convert(await file.readAsBytes()).toString();

String packagedCliExecutablePath(String outputRoot, String targetPath) =>
    p.join(outputRoot, 'bundle', 'bin', p.basenameWithoutExtension(targetPath));

(String, String) _packageTarget(NativeBuildTarget target) {
  final os = switch (target.format) {
    NativeArtifactFormat.elf => 'linux',
    NativeArtifactFormat.machO => 'macos',
    NativeArtifactFormat.coff => 'windows',
  };
  final arch = switch (target.architecture) {
    NativeArchitecture.x86_64 => 'x64',
    NativeArchitecture.aarch64 => 'arm64',
  };
  return (os, arch);
}

bool _containsTerminalControl(String output) {
  for (final codeUnit in output.codeUnits) {
    if ((codeUnit < 0x20 &&
            codeUnit != 0x09 &&
            codeUnit != 0x0a &&
            codeUnit != 0x0d) ||
        codeUnit == 0x7f ||
        codeUnit == 0x9b) {
      return true;
    }
  }
  return output.contains('\u001b');
}

bool _mapsEqual(Map<String, String> left, Map<String, String> right) {
  if (left.length != right.length) return false;
  return left.entries.every((entry) => right[entry.key] == entry.value);
}

String _compactUtc(DateTime dateTime) {
  final utc = dateTime.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}'
      '${two(utc.month)}${two(utc.day)}T'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}

String _secureEntropy() =>
    Random.secure().nextInt(0x100000000).toRadixString(16).padLeft(8, '0');

Directory _defaultRecoveryMirrorRoot() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty || !p.isAbsolute(home)) {
    throw const UnsafeNativeBuildPathException(
      'cannot resolve the default recovery directory',
    );
  }
  return Directory(p.join(home, 'noir-release-recovery'));
}
