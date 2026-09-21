import 'dart:io';

import 'package:test/test.dart';

/// The directory each script runs in, keyed by script name.
const _scriptDirectories = <String, String>{
  'format:noir': 'packages/noir',
  'format:driver': 'packages/noir_driver',
  'format:signals': 'packages/noir_signals',
  'analyze': '.',
  'analyze:driver': 'packages/noir_driver',
  'analyze:signals': 'packages/noir_signals',
  'test:noir': 'packages/noir',
  'test:driver': 'packages/noir_driver',
  'test:signals': 'packages/noir_signals',
  'test:architecture': 'packages/noir',
  'native:verify': 'packages/noir',
  'docs:frames': 'packages/noir',
  'docs:api': 'packages/noir',
  'stage:companion': 'packages/noir',
  'stage:driver': 'packages/noir',
  'archive:noir': 'packages/noir',
  'archive:driver': 'packages/noir_driver',
  'archive:signals': 'packages/noir_signals',
};

/// The commands the contributor guide authorizes, keyed by the Melos script
/// that wraps each one. A script is an alias for a documented command, never a
/// second definition of it, so CI and a contributor's terminal cannot drift.
const _scriptCommands = <String, String>{
  'format:noir':
      'dart format --output=none --set-exit-if-changed '
      'lib/ test/ example/ bin/ hook/ tool/',
  'format:driver':
      'dart format --output=none --set-exit-if-changed lib/ test/ bin/',
  'format:signals':
      'dart format --output=none --set-exit-if-changed lib/ test/ example/',
  'analyze': 'dart analyze --fatal-infos',
  'analyze:driver': 'dart analyze --fatal-infos',
  'analyze:signals': 'dart analyze --fatal-infos',
  'test:noir': 'dart test --concurrency=1',
  'test:driver': 'dart test --concurrency=1',
  'test:signals': 'dart test --concurrency=1',
  'test:architecture': 'dart test test/architecture/ --concurrency=1',
  'native:verify': 'dart run tool/fetch_opentui_binaries.dart --verify-only',
  'docs:frames': 'dart run tool/capture_doc_frames.dart --check',
  'docs:api': 'dart doc --validate-links --output .context/dartdoc',
  'stage:companion': 'dart run tool/stage_companion_package.dart --verify',
  'stage:driver':
      'dart run tool/stage_companion_package.dart --verify ../noir_driver',
  'archive:noir': 'dart pub publish --dry-run',
  'archive:driver': 'dart pub publish --dry-run',
  'archive:signals': 'dart pub publish --dry-run',
};

/// Commands the contributor guide lists verbatim. `docs:api` and the archive
/// scripts are release-workflow stages rather than entries in that list.
const _guidedScripts = <String>[
  'format:noir',
  'format:driver',
  'format:signals',
  'analyze',
  'test:noir',
  'test:architecture',
  'native:verify',
  'docs:frames',
  'stage:companion',
  'stage:driver',
];

