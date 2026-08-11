import 'dart:io';

import 'package:test/test.dart';

void main() {
  final workflow = File(
    '.github/workflows/release.yml',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  test('release runs once per ref without cancelling tag releases', () {
    expect(
      workflow,
      contains(
        'on:\n'
        '  push:\n'
        '    branches: [master, main]\n'
        "    tags: ['v*']\n"
        '  workflow_dispatch:\n'
        '\n'
        'concurrency:\n'
        r'  group: ${{ github.workflow }}-${{ github.ref }}'
        '\n'
        r"  cancel-in-progress: ${{ !startsWith(github.ref, 'refs/tags/v') }}"
        '\n',
      ),
    );
    expect(workflow, isNot(contains('  pull_request:')));
  });

  test('release validates only its uploaded and downloaded native artifact', () {
    final lint = _jobSection(workflow, 'lint', 'fetch-binaries');
    final producer = _jobSection(workflow, 'fetch-binaries', 'test-package');
    final consumer = _jobSection(workflow, 'test-package', 'release');

    expect(lint, isNot(contains('lfs: true')));
    expect(lint, isNot(contains('submodules:')));
    expect(producer, isNot(contains('lfs: true')));
    expect(producer, isNot(contains('submodules:')));
    expect(producer, isNot(contains('submodules: recursive')));
    expect(consumer, isNot(contains('lfs: true')));
    expect(consumer, isNot(contains('submodules:')));
    expect(
      RegExp(r'^\s+lfs: true$', multiLine: true).allMatches(workflow),
      isEmpty,
    );

    expect(
      producer,
      contains(
        'dart run scripts/fetch_opentui_binaries.dart --verify-only --verify-urls',
      ),
    );
    for (final path in <String>[
      'native/macos/x64/libopentui.dylib',
      'native/macos/arm64/libopentui.dylib',
      'native/linux/x64/libopentui.so',
      'native/linux/arm64/libopentui.so',
      'native/windows/x64/libopentui.dll',
      'native/windows/arm64/libopentui.dll',
    ]) {
      expect(producer, contains(path));
    }
    expect(producer, contains('native_manifest.json'));
    expect(producer, contains('actions/upload-artifact@v4'));
    expect(producer, contains('name: opentui-binaries'));
    expect(producer, contains('native/'));
    expect(producer, contains('retention-days: 30'));
    expect(
      producer,
      contains(
        r'tar -czf opentui-binaries-${{ github.ref_name }}.tar.gz native/ native_manifest.json',
      ),
    );
    expect(producer, contains('name: opentui-binaries-release'));

    expect(
      consumer,
      contains(
        '- name: Remove checkout native payload\n'
        '        shell: bash\n'
        '        run: rm -rf native native_manifest.json\n'
        '\n'
        '      - name: Download bundled binaries\n'
        '        uses: actions/download-artifact@v4',
      ),
    );
    expect(consumer, contains('name: opentui-binaries'));
    expect(consumer, contains('path: .'));
    expect(consumer, contains('ubuntu-latest'));
    expect(consumer, contains('macos-latest'));
    expect(consumer, contains('windows-latest'));
    expect(consumer, contains('native/linux/x64/libopentui.so'));
    expect(consumer, contains('native/linux/arm64/libopentui.so'));
    expect(consumer, contains('native/macos/x64/libopentui.dylib'));
    expect(consumer, contains('native/macos/arm64/libopentui.dylib'));
    expect(consumer, contains('native/windows/x64/libopentui.dll'));
    expect(consumer, contains('native/windows/arm64/libopentui.dll'));
    expect(
      consumer,
      contains(r'''
          for file in "${expected_files[@]}"; do
            if [[ -f "$file" ]]; then
              echo "✅ Found: $file"
            else
              echo "❌ Missing: $file"
              exit 1
            fi
          done'''),
    );
    expect(consumer, contains('dart run bin/health_check.dart'));
    expect(consumer, isNot(contains('run: dart bin/health_check.dart')));
    expect(
      consumer,
      contains(r'''
          dart build cli -t bin/health_check.dart --output build/health-check
          case "${{ runner.os }}" in
            Windows) bundle="build/health-check/bundle/bin/health_check.exe" ;;
            *) bundle="build/health-check/bundle/bin/health_check" ;;
          esac
          "$bundle"'''),
    );
    expect(workflow, contains('softprops/action-gh-release@v1'));
    expect(workflow, contains('files: opentui-binaries-*.tar.gz'));

    expect(workflow, isNot(contains('dart test')));
    expect(workflow, isNot(contains('GO_SNAPSHOT_CMD')));
    expect(workflow, isNot(contains('actions/setup-go')));
    expect(workflow, isNot(contains('pkg-config')));
    expect(workflow, isNot(contains('submodules: recursive')));
    expect(workflow, isNot(contains('--strip-debug')));
    expect(workflow, isNot(contains('native/checksums.txt')));
    expect(workflow, isNot(contains('sha256sum -c checksums.txt')));
  });

  test(
    'release uploads the verified manifest before downloading the artifact',
    () {
      final verify = workflow.indexOf(
        'dart run scripts/fetch_opentui_binaries.dart --verify-only --verify-urls',
      );
      final manifestUpload = workflow.indexOf(
        '            native_manifest.json',
      );
      final upload = workflow.indexOf('actions/upload-artifact@v4');
      final remove = workflow.indexOf(
        'run: rm -rf native native_manifest.json',
      );
      final download = workflow.indexOf('actions/download-artifact@v4');
      final health = workflow.indexOf('dart run bin/health_check.dart');
      final bundle = workflow.indexOf(
        'dart build cli -t bin/health_check.dart',
      );

      expect(verify, greaterThan(-1));
      expect(upload, greaterThan(verify));
      expect(manifestUpload, greaterThan(upload));
      expect(remove, greaterThan(upload));
      expect(download, greaterThan(remove));
      expect(health, greaterThan(download));
      expect(bundle, greaterThan(health));
    },
  );
}

String _jobSection(String workflow, String name, String nextName) {
  final start = workflow.indexOf('  $name:');
  final end = workflow.indexOf('  $nextName:', start + 1);
  expect(start, greaterThan(-1), reason: 'missing $name job');
  expect(end, greaterThan(start), reason: 'missing $nextName job');
  return workflow.substring(start, end);
}
