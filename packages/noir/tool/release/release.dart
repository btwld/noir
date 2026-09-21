/// Release logic shared by a contributor's terminal and the release workflows.
///
/// The workflows call this through `tool/release.dart` rather than reimplement
/// any of it in YAML, so the rules below are exercised by
/// `test/tools/release_cli_test.dart` on every ordinary CI run instead of
/// first running against a real tag.
library;

import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// One publishable workspace member.
class ReleasePackage {
  ReleasePackage({
    required this.name,
    required this.directory,
    required this.version,
    required this.dependencies,
    required this.devDependencies,
    required this.changelog,
  });

  /// The package name, which is also the release tag's prefix.
  final String name;

  /// Path to the package, relative to the workspace root.
  final String directory;

  /// The version in the package's own manifest.
  final Version version;

  /// Hosted runtime constraints, by package name.
  final Map<String, VersionConstraint> dependencies;

  /// Hosted development constraints, by package name.
  final Map<String, VersionConstraint> devDependencies;

  /// The package's `CHANGELOG.md`, or null when it has none.
  final String? changelog;

  /// The Melos release tag that publishes [version].
  String get releaseTag => releaseTagFor(name, version);

  /// The leading `## <version>` heading of [changelog], or null.
  Version? get leadingChangelogVersion {
    final source = changelog;
    if (source == null) return null;
    final heading = RegExp(
      r'^## +(\S+) *$',
      multiLine: true,
    ).firstMatch(source);
    if (heading == null) return null;
    return Version.parse(heading.group(1)!);
  }
}

/// The tag that releases [version] of [name].
///
/// This is Melos's own format — `gitTagForPackageVersion` in `common/git.dart`
/// builds `<name>-v<version>` for every package, with no special case for a
/// primary one. Matching it is what lets `melos version` find a package's
/// previous release instead of reading its whole history as unreleased.
String releaseTagFor(String name, Version version) => '$name-v$version';

/// A release tag split back into the package and version it names.
class ReleaseTag {
  ReleaseTag(this.package, this.version);

  final String package;
  final Version version;

  @override
  String toString() => releaseTagFor(package, version);
}

/// Parses `<package>-v<version>`, or throws [FormatException].
///
/// A package name cannot contain `-`, so the first `-v` that is followed by a
/// parsable version ends the name unambiguously.
ReleaseTag parseReleaseTag(String tag) {
  final match = RegExp(r'^([a-z][a-z0-9_]*)-v(.+)$').firstMatch(tag.trim());
  if (match == null) {
    throw FormatException(
      'Not a release tag: "$tag". Release tags are <package>-v<version>, '
      'for example noir-v0.0.3.',
    );
  }
  final Version version;
  try {
    version = Version.parse(match.group(2)!);
  } on FormatException catch (error) {
    throw FormatException(
      'Release tag "$tag" carries no usable version: '
      '${error.message}',
    );
  }
  return ReleaseTag(match.group(1)!, version);
}

/// Reads every member named by the workspace manifest at [root].
List<ReleasePackage> loadWorkspace(Directory root) {
  final rootManifest =
      loadYaml(File('${root.path}/pubspec.yaml').readAsStringSync()) as YamlMap;
  final members = (rootManifest['workspace'] as YamlList?) ?? YamlList();
  return <ReleasePackage>[
    for (final member in members.cast<String>()) _loadPackage(root, member),
  ];
}

ReleasePackage _loadPackage(Directory root, String directory) {
  final manifest =
      loadYaml(File('${root.path}/$directory/pubspec.yaml').readAsStringSync())
          as YamlMap;
  final changelog = File('${root.path}/$directory/CHANGELOG.md');
  return ReleasePackage(
    name: manifest['name'] as String,
    directory: directory,
    version: Version.parse(manifest['version'] as String),
    dependencies: _constraints(manifest['dependencies']),
    devDependencies: _constraints(manifest['dev_dependencies']),
    changelog: changelog.existsSync() ? changelog.readAsStringSync() : null,
  );
}

/// Hosted constraints only. A `path:` or `sdk:` entry is a map, and carries no
/// version this tooling can reason about.
Map<String, VersionConstraint> _constraints(Object? section) {
  if (section is! YamlMap) return const <String, VersionConstraint>{};
  return <String, VersionConstraint>{
    for (final entry in section.entries)
      if (entry.value is String)
        entry.key as String: VersionConstraint.parse(entry.value as String),
  };
}

