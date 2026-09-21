/// The release gate, shared by a contributor's terminal and the workflows.
///
/// Run from `packages/noir/`. Every rule lives in `tool/release/release.dart`
/// and is covered by `test/tools/release_cli_test.dart`, so a release workflow
/// is a thin caller rather than logic that first runs against a real tag.
library;

import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:pub_semver/pub_semver.dart';

import 'release/release.dart';

const _usage = '''
Usage: dart run tool/release.dart <command> [options]

  check                  Every package's cross-package constraints admit the
                         sibling it ships beside, and every changelog leads
                         with its own manifest version.

  resolve-tag <tag>      Split a <package>-v<version> release tag and check it
                         against that package's manifest.

  preflight <package>    Ask pub.dev whether this version still needs
                         publishing, and whether every workspace dependency is
                         already served at a version the constraint admits.
                         Waits up to --timeout for a dependency that a just
                         finished publish has not surfaced yet.

  published <package>    Succeed only when pub.dev already serves the version
                         this package's manifest names. The gate a GitHub
                         release passes before it announces anything. Waits up
                         to --timeout for an upload that has not surfaced yet.

  record                 Rewrite publication.json from what pub.dev serves.
                         Run only after a publication is confirmed; the
                         website's availability labels derive from it.

Options:
''';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption(
      'root',
      help: 'Workspace root. Defaults to two directories above this package.',
      defaultsTo: '../..',
    )
    ..addOption(
      'timeout',
      help: 'Seconds preflight waits for a dependency to appear on pub.dev.',
      defaultsTo: '0',
    );

  final ArgResults options;
  try {
    options = parser.parse(args);
  } on FormatException catch (error) {
    _fail(error.message, parser);
    return;
  }
  if (options['help'] as bool || options.rest.isEmpty) {
    io.stdout.write(_usage);
    io.stdout.writeln(parser.usage);
    return;
  }

  final root = io.Directory(options['root'] as String);
  final command = options.rest.first;
  final rest = options.rest.skip(1).toList();

  switch (command) {
    case 'check':
      _check(root);
    case 'resolve-tag':
      if (rest.length != 1) {
        _fail('resolve-tag takes exactly one tag.', parser);
        return;
      }
      _resolveTag(root, rest.single);
    case 'published':
      if (rest.length != 1) {
        _fail('published takes exactly one package name.', parser);
        return;
      }
      await _published(
        root,
        rest.single,
        timeout: Duration(seconds: int.parse(options['timeout'] as String)),
      );
    case 'record':
      await _record(root);
    case 'preflight':
      if (rest.length != 1) {
        _fail('preflight takes exactly one package name.', parser);
        return;
      }
      await _preflight(
        root,
        rest.single,
        timeout: Duration(seconds: int.parse(options['timeout'] as String)),
      );
    default:
      _fail('Unknown command "$command".', parser);
  }
}

void _check(io.Directory root) {
  final workspace = loadWorkspace(root);
  final problems = releaseReadinessProblems(workspace);
  if (problems.isEmpty) {
    io.stdout.writeln(
      'Release ready: ${workspace.map((p) => '${p.name} ${p.version}').join(', ')}.',
    );
    return;
  }
  for (final problem in problems) {
    io.stderr.writeln('error: $problem');
  }
  io.exitCode = 1;
}

void _resolveTag(io.Directory root, String tag) {
  final ReleaseTag release;
  try {
    release = parseReleaseTag(tag);
  } on FormatException catch (error) {
    io.stderr.writeln('error: ${error.message}');
    io.exitCode = 1;
    return;
  }
  final workspace = loadWorkspace(root);
  final package = workspace
      .where((candidate) => candidate.name == release.package)
      .firstOrNull;
  if (package == null) {
    io.stderr.writeln(
      'error: tag "$tag" names ${release.package}, which is not a workspace '
      'member. Members: ${workspace.map((p) => p.name).join(', ')}.',
    );
    io.exitCode = 1;
    return;
  }
  if (package.version != release.version) {
    io.stderr.writeln(
      'error: tag "$tag" carries ${release.version}, but '
      '${package.directory}/pubspec.yaml declares ${package.version}. The tag '
      'and the manifest must agree, because pub.dev matches the pushed tag '
      'against the version it is asked to publish.',
    );
    io.exitCode = 1;
    return;
  }
  io.stdout.writeln(
    '${package.name} ${package.version} (${package.directory})',
  );
  _emitOutputs(<String, String>{
    'package': package.name,
    'version': package.version.toString(),
    'directory': package.directory,
    // The one place that decides what a prerelease is. A GitHub release marks
    // itself prerelease from this, rather than from a second rule that reads
    // the tag text and can disagree.
    'prerelease': package.version.isPreRelease.toString(),
  });
}

