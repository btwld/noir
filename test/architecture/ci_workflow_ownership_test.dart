import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('CI runs feature work once and cancels superseded runs', () {
    final workflow = File(
      '.github/workflows/ci.yml',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(
      workflow,
      contains(
        'on:\n'
        '  push:\n'
        '    branches: [master, main]\n'
        '  pull_request:\n'
        '\n'
        'concurrency:\n'
        r'  group: ${{ github.workflow }}-${{ github.ref }}'
        '\n'
        '  cancel-in-progress: true\n',
      ),
    );
  });

  test('CI isolates process-spawning tests from native-asset full suite', () {
    final workflow = File(
      '.github/workflows/ci.yml',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final parity = _jobSection(workflow, 'parity', 'consumer-smoke');
    final wrapperTests = File(
      'test/parity/go_snapshot_wrapper_test.dart',
    ).readAsStringSync();

    expect(workflow, isNot(contains('lfs: true')));
    expect(parity, contains('submodules: recursive'));
    expect(parity, contains('actions/setup-go@v5'));
    expect(
      parity,
      contains('go-version-file: tools/parity/go_snapshot/go.mod'),
    );
    expect(parity, contains('cache: false'));
    expect(parity, contains('sudo apt-get install -y pkg-config'));
    expect(
      parity,
      contains('dart test test/bin/health_check_test.dart --concurrency=1'),
    );
    expect(
      workflow,
      contains('dart test --exclude-tags process-spawning --concurrency=1'),
    );
    expect(parity, contains('GO_SNAPSHOT_CMD: ./scripts/run_go_snapshot.sh'));
    expect(
      parity,
      contains(
        'set +e'
        '\n'
        r'          timeout --signal=TERM --kill-after=30s 30m \'
        '\n'
        r'            dart test -r expanded test/parity --concurrency=1 \'
        '\n'
        r'            >"$parity_log" 2>&1'
        '\n'
        r'          parity_status=$?'
        '\n'
        '          set -e'
        '\n'
        r'          cat "$parity_log"'
        '\n'
        r'          exit "$parity_status"',
      ),
    );
    expect(parity, contains(r'parity_log="$RUNNER_TEMP/linux-go-parity.log"'));
    expect(parity, contains('timeout-minutes: 35'));
    expect(
      RegExp(
        RegExp.escape('GO_SNAPSHOT_CMD: ./scripts/run_go_snapshot.sh'),
      ).allMatches(workflow),
      hasLength(1),
    );
    expect(
      RegExp(
        RegExp.escape('dart test -r expanded test/parity --concurrency=1'),
      ).allMatches(workflow),
      hasLength(1),
    );
    expect(
      RegExp(RegExp.escape('timeout-minutes: 35')).allMatches(workflow),
      hasLength(1),
    );
    expect(wrapperTests, contains("@Tags(['process-spawning'])"));
    expect(workflow, isNot(contains(RegExp(r'run: dart test\s*$'))));
  });

  test('CI renders the full suite on Linux, macOS, and Windows', () {
    final workflow = File(
      '.github/workflows/ci.yml',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    // The render suite must run on all three desktop OSes, not Linux alone.
    expect(workflow, contains('ubuntu-latest'));
    expect(workflow, contains('macos-latest'));
    expect(workflow, contains('windows-latest'));
    // Every leg reports independently rather than cancelling its siblings.
    expect(workflow, contains('fail-fast: false'));
    // The cross-platform legs run the rendering suite, not just FFI smoke.
    expect(
      workflow,
      contains('dart test --exclude-tags process-spawning --concurrency=1'),
    );
  });
}

String _jobSection(String workflow, String name, String nextName) {
  final start = workflow.indexOf('  $name:');
  final end = workflow.indexOf('  $nextName:', start + 1);
  expect(start, greaterThan(-1), reason: 'missing $name job');
  expect(end, greaterThan(start), reason: 'missing $nextName job');
  return workflow.substring(start, end);
}