/// Every way the workspace is not ready to be released, in report order.
///
/// Both rules exist because nothing else reports them. Inside a workspace pub
/// binds a sibling to the local checkout and never rules on whether the
/// declared constraint would have admitted it, and
/// `stage_companion_package.dart --verify` replaces the `noir` dependency with
/// a path override before its dry-run. Once published, though, the declared
/// constraint is all a consumer has.
///
/// Note that Dart's caret is not npm's. `pub_semver` raises the *minor* for a
/// `0.y.z` version, so `^0.0.2` is `>=0.0.2 <0.1.0` and does admit 0.0.3. The
/// constraint that actually strands a companion is one left behind across a
/// minor bump — `^0.0.3` once Noir reaches 0.1.0 — which is exactly the move
/// `melos version` exists to cascade.
List<String> releaseReadinessProblems(List<ReleasePackage> packages) {
  final byName = {for (final package in packages) package.name: package};
  final problems = <String>[];
  for (final package in packages) {
    for (final section in <(String, Map<String, VersionConstraint>)>[
      ('dependencies', package.dependencies),
      ('dev_dependencies', package.devDependencies),
    ]) {
      for (final entry in section.$2.entries) {
        final sibling = byName[entry.key];
        if (sibling == null) continue;
        if (!entry.value.allows(sibling.version)) {
          problems.add(
            '${package.directory}/pubspec.yaml declares '
            '${section.$1}.${entry.key}: ${entry.value}, which excludes the '
            '${sibling.name} ${sibling.version} it is built against. Once '
            'published, that constraint is all a consumer has to resolve '
            'against.',
          );
        }
      }
    }
    if (package.changelog == null) {
      problems.add('${package.directory} has no CHANGELOG.md.');
      continue;
    }
    final leading = package.leadingChangelogVersion;
    if (leading != package.version) {
      problems.add(
        '${package.directory}/CHANGELOG.md leads with '
        '${leading ?? 'no version heading'}, not the manifest version '
        '${package.version}. Every published version is a written contract.',
      );
    }
  }
  return problems;
}

/// Looks up the versions of [package] that pub.dev already serves.
typedef RegistryLookup = Future<Set<Version>> Function(String package);

/// What the release workflow should do with one package.
class PublishDecision {
  PublishDecision({
    required this.package,
    required this.shouldPublish,
    required this.reason,
    this.blockers = const <String>[],
  });

  final String package;

  /// Whether the workflow should run `dart pub publish`.
  final bool shouldPublish;

  /// Why, in one line, for the workflow log.
  final String reason;

  /// Unsatisfied preconditions. Non-empty means the run must fail.
  final List<String> blockers;

  bool get isBlocked => blockers.isNotEmpty;
}

/// Decides whether [name] may be published now.
///
/// Three outcomes, and the caller must distinguish them:
///
/// - **blocked**: a workspace dependency this package needs is not on pub.dev
///   at a version its constraint allows. Publishing anyway would ship an
///   archive no consumer can resolve. This is the ordering rule, enforced
///   rather than documented.
/// - **skip**: the version is already on pub.dev. A re-run of the same tag is
///   a no-op, so a retry after a partial failure is safe.
/// - **publish**: neither of the above.
///
/// Only runtime [ReleasePackage.dependencies] gate the order. Noir carries
/// `noir_driver` as a checkout-only dev dependency, so treating dev
/// dependencies as ordering edges would make Noir wait for a package that
/// waits for Noir. `melos publish` does exactly that: its
/// `sortPackagesForPublishing` feeds both sections into one graph, sees the
/// cycle, and falls back to sorting by name length — which puts `noir_driver`
/// ahead of `noir`. That is why publication here does not go through Melos.
Future<PublishDecision> decidePublish(
  String name,
  List<ReleasePackage> workspace, {
  required RegistryLookup lookup,
}) async {
  final package = workspace.firstWhere(
    (candidate) => candidate.name == name,
    orElse: () => throw ArgumentError('$name is not a workspace member'),
  );
  final byName = {for (final member in workspace) member.name: member};

  final blockers = <String>[];
  for (final entry in package.dependencies.entries) {
    if (!byName.containsKey(entry.key)) continue;
    final published = await lookup(entry.key);
    if (!published.any(entry.value.allows)) {
      blockers.add(
        '${package.name} needs ${entry.key} ${entry.value}, and pub.dev '
        'serves ${published.isEmpty ? 'no version' : _describe(published)}. '
        'Publish ${entry.key} first.',
      );
    }
  }
  if (blockers.isNotEmpty) {
    return PublishDecision(
      package: name,
      shouldPublish: false,
      reason: 'blocked by an unpublished workspace dependency',
      blockers: blockers,
    );
  }

  final alreadyPublished = await lookup(name);
  if (alreadyPublished.contains(package.version)) {
    return PublishDecision(
      package: name,
      shouldPublish: false,
      reason: '${package.name} ${package.version} is already on pub.dev',
    );
  }
  return PublishDecision(
    package: name,
    shouldPublish: true,
    reason: 'publishing ${package.name} ${package.version}',
  );
}

