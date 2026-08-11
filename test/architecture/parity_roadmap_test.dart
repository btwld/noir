import 'dart:io';

import 'package:test/test.dart';

/// Light structural checks for the parity roadmap. Plan inventory under the
/// review-fix gate is the authority for recipe correctness; this file only
/// guards against reintroduction of a few high-cost stale tokens.
void main() {
  final plan = File('tasks/plan.md').readAsStringSync();

  test('parity roadmap uses READ_HERE workflow, not unavailable skills', () {
    expect(plan, contains('tasks/READ_HERE.md'));
    expect(plan, isNot(contains('superpowers:subagent-driven-development')));
    expect(plan, isNot(contains('superpowers:executing-plans')));
  });

  test('parity roadmap reuses BufferCapture and bans new testing harness', () {
    expect(plan, contains('BufferCapture'));
    expect(plan, contains('test/helpers/buffer_capture.dart'));
    expect(
      plan,
      isNot(contains('Create: `lib/src/testing/widget_scene_snapshot.dart`')),
    );
    expect(plan, isNot(contains('final renderer = Renderer.create')));
    expect(plan, isNot(contains('renderer.debugCurrentBuffer')));
  });

  test('parity roadmap wire contracts and gates', () {
    expect(plan, isNot(contains('_serializeRGBA')));
    expect(plan, isNot(contains('RGBA(1, 0, 0, 1)')));
    expect(
      plan,
      isNot(
        contains('Harden Snapshot Serialization Only for Active Widget Fields'),
      ),
    );
    expect(
      plan,
      contains('Consolidate and Remove the Manual Widget Snapshot Lane'),
    );
    expect(plan, contains('superseded, not implemented'));
    expect(
      plan,
      contains(
        'inventories every caller and migrates any unique semantic assertion',
      ),
    );
    expect(plan, contains('no replacement serializer or'));
    expect(plan, contains('fifth harness is introduced'));
    expect(plan, contains('exact-three'));
    expect(plan, contains('read-only for this roadmap'));
    expect(plan, contains('upstream-triggered cleanup'));
    expect(
      plan,
      isNot(contains('reachable OpenTUI-fork commit through a separately')),
    );
    expect(
      plan,
      contains('Local parity-roadmap completion requires all three statements'),
    );
    expect(plan, contains('Task 4 / P9-039 remains visibly open and optional'));
    expect(plan, contains('does not block local parity-roadmap'));
    expect(plan, matches(RegExp(r'P9-041 is\s+administratively closed')));
    // Centered W2/W3 geometry (not top-left y=0 for both).
    expect(plan, contains('DrawText("Left", 0, 2'));
    expect(plan, contains('DrawText("Line 1", 7, 0'));
  });

  test('manual widget snapshot lane stays retired', () {
    String joined(String first, String second, [String third = '']) =>
        '$first$second$third';

    for (final obsoletePath in <String>[
      joined('test/helpers/snapshot', '_utils.dart'),
      joined('test/snapshots/widget_snapshot', '_test.dart'),
    ]) {
      expect(
        File(obsoletePath).existsSync(),
        isFalse,
        reason: 'obsolete widget snapshot lane returned at $obsoletePath',
      );
    }

    final goldenTesting = File(
      'test/helpers/golden_testing.dart',
    ).readAsStringSync();
    for (final staleToken in <String>[
      joined('Snapshot', 'Serializer'),
      joined('Snapshot', 'Utils'),
      joined('expectGolden', 'Snapshot'),
      '.snapshot',
      "type == 'snapshot'",
      "type == 'golden'",
    ]) {
      expect(
        goldenTesting,
        isNot(contains(staleToken)),
        reason: 'GoldenTester revived retired surface: $staleToken',
      );
    }

    final dartTestConfig = File('dart_test.yaml').readAsStringSync();
    for (final staleToken in <String>[
      '`snapshot` tests use',
      'snapshot:',
      joined('-P ', 'snapshot'),
      joined('include_tags: ', 'snapshot'),
    ]) {
      expect(
        dartTestConfig,
        isNot(contains(staleToken)),
        reason: 'dart_test.yaml revived widget snapshot lane: $staleToken',
      );
    }

    final helperGuide = File('test/helpers/README.md').readAsStringSync();
    for (final staleToken in <String>[
      joined('expectGolden', 'Snapshot'),
      joined('.golden', '.json'),
      joined('snapshot', '_utils.dart'),
      joined("@Tags(['", 'snapshot', "'])"),
      joined('-P ', 'snapshot'),
      '## Snapshot tests',
    ]) {
      expect(
        helperGuide,
        isNot(contains(staleToken)),
        reason: 'helper guide revived widget snapshot lane: $staleToken',
      );
    }

    final testGuide = File('test/README.md').readAsStringSync();
    for (final staleToken in <String>[
      'capture, snapshot, and golden infrastructure',
      joined('test/helpers/snapshot', '_utils.dart'),
      'broadening snapshots or goldens',
    ]) {
      expect(
        testGuide,
        isNot(contains(staleToken)),
        reason: 'test guide revived widget snapshot lane: $staleToken',
      );
    }

    for (final parityPath in <String>[
      'bin/snapshot_scenes.dart',
      'scripts/run_go_snapshot.sh',
      'test/parity/primitives_parity_test.dart',
      'test/parity/widget_parity_test.dart',
      'tools/parity/go_snapshot/main.go',
    ]) {
      expect(
        File(parityPath).existsSync(),
        isTrue,
        reason: 'parity cell-snapshot protocol missing $parityPath',
      );
    }
  });
}
