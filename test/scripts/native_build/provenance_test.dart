import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../scripts/native_build/provenance.dart';

void main() {
  test('build information and unsigned SLSA v1 provenance are stable', () {
    final inputs = BuildProvenanceInputs(
      runId: '20260811T120000Z-abcdef12',
      startedAtUtc: DateTime.utc(2026, 8, 11, 12),
      finishedAtUtc: DateTime.utc(2026, 8, 11, 13),
      noirCommit: 'noir-commit',
      noirTree: 'noir-tree',
      recipeCommit: 'recipe-commit',
      recipeDigest: 'recipe-digest',
      openTuiCommit: 'opentui-commit',
      openTuiTree: 'opentui-tree',
      runnerImageDigest: 'sha256:image',
      runnerArchiveSha256: 'archive-hash',
      versions: const <String, String>{
        'zig': '0.14.1',
        'llvm': '19.1.7',
        'docker': '29.7.2',
      },
      commands: const <List<String>>[
        <String>['docker', 'run', '--network=none'],
      ],
      normalizedHashes: const <String, String>{
        'aarch64-linux': 'hash-a',
        'x86_64-linux': 'hash-x',
      },
      resolvedDependencies: const <String, String>{
        'zig': 'f7a654',
        'opentui': 'ddbc9edf',
      },
    );

    final first = canonicalJson(buildInformation(inputs));
    final second = canonicalJson(buildInformation(inputs));
    expect(first, second);
    expect(
      first.indexOf('"aarch64-linux"'),
      lessThan(first.indexOf('"x86_64-linux"')),
    );

    final statement = slsaProvenance(inputs);
    expect(statement['_type'], 'https://in-toto.io/Statement/v1');
    expect(statement['predicateType'], 'https://slsa.dev/provenance/v1');
    final predicate = statement['predicate']! as Map<String, Object?>;
    expect(predicate['buildDefinition'], isA<Map<String, Object?>>());
    expect(predicate['runDetails'], isA<Map<String, Object?>>());
    expect(canonicalJson(statement), contains('local-unsigned'));
  });

  test('inventory and mirror are sorted, hashed, and reverified', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'noir_native_provenance.',
    );
    addTearDown(() async {
      if (sandbox.existsSync()) await sandbox.delete(recursive: true);
    });
    final source = Directory(p.join(sandbox.path, 'source'))..createSync();
    File(p.join(source.path, 'z.txt')).writeAsStringSync('z');
    Directory(p.join(source.path, 'nested')).createSync();
    File(p.join(source.path, 'nested', 'a.txt')).writeAsStringSync('a');

    final entries = await inventoryFiles(source);
    expect(entries.map((entry) => entry.relativePath), <String>[
      'nested/a.txt',
      'z.txt',
    ]);
    expect(entries.every((entry) => entry.sha256.length == 64), isTrue);

    final mirror = Directory(p.join(sandbox.path, 'external-mirror'));
    final result = await mirrorRecoveryItems(
      destination: mirror,
      items: <RecoveryItem>[
        RecoveryItem(source: source, relativeDestination: 'evidence'),
      ],
      workspaceRoots: <String>[p.join(sandbox.path, 'workspace')],
    );
    expect(result.every((entry) => entry.verified), isTrue);
    expect(
      File(
        p.join(mirror.path, 'evidence', 'nested', 'a.txt'),
      ).readAsStringSync(),
      'a',
    );
    expect(
      jsonDecode(canonicalJson(result.map((entry) => entry.toJson()).toList())),
      isA<List<Object?>>(),
    );
  });
}