/// How often to re-ask pub.dev while waiting out registry lag.
const _pollInterval = Duration(seconds: 15);

/// Re-runs [ask] until [settled] accepts its answer or [timeout] runs out.
///
/// pub.dev serves a version a short while after the upload that created it
/// returns, so both questions this tool asks the registry right after a
/// publish — can this dependent go now, and is this version really out — can
/// be answered wrongly for reasons that fix themselves.
Future<T> _untilSettled<T>(
  Future<T> Function() ask, {
  required bool Function(T) settled,
  required Duration timeout,
  required String waitingFor,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final answer = await ask();
    if (settled(answer)) return answer;
    final left = deadline.difference(DateTime.now());
    if (left <= Duration.zero) return answer;
    io.stdout.writeln('waiting for $waitingFor to appear on pub.dev …');
    await Future<void>.delayed(left < _pollInterval ? left : _pollInterval);
  }
}

Future<void> _preflight(
  io.Directory root,
  String name, {
  required Duration timeout,
}) async {
  final workspace = loadWorkspace(root);
  if (!workspace.any((candidate) => candidate.name == name)) {
    io.stderr.writeln('error: $name is not a workspace member.');
    io.exitCode = 1;
    return;
  }

  final cache = <String, Set<Version>>{};
  Future<Set<Version>> lookup(String package) async =>
      cache[package] ??= await fetchPublishedVersions(package);

  final decision = await _untilSettled(
    () async {
      cache.clear();
      return decidePublish(name, workspace, lookup: lookup);
    },
    settled: (candidate) => !candidate.isBlocked,
    timeout: timeout,
    waitingFor: 'a workspace dependency',
  );

  for (final blocker in decision.blockers) {
    io.stderr.writeln('error: $blocker');
  }
  io.stdout.writeln(decision.reason);
  _emitOutputs(<String, String>{
    'publish': decision.shouldPublish.toString(),
    'reason': decision.reason,
  });
  if (decision.isBlocked) io.exitCode = 1;
}

Future<void> _published(
  io.Directory root,
  String name, {
  required Duration timeout,
}) async {
  final workspace = loadWorkspace(root);
  if (!workspace.any((candidate) => candidate.name == name)) {
    io.stderr.writeln('error: $name is not a workspace member.');
    io.exitCode = 1;
    return;
  }
  final package = workspace.firstWhere((candidate) => candidate.name == name);
  final published = await _untilSettled(
    () => isPublished(name, workspace, lookup: fetchPublishedVersions),
    settled: (candidate) => candidate,
    timeout: timeout,
    waitingFor: '$name ${package.version}',
  );
  if (!published) {
    io.stderr.writeln(
      'error: pub.dev does not serve $name ${package.version}. A release '
      'must not announce a version nobody can install.',
    );
    io.exitCode = 1;
    return;
  }
  io.stdout.writeln('pub.dev serves $name ${package.version}.');
}

Future<void> _record(io.Directory root) async {
  final workspace = loadWorkspace(root);
  final publication = io.File('${root.path}/publication.json');
  final changed = await recordPublication(
    workspace,
    publication,
    lookup: fetchPublishedVersions,
  );
  if (changed.isEmpty) {
    io.stdout.writeln('publication.json already matches pub.dev.');
    _emitOutputs(const <String, String>{'changed': ''});
    return;
  }
  io.stdout.writeln('Recorded from pub.dev: ${changed.join(', ')}.');
  io.stdout.writeln(
    'Run `npm run sync` in website/ so the availability labels follow.',
  );
  _emitOutputs(<String, String>{'changed': changed.join(',')});
}

/// Writes GitHub Actions step outputs when running inside a workflow.
void _emitOutputs(Map<String, String> outputs) {
  final path = io.Platform.environment['GITHUB_OUTPUT'];
  if (path == null || path.isEmpty) return;
  final sink = io.File(path).openWrite(mode: io.FileMode.append);
  for (final entry in outputs.entries) {
    sink.writeln('${entry.key}=${entry.value}');
  }
  sink.close();
}

void _fail(String message, ArgParser parser) {
  io.stderr.writeln('error: $message');
  io.stderr.write(_usage);
  io.stderr.writeln(parser.usage);
  io.exitCode = 64;
}