void main() {
  final workspacePubspec = _read('../../pubspec.yaml');
  final contributorGuide = _read('../../CONTRIBUTING.md');
  final agentGuide = _read('../../AGENTS.md');
  final scripts = _scripts(workspacePubspec);
  final workflows = <String, String>{
    for (final name in const <String>['ci', 'release', 'publish'])
      name: _read('../../.github/workflows/$name.yml'),
  };

  test('Melos is a pinned workspace dev dependency, not a floating one', () {
    // Melos locates the workspace through its own dev dependency, so the
    // version a contributor runs is the version this file pins. `ffigen`, a
    // Noir dev dependency, holds `cli_util` below the range newer Melos
    // releases need, and a Pub workspace resolves once for every member.
    final pin = RegExp(
      r'^dev_dependencies:\n  melos: (\S+)$',
      multiLine: true,
    ).firstMatch(workspacePubspec);
    expect(pin, isNotNull, reason: 'the workspace must pin one Melos version');

    final version = pin!.group(1)!;
    expect(
      version,
      matches(RegExp(r'^\d+\.\d+\.\d+$')),
      reason: 'an exact version, so a range cannot pull in a newer cli_util',
    );
    expect(contributorGuide, contains('melos: $version'));
    expect(contributorGuide, contains('cli_util'));
    expect(contributorGuide, contains('ffigen'));
  });

  test('bootstrap never writes into a package directory', () {
    // IntelliJ generation is on by default and would drop a `melos_*.iml`
    // beside each pubspec, where `.pubignore` does not exclude it.
    expect(workspacePubspec, contains('ide:\n    intellij: false'));
    expect(File('melos_noir.iml').existsSync(), isFalse);
    expect(File('../../melos_noir_workspace.iml').existsSync(), isFalse);
    expect(_read('../../.gitignore'), contains('pubspec_overrides.yaml'));
  });

  test('versioning writes no changelog, no commit, no tag, and no fetch', () {
    // A `v*` tag publishes Noir to pub.dev, so the documented command must
    // carry every guarantee this Melos release cannot express as a setting.
    expect(workspacePubspec, contains('workspaceChangelog: false'));
    expect(workspacePubspec, contains('fetchTags: false'));

    // Indented command blocks only: the surrounding prose names the forms
    // this repository must not use.
    final documented = RegExp(
      r'^    dart run melos:melos version [^\n]*$',
      multiLine: true,
    ).allMatches(contributorGuide).map((match) => match.group(0)!).toList();
    expect(documented, isNotEmpty, reason: 'the guide must show the command');
    for (final command in documented) {
      expect(command, contains('--no-changelog'), reason: command);
      // Implies --no-git-tag-version, which is the guarantee that matters.
      expect(command, contains('--no-git-commit-version'), reason: command);
      expect(command, contains('--dependent-constraints'), reason: command);
      // A dependent's own version is a release decision, not a side effect.
      expect(command, contains('--no-dependent-versions'), reason: command);
      // Without an empty commit range Melos also versions the companions
      // from their Conventional Commit history, which is their whole history
      // because they are published by hand and carry no release tag.
      expect(command, contains('--diff=HEAD...HEAD'), reason: command);
      // The `melos version <package> <version>` positional form scopes the
      // run, which turns the other members into ignored packages with
      // pending changes; Melos then skips every package that depends on one
      // and exits 0 having changed nothing.
      expect(command, contains('-V '), reason: command);
    }
  });

  test('every script wraps a command the guides document', () {
    expect(scripts.keys, containsAll(_scriptCommands.keys));
    for (final entry in _scriptCommands.entries) {
      final directory = _scriptDirectories[entry.key]!;
      // A script is the documented command plus the directory the guides say
      // to run it from, and nothing else.
      expect(
        scripts[entry.key],
        directory == '.' ? entry.value : 'cd $directory && ${entry.value}',
        reason: entry.key,
      );
    }
    for (final name in _guidedScripts) {
      expect(
        agentGuide,
        contains(_scriptCommands[name]),
        reason: '$name must wrap a command the agent guide authorizes',
      );
    }
  });

  test('the ladder script runs every check, in the documented order', () {
    const ladder = <String>[
      'format:noir',
      'format:driver',
      'format:signals',
      'analyze',
      'analyze:driver',
      'analyze:signals',
      'test:architecture',
      'test:noir',
      'test:driver',
      'test:signals',
      'native:verify',
    ];

    final verify = scripts['verify'];
    expect(verify, isNotNull, reason: 'the workspace declares no ladder');
    expect(
      RegExp(
        r'dart run melos:melos run (\S+)',
      ).allMatches(verify!).map((match) => match.group(1)).toList(),
      ladder,
    );
    // A step list would shell out to a bare `melos`, which only exists when
    // someone has also installed it globally. CI has not.
    expect(verify, isNot(contains('steps:')));
    for (final name in ladder) {
      expect(scripts.keys, contains(name));
    }
  });

  test('shared constraints in one place match every package that uses one', () {
    final shared = _bootstrapConstraints(workspacePubspec);
    expect(shared['dependencies'], isNotEmpty);
    expect(shared['dev_dependencies'], isNotEmpty);
    expect(shared['environment'], contains('sdk'));

    for (final package in const <String>[
      'pubspec.yaml',
      '../noir_driver/pubspec.yaml',
      '../noir_signals/pubspec.yaml',
    ]) {
      final source = _read(package);
      for (final section in const <String>[
        'dependencies',
        'dev_dependencies',
      ]) {
        final declared = _section(source, section);
        for (final entry in shared[section]!.entries) {
          final constraint = declared[entry.key];
          if (constraint == null) continue;
          expect(
            constraint,
            entry.value,
            reason:
                '$package declares ${entry.key} $constraint, but the '
                'workspace shares ${entry.value}',
          );
        }
      }
      expect(
        _section(source, 'environment')['sdk'],
        shared['environment']!['sdk'],
        reason: '$package must use the shared SDK range',
      );
    }
  });

  test('workflows only name scripts this workspace declares', () {
    for (final entry in workflows.entries) {
      final invoked = RegExp(
        r'dart run melos:melos run (\S+)',
      ).allMatches(entry.value).map((match) => match.group(1)!).toSet();
      for (final name in invoked) {
        expect(
          scripts.keys,
          contains(name),
          reason: '${entry.key}.yml runs an undeclared script: $name',
        );
      }
    }
    expect(workflows['ci'], contains('dart run melos:melos run '));
  });

  test('publication itself never goes through Melos', () {
    // `melos publish` would decide for itself which packages ship. The two
    // companions publish by hand, on their own cadence, from their own
    // directories.
    for (final entry in workflows.entries) {
      expect(
        entry.value,
        isNot(contains('melos publish')),
        reason: '${entry.key}.yml must not publish through Melos',
      );
      expect(entry.value, isNot(contains('melos version')));
    }
    expect(workflows['publish'], contains('run: dart pub publish --force'));
  });
}

