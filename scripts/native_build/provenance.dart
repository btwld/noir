import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'safe_fs.dart';

final class BuildProvenanceInputs {
  const BuildProvenanceInputs({
    required this.runId,
    required this.startedAtUtc,
    required this.finishedAtUtc,
    required this.noirCommit,
    required this.noirTree,
    required this.recipeCommit,
    required this.recipeDigest,
    required this.openTuiCommit,
    required this.openTuiTree,
    required this.runnerImageDigest,
    required this.runnerArchiveSha256,
    required this.versions,
    required this.commands,
    required this.normalizedHashes,
    required this.resolvedDependencies,
  });

  final String runId;
  final DateTime startedAtUtc;
  final DateTime finishedAtUtc;
  final String noirCommit;
  final String noirTree;
  final String recipeCommit;
  final String recipeDigest;
  final String openTuiCommit;
  final String openTuiTree;
  final String runnerImageDigest;
  final String runnerArchiveSha256;
  final Map<String, String> versions;
  final List<List<String>> commands;
  final Map<String, String> normalizedHashes;
  final Map<String, String> resolvedDependencies;
}

Map<String, Object?> buildInformation(BuildProvenanceInputs inputs) =>
    <String, Object?>{
      'schema': 'noir-native-build-information-v1',
      'runId': inputs.runId,
      'startedAtUtc': inputs.startedAtUtc.toUtc().toIso8601String(),
      'finishedAtUtc': inputs.finishedAtUtc.toUtc().toIso8601String(),
      'source': <String, Object?>{
        'noirCommit': inputs.noirCommit,
        'noirTree': inputs.noirTree,
        'recipeCommit': inputs.recipeCommit,
        'recipeDigest': inputs.recipeDigest,
        'openTuiCommit': inputs.openTuiCommit,
        'openTuiTree': inputs.openTuiTree,
      },
      'runner': <String, Object?>{
        'imageDigest': inputs.runnerImageDigest,
        'archiveSha256': inputs.runnerArchiveSha256,
      },
      'versions': inputs.versions,
      'commands': inputs.commands,
      'normalizedHashes': inputs.normalizedHashes,
      'resolvedDependencies': inputs.resolvedDependencies,
    };

Map<String, Object?> slsaProvenance(BuildProvenanceInputs inputs) =>
    <String, Object?>{
      '_type': 'https://in-toto.io/Statement/v1',
      'subject': inputs.normalizedHashes.entries
          .map(
            (entry) => <String, Object?>{
              'name': entry.key,
              'digest': <String, String>{'sha256': entry.value},
            },
          )
          .toList(),
      'predicateType': 'https://slsa.dev/provenance/v1',
      'predicate': <String, Object?>{
        'buildDefinition': <String, Object?>{
          'buildType': 'https://github.com/leoafarias/noir/native-build/v1',
          'externalParameters': <String, Object?>{
            'mode': 'local-unsigned',
            'commands': inputs.commands,
          },
          'resolvedDependencies': inputs.resolvedDependencies.entries
              .map(
                (entry) => <String, Object?>{
                  'uri': entry.key,
                  'digest': <String, String>{'sha256': entry.value},
                },
              )
              .toList(),
        },
        'runDetails': <String, Object?>{
          'builder': <String, Object?>{
            'id': 'local-unsigned:noir-native-build-wrapper',
          },
          'metadata': <String, Object?>{
            'invocationId': inputs.runId,
            'startedOn': inputs.startedAtUtc.toUtc().toIso8601String(),
            'finishedOn': inputs.finishedAtUtc.toUtc().toIso8601String(),
          },
        },
      },
    };

String canonicalJson(Object? value) =>
    '${const JsonEncoder.withIndent('  ').convert(_canonicalize(value))}\n';

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is Iterable) return value.map(_canonicalize).toList();
  return value;
}

final class EvidenceInventoryEntry {
  const EvidenceInventoryEntry({
    required this.relativePath,
    required this.size,
    required this.sha256,
  });

  final String relativePath;
  final int size;
  final String sha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': relativePath,
    'sha256': sha256,
    'size': size,
  };
}

Future<List<EvidenceInventoryEntry>> inventoryFiles(Directory root) async {
  final files =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final entries = <EvidenceInventoryEntry>[];
  for (final file in files) {
    final bytes = await file.readAsBytes();
    entries.add(
      EvidenceInventoryEntry(
        relativePath: p.relative(file.path, from: root.path),
        size: bytes.length,
        sha256: sha256.convert(bytes).toString(),
      ),
    );
  }
  return entries;
}

final class RecoveryItem {
  const RecoveryItem({required this.source, required this.relativeDestination});

  final FileSystemEntity source;
  final String relativeDestination;
}

final class MirrorVerification {
  const MirrorVerification({
    required this.relativePath,
    required this.sha256,
    required this.verified,
  });

  final String relativePath;
  final String sha256;
  final bool verified;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': relativePath,
    'sha256': sha256,
    'verified': verified,
  };
}

Future<List<MirrorVerification>> mirrorRecoveryItems({
  required Directory destination,
  required List<RecoveryItem> items,
  required List<String> workspaceRoots,
}) async {
  requireExternalRecoveryDestination(
    destination: destination.path,
    workspaceRoots: workspaceRoots,
  );
  destination.createSync(recursive: true);
  final verifications = <MirrorVerification>[];
  for (final item in items) {
    if (p.isAbsolute(item.relativeDestination) ||
        p.split(p.normalize(item.relativeDestination)).contains('..')) {
      throw UnsafeNativeBuildPathException(
        'invalid recovery path ${item.relativeDestination}',
      );
    }
    if (item.source is File) {
      verifications.add(
        await _copyAndVerify(
          item.source as File,
          destination,
          item.relativeDestination,
        ),
      );
    } else if (item.source is Directory) {
      final sourceDirectory = item.source as Directory;
      for (final entry in await inventoryFiles(sourceDirectory)) {
        verifications.add(
          await _copyAndVerify(
            File(p.join(sourceDirectory.path, entry.relativePath)),
            destination,
            p.join(item.relativeDestination, entry.relativePath),
          ),
        );
      }
    } else {
      throw StateError('Recovery source is not a file or directory');
    }
  }
  verifications.sort((a, b) => a.relativePath.compareTo(b.relativePath));
  return verifications;
}

Future<MirrorVerification> _copyAndVerify(
  File source,
  Directory destination,
  String relativePath,
) async {
  final target = File(p.join(destination.path, relativePath));
  target.parent.createSync(recursive: true);
  final sourceBytes = await source.readAsBytes();
  final sourceHash = sha256.convert(sourceBytes).toString();
  if (target.existsSync()) {
    final existingHash = sha256.convert(await target.readAsBytes()).toString();
    if (existingHash != sourceHash) {
      throw StateError('Refusing to overwrite mismatched recovery file');
    }
  } else {
    await target.writeAsBytes(sourceBytes, flush: true);
  }
  final targetHash = sha256.convert(await target.readAsBytes()).toString();
  return MirrorVerification(
    relativePath: relativePath,
    sha256: sourceHash,
    verified: targetHash == sourceHash,
  );
}
