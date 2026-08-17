import 'dart:io';

import 'package:test/test.dart';

void main() {
  final workflow = File(
    '.github/workflows/release.yml',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  test('release is manual for one explicit existing tag', () {
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains('inputs:'));
    expect(workflow, contains('tag:'));
    expect(
      RegExp(r'ref: refs/tags/\$\{\{ inputs\.tag \}\}').allMatches(workflow),
      hasLength(2),
    );
    expect(
      workflow,
      contains(r'git show-ref --verify --quiet "refs/tags/$RELEASE_TAG"'),
    );
    expect(workflow, isNot(contains('push:')));
    expect(workflow, isNot(contains('tags:')));
    expect(workflow, isNot(contains('branches:')));
    expect(workflow, contains('cancel-in-progress: false'));
    expect(workflow, contains('for example, v1.2.3'));
    expect(workflow, isNot(contains('pull_request:')));
  });

  test('release uses immutable actions and explicit permissions', () {
    for (final line
        in workflow
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.startsWith('uses:'))) {
      expect(
        line,
        matches(RegExp(r'^uses: [^@ ]+@[0-9a-f]{40}(?: # v[^ ]+)?$')),
        reason: 'release action must be immutable: $line',
      );
    }

    expect(workflow, contains('permissions:\n  contents: read'));
    final release = workflow.substring(workflow.indexOf('  release:'));
    expect(release, contains('contents: write'));
    expect(release, isNot(contains('secrets.GITHUB_TOKEN')));
  });

  test('verified committed assets are packaged then tested cross-platform', () {
    final verify = workflow.indexOf(
      'dart run scripts/fetch_opentui_binaries.dart --verify-only',
    );
    final ordinaryTests = workflow.indexOf('dart test --concurrency=1');
    final docs = workflow.indexOf(
      'dart doc --validate-links --output .context/dartdoc',
    );
    final dryRun = workflow.indexOf('dart pub publish --dry-run');
    final upload = workflow.indexOf('actions/upload-artifact@');
    final remove = workflow.indexOf('run: rm -rf native native_manifest.json');
    final download = workflow.indexOf('actions/download-artifact@');
    final health = workflow.indexOf('run: dart run noir:health_check');

    expect(verify, greaterThan(-1));
    expect(workflow, isNot(contains('--verify-urls')));
    expect(ordinaryTests, greaterThan(verify));
    expect(docs, greaterThan(ordinaryTests));
    expect(dryRun, greaterThan(docs));
    expect(upload, greaterThan(dryRun));
    expect(remove, greaterThan(upload));
    expect(download, greaterThan(remove));
    expect(health, greaterThan(download));
    expect(workflow, contains('native_manifest.json'));
    expect(workflow, contains('ubuntu-latest'));
    expect(workflow, contains('macos-latest'));
    expect(workflow, contains('windows-latest'));
    expect(workflow, contains('dart build cli -t bin/health_check.dart'));
    expect(workflow, contains('  verify:'));
    expect(workflow, contains('timeout-minutes: 15'));
    expect(workflow, contains('timeout-minutes: 12'));
    expect(workflow, contains('timeout-minutes: 5'));
    expect('actions/cache@'.allMatches(workflow), hasLength(2));
    expect(
      r'path: ${{ runner.temp }}/pub-cache'.allMatches(workflow),
      hasLength(2),
    );
    expect(
      r'run: echo "PUB_CACHE=$RUNNER_TEMP/pub-cache" >> "$GITHUB_ENV"'
          .allMatches(workflow),
      hasLength(2),
    );
    expect(
      workflow,
      isNot(contains(r'PUB_CACHE: ${{ runner.temp }}/pub-cache')),
      reason: 'runner context is unavailable in job-level env',
    );
  });

  test('tag releases require an exact semantic-version/package match', () {
    expect(workflow, contains('name: Verify release tag'));
    expect(workflow, contains(r'RELEASE_TAG: ${{ inputs.tag }}'));
    expect(workflow, contains("semver='[0-9]+[.][0-9]+[.][0-9]+"));
    expect(
      workflow,
      contains(r'if [[ "$RELEASE_TAG" != "v$package_version" ]]'),
    );
  });

  test('release metadata is strict and states the macOS deployment floor', () {
    expect(workflow, contains('fail_on_unmatched_files: true'));
    expect(workflow, contains(r"prerelease: ${{ contains(inputs.tag, '-') }}"));
    expect(workflow, contains(r'tag_name: ${{ inputs.tag }}'));
    expect(workflow, contains('generate_release_notes: true'));
    expect(workflow, contains('macOS 13.0 or later (x64, arm64)'));
    expect(workflow, isNot(contains('dart run example/')));
  });
}
