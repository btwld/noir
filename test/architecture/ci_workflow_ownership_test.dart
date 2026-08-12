import 'dart:io';

import 'package:test/test.dart';

const _safeProcessTests = <String>[
  'test/bin/health_check_test.dart',
  'test/rendering/flex_validation_release_test.dart',
  'test/rendering/geometry_constraints_test.dart',
  'test/rendering/paragraph_max_lines_test.dart',
  'test/rendering/render_setter_invalidation_release_test.dart',
  'test/source_package_consumer_test.dart',
  'test/widgets/geometry_validation_test.dart',
  'test/widgets/text_editing_owner_release_test.dart',
  'test/widgets/text_max_lines_release_test.dart',
];

void main() {
  final workflow = _read('.github/workflows/ci.yml');

  test('CI targets master with least privilege and cancellation', () {
    expect(workflow, contains('branches: [master]'));
    expect(workflow, isNot(contains('branches: [master, main]')));
    expect(workflow, contains('permissions:\n  contents: read'));
    expect(
      workflow,
      contains(r'group: ${{ github.workflow }}-${{ github.ref }}'),
    );
    expect(workflow, contains('cancel-in-progress: true'));
  });

  test('all workflow actions use immutable full SHA references', () {
    final actionLines = workflow
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('uses:'));

    expect(actionLines, isNotEmpty);
    for (final line in actionLines) {
      expect(
        line,
        matches(RegExp(r'^uses: [^@ ]+@[0-9a-f]{40}(?: # v[^ ]+)?$')),
        reason: 'mutable or malformed action reference: $line',
      );
    }
  });

  test('CI bounds native wrapper validation without building candidates', () {
    final start = workflow.indexOf('  native-wrapper:');
    expect(start, isNonNegative);
    final end = workflow.indexOf('\n  test:', start);
    expect(end, greaterThan(start));

    final job = workflow.substring(start, end);
    expect(job, contains('timeout-minutes: 10'));
    expect(
      RegExp(r'^\s+timeout-minutes: 5$', multiLine: true).allMatches(job),
      hasLength(2),
    );
    expect(
      job,
      contains(
        'dart test test/scripts/native_build/normalization_policy_test.dart '
        '--concurrency=1',
      ),
    );
    expect(
      job,
      contains('dart run scripts/build_opentui_candidates.dart --plan'),
    );
    expect(
      job,
      contains('git remote set-url origin git@github.com:leoafarias/noir.git'),
    );
    expect(job, isNot(contains('--execute-native-build')));
    expect(job, isNot(contains('actions/upload-artifact')));
    expect(job, isNot(contains('actions/download-artifact')));
    expect(job, isNot(contains('secrets.')));
    expect(job, isNot(contains('dart pub publish')));
    expect(
      job,
      isNot(
        contains(
          'dart test --exclude-tags restricted-process-lifecycle '
          '--concurrency=1',
        ),
      ),
    );
  });

  test('ordinary subprocess tests are distinct from restricted lifecycle', () {
    for (final path in _safeProcessTests) {
      final source = _read(path);
      expect(
        source,
        contains('safe-process-spawning'),
        reason: '$path must use the ordinary subprocess tag',
      );
      expect(source, isNot(contains('restricted-process-lifecycle')));
      expect(source, isNot(matches(RegExp("[\"']process-spawning[\"']"))));
    }

    const wrapperPath = 'test/parity/go_snapshot_wrapper_test.dart';
    final wrapper = _read(wrapperPath);
    expect(wrapper, contains("@Tags(['restricted-process-lifecycle'])"));
    expect(wrapper, isNot(contains('safe-process-spawning')));

    final restrictedOwners = <String>[];
    for (final entity in Directory('test').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains('/architecture/')) continue;
      if (RegExp(
        "@Tags\\(\\[[\"']restricted-process-lifecycle[\"']\\]\\)",
      ).hasMatch(_read(entity.path))) {
        restrictedOwners.add(entity.path);
      }
    }
    expect(restrictedOwners, [wrapperPath]);

    final config = _read('dart_test.yaml');
    expect(config, contains('  safe-process-spawning:'));
    expect(config, contains('  restricted-process-lifecycle:'));
    expect(
      config,
      isNot(matches(RegExp('^  process-spawning:', multiLine: true))),
    );
  });

  test('CI runs safe tests and selects parity without wrapper lifecycle', () {
    expect(
      workflow,
      contains(
        'dart test --exclude-tags restricted-process-lifecycle --concurrency=1',
      ),
    );
    expect(workflow, isNot(contains('test/bin/health_check_test.dart')));
    expect(workflow, contains('test/parity/primitives_parity_test.dart'));
    expect(workflow, contains('test/parity/widget_parity_test.dart'));
    expect(
      workflow,
      isNot(contains('test/parity/go_snapshot_wrapper_test.dart')),
    );
    expect(
      workflow,
      isNot(matches(RegExp(r'dart test[^\n]*test/parity(?:/|\s|$)'))),
    );
    expect(workflow, contains('GO_SNAPSHOT_CMD: ./scripts/run_go_snapshot.sh'));
  });

  test('CI covers all supported desktop operating systems', () {
    expect(workflow, contains('ubuntu-latest'));
    expect(workflow, contains('macos-latest'));
    expect(workflow, contains('windows-latest'));
    expect(workflow, contains('fail-fast: false'));
  });
}

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');