/// Every script name mapped to the command it runs.
Map<String, String> _scripts(String pubspec) {
  final start = pubspec.indexOf('\n  scripts:\n');
  if (start < 0) {
    throw StateError('the workspace pubspec declares no Melos scripts');
  }
  final block = pubspec.substring(start);
  final scripts = <String, String>{};
  final lines = block.split('\n');
  String? current;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final name = RegExp(r'^    ([a-z][\w:.-]*):\s*$').firstMatch(line);
    if (name != null) {
      current = name.group(1);
      continue;
    }
    final command = RegExp(r'^      (?:exec|run): (.+)$').firstMatch(line);
    if (command == null || current == null) continue;

    final value = command.group(1)!.trim();
    if (value != '>-' && value != '>') {
      scripts[current] = value;
      current = null;
      continue;
    }
    // A folded scalar: the command continues on the lines below it, joined
    // with single spaces.
    final folded = <String>[];
    while (index + 1 < lines.length &&
        lines[index + 1].startsWith('        ')) {
      folded.add(lines[++index].trim());
    }
    scripts[current] = folded.join(' ');
    current = null;
  }
  return scripts;
}

/// The bootstrap section's shared constraints, by pubspec section name.
Map<String, Map<String, String>> _bootstrapConstraints(String pubspec) {
  final start = pubspec.indexOf('    bootstrap:\n');
  if (start < 0) {
    throw StateError('the workspace pubspec has no bootstrap configuration');
  }
  final end = pubspec.indexOf('\n    version:\n', start);
  final block = pubspec.substring(start, end < 0 ? pubspec.length : end);
  final sections = <String, Map<String, String>>{};
  String? current;
  for (final line in block.split('\n')) {
    final section = RegExp(
      r'^      (environment|dependencies|dev_dependencies):\s*$',
    ).firstMatch(line);
    if (section != null) {
      current = section.group(1);
      sections[current!] = <String, String>{};
      continue;
    }
    final entry = RegExp(r'^        ([\w-]+): (.+)$').firstMatch(line);
    if (entry != null && current != null) {
      sections[current]![entry.group(1)!] = entry.group(2)!.trim();
    }
  }
  return sections;
}

/// One pubspec section read as a flat constraint map.
Map<String, String> _section(String pubspec, String name) {
  final start = RegExp('^$name:\\s*\$', multiLine: true).firstMatch(pubspec);
  if (start == null) return const <String, String>{};
  final rest = pubspec.substring(start.end);
  final end = RegExp(r'^\S', multiLine: true).firstMatch(rest);
  final block = rest.substring(0, end?.start ?? rest.length);
  return <String, String>{
    for (final match in RegExp(
      r'^  ([\w-]+): (.+)$',
      multiLine: true,
    ).allMatches(block))
      match.group(1)!: match.group(2)!.trim(),
  };
}

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');
