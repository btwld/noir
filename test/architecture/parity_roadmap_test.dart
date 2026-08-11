import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('manual widget snapshot lane stays retired', () {
    for (final obsoletePath in <String>[
      'test/helpers/snapshot_utils.dart',
      'test/snapshots/widget_snapshot_test.dart',
      'lib/src/testing/widget_scene_snapshot.dart',
    ]) {
      expect(
        File(obsoletePath).existsSync(),
        isFalse,
        reason: 'obsolete snapshot lane returned at $obsoletePath',
      );
    }

    final goldenTesting = _read('test/helpers/golden_testing.dart');
    for (final staleToken in <String>[
      'SnapshotSerializer',
      'SnapshotUtils',
      'expectGoldenSnapshot',
      '.snapshot',
      "type == 'snapshot'",
      "type == 'golden'",
    ]) {
      expect(
        goldenTesting,
        isNot(contains(staleToken)),
        reason: 'retired snapshot surface returned: $staleToken',
      );
    }
  });

  test('parity protocol keeps one Dart capture path and six scenes', () {
    for (final path in <String>[
      'bin/snapshot_scenes.dart',
      'scripts/run_go_snapshot.sh',
      'test/parity/primitives_parity_test.dart',
      'test/parity/widget_parity_test.dart',
      'tools/parity/go_snapshot/main.go',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }

    final dartScenes = _read('bin/snapshot_scenes.dart');
    final goScenes = _read('tools/parity/go_snapshot/main.go');
    for (final scene in <String>['S1', 'S2', 'S3', 'W1', 'W2', 'W3']) {
      expect(dartScenes, contains("'$scene'"), reason: scene);
      expect(goScenes, contains('"$scene"'), reason: scene);
    }
    expect(dartScenes, contains('BufferCapture'));
    expect(dartScenes, isNot(contains('Renderer.create')));
    expect(dartScenes, isNot(contains('debugCurrentBuffer')));
  });

  test('parity wrapper preserves the read-only compatibility boundary', () {
    final wrapper = _read('scripts/run_go_snapshot.sh');

    expect(wrapper, contains('external/opentui'));
    expect(wrapper, contains('read-only compatibility shim'));
    expect(wrapper, isNot(contains('tasks/plan.md')));
    expect(wrapper, isNot(contains('git checkout')));
    expect(wrapper, isNot(contains('git commit')));
    expect(wrapper, isNot(contains('git push')));
  });

  test('test configuration does not revive snapshot presets', () {
    final config = _read('dart_test.yaml');
    final testGuide = _read('test/README.md');
    final helperGuide = _read('test/helpers/README.md');

    for (final source in <String>[config, testGuide, helperGuide]) {
      for (final staleToken in <String>[
        'include_tags: snapshot',
        '-P snapshot',
        "@Tags(['snapshot'])",
        'expectGoldenSnapshot',
        'snapshot_utils.dart',
      ]) {
        expect(source, isNot(contains(staleToken)), reason: staleToken);
      }
    }
  });
}

String _read(String path) => File(path).readAsStringSync();