String _describe(Set<Version> versions) {
  final sorted = versions.toList()..sort();
  return sorted.length <= 3
      ? sorted.join(', ')
      : '${sorted.take(2).join(', ')} … ${sorted.last}';
}

/// Reads the versions pub.dev serves for [package], retrying transient errors.
///
/// A missing package is not an error: it is a package whose first version this
/// run may be publishing. Anything else is retried, because a release must not
/// fail on one flaky read, and must not mistake a flaky read for "nothing is
/// published yet" — which would let an ordering blocker through.
Future<Set<Version>> fetchPublishedVersions(
  String package, {
  int attempts = 3,
  Duration retryDelay = const Duration(seconds: 2),
  Future<void> Function(Duration duration) delay = _sleep,
  Uri? registry,
}) async {
  final base = registry ?? Uri.parse('https://pub.dev');
  Object? lastError;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        base.replace(path: '/api/packages/$package'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == HttpStatus.notFound) {
        return const <Version>{};
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'pub.dev answered ${response.statusCode} for $package',
        );
      }
      return parsePublishedVersions(body);
    } on Object catch (error) {
      lastError = error;
      if (attempt < attempts) {
        await delay(retryDelay * attempt);
      }
    } finally {
      client.close(force: true);
    }
  }
  throw StateError(
    'Could not read pub.dev for $package after $attempts attempts: '
    '$lastError',
  );
}

/// The versions in a pub.dev `/api/packages/<name>` document.
Set<Version> parsePublishedVersions(String body) {
  final document = jsonDecode(body);
  if (document is! Map || document['versions'] is! List) {
    throw const FormatException('pub.dev returned no version list');
  }
  return <Version>{
    for (final entry in document['versions'] as List)
      if (entry is Map && entry['version'] is String)
        Version.parse(entry['version'] as String),
  };
}

Future<void> _sleep(Duration duration) => Future<void>.delayed(duration);

/// Rewrites [publicationFile] from what pub.dev actually serves.
///
/// pub.dev is the source of truth for "what is published"; `publication.json`
/// is a cache of it that the website's availability labels read, and
/// `website/src/generated/availability.ts` is derived from both that cache and
/// the manifests. Deriving the cache from the registry rather than from the
/// manifests is what keeps a label from claiming a version that a release
/// abandoned halfway.
///
/// Returns the packages whose recorded version changed.
Future<List<String>> recordPublication(
  List<ReleasePackage> workspace,
  File publicationFile, {
  required RegistryLookup lookup,
}) async {
  final recorded =
      jsonDecode(publicationFile.readAsStringSync()) as Map<String, Object?>;
  final changed = <String>[];
  final updated = <String, Object?>{};
  for (final package in workspace) {
    final published = await lookup(package.name);
    final latest = latestStableOrPrerelease(published);
    final before = recorded[package.name];
    final after = latest?.toString();
    if (before != after) changed.add(package.name);
    updated[package.name] = after;
  }
  if (changed.isNotEmpty) {
    publicationFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(updated)}\n',
    );
  }
  return changed;
}

/// The version a consumer gets from `dart pub add`, or null when there is none.
///
/// A prerelease only wins when nothing stable has shipped, which is how
/// `noir_driver` and `noir_signals` read today and how `noir` read before
/// 0.0.1. Pub resolves a bare constraint to the newest stable version, so a
/// stable release must not be reported as superseded by an older prerelease.
Version? latestStableOrPrerelease(Set<Version> versions) {
  if (versions.isEmpty) return null;
  final stable = versions.where((version) => !version.isPreRelease).toList();
  final candidates = stable.isNotEmpty ? stable : versions.toList();
  return candidates.reduce((a, b) => a > b ? a : b);
}
