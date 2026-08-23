import 'package:pub_api_client/pub_api_client.dart';

/// Sort orders supported by pub.dev search.
enum PackageSort {
  /// Pub.dev's combined ranking.
  top,

  /// Text relevance only.
  text,

  /// Newest package creation first.
  created,

  /// Most recently updated first.
  updated,

  /// Download count first.
  downloads,

  /// Like count first.
  likes,

  /// Pub points first.
  points,

  /// Recently accelerating package interest first.
  trending,
}

/// API-supported search filters the example can send as pub.dev tags.
enum PackageSearchFilter {
  /// No extra tag.
  any,

  /// `sdk:dart`.
  dart,

  /// `sdk:flutter`.
  flutter,

  /// `is:flutter-favorite`.
  favorite,
}

/// Kind of a prefix suggestion. Only the payloads pub.dev actually returns.
enum PubSuggestionKind {
  /// A package name from `packageNameCompletion` or `search`.
  package,

  /// A topic name plus package count from `topicNameCompletion`.
  topic,
}

/// One completion row. Package rows are names only; topic rows carry a count.
final class PubSuggestion {
  /// A package-name suggestion.
  const PubSuggestion.package(this.name)
    : kind = PubSuggestionKind.package,
      packageCount = null;

  /// A topic suggestion with the number of packages using it.
  const PubSuggestion.topic(this.name, this.packageCount)
    : kind = PubSuggestionKind.topic;

  /// Package or topic.
  final PubSuggestionKind kind;

  /// Package name or topic slug.
  final String name;

  /// Package count for a topic; null for a package name.
  final int? packageCount;
}

/// One immutable page of package-name search results.
///
/// The page deliberately does not echo the query or sort order back. The
/// application already owns both, so repeating them here would create a second
/// source of truth that could disagree with the controls on screen.
final class PackageSearchPage {
  /// Creates a result page.
  PackageSearchPage({
    required this.page,
    required List<String> packages,
    required this.hasNextPage,
    this.message,
  }) : packages = List.unmodifiable(packages);

  /// One-based result page.
  final int page;

  /// Package names returned by pub.dev.
  final List<String> packages;

  /// Whether pub.dev supplied a next-page URL.
  final bool hasNextPage;

  /// Server note when the query could not be fully honoured.
  final String? message;
}

/// Documentation and release information for one published version.
final class PackageRelease {
  /// Creates a release summary.
  const PackageRelease({
    required this.version,
    required this.published,
    required this.retracted,
    required this.archiveUrl,
    required this.archiveSha256,
    this.hasDocumentation,
    this.documentationStatus,
  });

  /// Semantic version string.
  final String version;

  /// Publication time reported by pub.dev.
  final DateTime published;

  /// Whether this release was retracted.
  final bool retracted;

  /// Download URL for this release's archive.
  final String archiveUrl;

  /// SHA-256 digest reported for this release's archive.
  final String archiveSha256;

  /// Whether hosted API documentation exists, when known.
  final bool? hasDocumentation;

  /// Documentation build status, when known.
  final String? documentationStatus;
}

/// A security advisory reduced to terminal-friendly fields.
final class PackageAdvisorySummary {
  /// Creates an advisory summary.
  PackageAdvisorySummary({
    required this.id,
    this.summary,
    this.details,
    this.url,
    List<String> affectedVersions = const [],
  }) : affectedVersions = List.unmodifiable(affectedVersions);

  /// Advisory identifier.
  final String id;

  /// Short advisory title from OSV.
  final String? summary;

  /// Advisory body. Live pub.dev payloads are sometimes GitHub-flavoured
  /// markdown and sometimes plain prose.
  final String? details;

  /// Pub.dev display URL.
  final String? url;

  /// Explicitly affected versions reported by OSV.
  final List<String> affectedVersions;
}

/// One section from the package analyzer report.
final class PackageHealthSection {
  /// Creates an analyzer section summary.
  const PackageHealthSection({
    required this.title,
    required this.status,
    required this.summary,
    this.grantedPoints,
    this.maxPoints,
  });

  /// Human-readable section title.
  final String title;

  /// Analyzer status.
  final String status;

  /// GitHub-flavoured markdown from pana's `ReportSection.summary`.
  final String summary;

  /// Points granted for this section.
  final int? grantedPoints;

  /// Maximum points for this section.
  final int? maxPoints;
}

/// A screenshot entry from the package pubspec.
final class PackageScreenshotSummary {
  /// Creates a screenshot summary.
  const PackageScreenshotSummary({
    required this.description,
    required this.path,
  });

  /// Screenshot description.
  final String description;

  /// Package-relative screenshot path.
  final String path;
}

/// Download counts attributed to one semantic-version range.
final class PackageVersionDownloads {
  /// Creates a version-range history.
  PackageVersionDownloads({
    required this.versionRange,
    required List<int> counts,
  }) : counts = List.unmodifiable(counts);

  /// Pub's semantic-version range expression.
  final String versionRange;

  /// Weekly counts ordered oldest to newest.
  final List<int> counts;
}

/// Source kinds supported by pubspec dependencies.
enum PackageDependencySource {
  /// A package hosted on pub.dev or another package repository.
  hosted,

  /// A package fetched from Git.
  git,

  /// A package loaded from a local path.
  path,

  /// A package supplied by an SDK.
  sdk,
}

/// Structured, terminal-friendly dependency metadata from a package pubspec.
final class PackageDependencySummary {
  /// Creates a dependency summary.
  const PackageDependencySummary({
    required this.source,
    this.constraint,
    this.packageName,
    this.url,
    this.ref,
    this.path,
    this.sdk,
  });

  /// Dependency source kind.
  final PackageDependencySource source;

  /// Hosted or SDK version constraint.
  final String? constraint;

  /// Declared hosted package name, including aliases.
  final String? packageName;

  /// Hosted repository or Git URL.
  final String? url;

  /// Git ref.
  final String? ref;

  /// Git subpath or local package path.
  final String? path;

  /// SDK name.
  final String? sdk;

  /// Complete compact representation for the Dependencies tab.
  String get displayValue {
    final values = switch (source) {
      PackageDependencySource.hosted => [
        constraint ?? 'any',
        if (packageName case final value?) 'package $value',
        if (url case final value?) 'hosted $value',
      ],
      PackageDependencySource.git => [
        if (url case final value?) 'git $value' else 'git',
        if (ref case final value?) 'ref $value',
        if (path case final value?) 'path $value',
      ],
      PackageDependencySource.path => [
        if (path case final value?) 'path $value' else 'path',
      ],
      PackageDependencySource.sdk => [
        if (sdk case final value?) 'sdk $value' else 'sdk',
        ?constraint,
      ],
    };
    return values.join(' · ');
  }
}

/// Repository metadata inferred by pana.
final class PackageRepositorySummary {
  /// Creates a repository summary.
  const PackageRepositorySummary({
    this.provider,
    this.host,
    this.repository,
    this.branch,
  });

  /// Source host provider, such as GitHub.
  final String? provider;

  /// Repository host.
  final String? host;

  /// Owner and repository name.
  final String? repository;

  /// Default branch.
  final String? branch;
}

/// Application-owned view of the useful typed package API responses.
final class PubPackageSnapshot {
  /// Creates a package snapshot, primarily for deterministic examples/tests.
  PubPackageSnapshot({
    required this.name,
    required this.version,
    required this.description,
    required this.published,
    this.packageUrl = '',
    this.changelogUrl = '',
    this.retracted = false,
    this.publisher,
    Map<String, String> environment = const {},
    this.homepage,
    this.repository,
    this.issueTracker,
    this.documentationUrl,
    this.contributingUrl,
    List<String> fundingUrls = const [],
    List<String> topics = const [],
    List<String> platforms = const [],
    List<String> runtimes = const [],
    List<String> licenses = const [],
    this.publishTo,
    List<PackageScreenshotSummary> screenshots = const [],
    Map<String, PackageDependencySummary> directDependencies = const {},
    Map<String, PackageDependencySummary> devDependencies = const {},
    Map<String, PackageDependencySummary> dependencyOverrides = const {},
    List<String> transitiveDependencies = const [],
    Map<String, String?> executables = const {},
    List<String> workspace = const [],
    this.resolution,
    this.grantedPoints,
    this.maxPoints,
    this.likeCount,
    this.downloadCount30Days,
    List<PackageRelease> releases = const [],
    this.isDiscontinued = false,
    this.replacedBy,
    this.isUnlisted = false,
    List<PackageAdvisorySummary> advisories = const [],
    this.advisoriesUpdated,
    this.analysisStatus,
    this.dartdocStatus,
    this.taskStatus,
    List<PackageHealthSection> healthSections = const [],
    List<String> urlProblems = const [],
    List<String> analysisScreenshots = const [],
    this.archiveUrl = '',
    this.archiveSha256 = '',
    this.metricsUpdated,
    this.analysisUpdated,
    this.scorecardPackageVersion,
    this.scorecardRuntimeVersion,
    this.panaVersion,
    this.analyzedSdkVersion,
    this.analyzedFlutterVersion,
    this.repositorySummary,
    this.analysisGrantedPoints,
    this.analysisMaxPoints,
    List<int> weeklyDownloads = const [],
    List<PackageVersionDownloads> majorVersionDownloads = const [],
    this.weeklyDownloadsNewestDate,
  }) : environment = Map.unmodifiable(environment),
       fundingUrls = List.unmodifiable(fundingUrls),
       topics = List.unmodifiable(topics),
       platforms = List.unmodifiable(platforms),
       runtimes = List.unmodifiable(runtimes),
       licenses = List.unmodifiable(licenses),
       screenshots = List.unmodifiable(screenshots),
       directDependencies = Map.unmodifiable(directDependencies),
       devDependencies = Map.unmodifiable(devDependencies),
       dependencyOverrides = Map.unmodifiable(dependencyOverrides),
       transitiveDependencies = List.unmodifiable(transitiveDependencies),
       executables = Map.unmodifiable(executables),
       workspace = List.unmodifiable(workspace),
       releases = List.unmodifiable(releases),
       advisories = List.unmodifiable(advisories),
       healthSections = List.unmodifiable(healthSections),
       urlProblems = List.unmodifiable(urlProblems),
       analysisScreenshots = List.unmodifiable(analysisScreenshots),
       weeklyDownloads = List.unmodifiable(weeklyDownloads),
       majorVersionDownloads = List.unmodifiable(majorVersionDownloads);

  /// Maps the public client responses into an application-owned snapshot.
  factory PubPackageSnapshot.fromApi({
    required PubPackage package,
    required PackageScore? score,
    required PackageMetrics? metrics,
    required PackagePublisher? publisher,
    required PackageOptions? options,
    required PackageDocumentation? documentation,
    required PackageAdvisories? advisories,
  }) {
    final pubspec = package.latestPubspec;
    final effectiveScore = metrics?.score ?? score;
    final tags = effectiveScore?.tags ?? const <String>[];
    final scorecard = metrics?.scorecard;
    final pana = scorecard?.panaReport;
    final result = pana?.result;
    final weekly = scorecard?.weeklyVersionDownloads;
    final docsByVersion = {
      for (final item
          in documentation?.versions ?? const <PackageDocumentationVersion>[])
        item.version: item,
    };
    final metricLicenses =
        pana?.licenses
            ?.map(
              (license) => [
                ?license.spdxIdentifier,
                if (license.path case final value?) '($value)',
              ].join(' '),
            )
            .where((value) => value.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    final resultRepository = result?.repository;
    final flutterVersions = pana?.panaRuntimeInfo?.flutterVersions;

    return PubPackageSnapshot(
      name: package.name,
      version: package.version,
      description: package.description,
      published: package.latest.published,
      packageUrl: package.url,
      changelogUrl: package.changelogUrl,
      retracted: package.latest.retracted,
      publisher: publisher?.publisherId,
      environment: pubspec.environment.map(
        (name, constraint) => MapEntry(name, '$constraint'),
      ),
      homepage: pubspec.homepage ?? result?.homepageUrl,
      repository: pubspec.repository?.toString() ?? result?.repositoryUrl,
      issueTracker: pubspec.issueTracker?.toString() ?? result?.issueTrackerUrl,
      documentationUrl: pubspec.documentation ?? result?.documentationUrl,
      contributingUrl: result?.contributingUrl,
      fundingUrls:
          pubspec.funding?.map((uri) => '$uri').toList(growable: false) ??
          result?.fundingUrls ??
          const <String>[],
      topics: pubspec.topics ?? const <String>[],
      platforms: _tagValues(tags, 'platform:'),
      runtimes: _tagValues(tags, 'runtime:'),
      licenses: metricLicenses.isNotEmpty
          ? metricLicenses
          : _tagValues(tags, 'license:'),
      publishTo: pubspec.publishTo,
      screenshots: (pubspec.screenshots ?? const [])
          .map(
            (screenshot) => PackageScreenshotSummary(
              description: screenshot.description,
              path: screenshot.path,
            ),
          )
          .toList(growable: false),
      directDependencies: pubspec.dependencies.map(
        (name, dependency) =>
            MapEntry(name, _dependencySummary(name, dependency)),
      ),
      devDependencies: pubspec.devDependencies.map(
        (name, dependency) =>
            MapEntry(name, _dependencySummary(name, dependency)),
      ),
      dependencyOverrides: pubspec.dependencyOverrides.map(
        (name, dependency) =>
            MapEntry(name, _dependencySummary(name, dependency)),
      ),
      transitiveDependencies: pana?.allDependencies ?? const <String>[],
      executables: pubspec.executables,
      workspace: pubspec.workspace ?? const <String>[],
      resolution: pubspec.resolution,
      grantedPoints: effectiveScore?.grantedPoints,
      maxPoints: effectiveScore?.maxPoints,
      likeCount: effectiveScore?.likeCount,
      downloadCount30Days: effectiveScore?.downloadCount30Days,
      releases: _newestFirst(
        package.versions.map<PackageRelease>((release) {
          final doc = docsByVersion[release.version];
          return PackageRelease(
            version: release.version,
            published: release.published,
            retracted: release.retracted,
            archiveUrl: release.archiveUrl,
            archiveSha256: release.archiveSha256,
            hasDocumentation: doc?.hasDocumentation,
            documentationStatus: doc?.status,
          );
        }),
      ),
      isDiscontinued:
          options?.isDiscontinued ?? package.isDiscontinued ?? false,
      replacedBy: options?.replacedBy ?? package.replacedBy,
      isUnlisted: options?.isUnlisted ?? false,
      advisories: (advisories?.advisories ?? const <SecurityAdvisory>[])
          .map(
            (advisory) => PackageAdvisorySummary(
              id: advisory.id,
              summary: advisory.summary,
              details: advisory.details,
              url: advisory.pubDisplayUrl,
              affectedVersions:
                  advisory.affected
                      ?.expand(
                        (affected) => affected.versions ?? const <String>[],
                      )
                      .toSet()
                      .toList(growable: false) ??
                  const <String>[],
            ),
          )
          .toList(growable: false),
      advisoriesUpdated:
          advisories?.advisoriesUpdated ?? package.advisoriesUpdated,
      analysisStatus: pana?.reportStatus,
      dartdocStatus: scorecard?.dartdocReport?.reportStatus,
      taskStatus: scorecard?.taskStatus,
      healthSections: (pana?.report?.sections ?? const <Section>[])
          .map(
            (section) => PackageHealthSection(
              title: section.title ?? section.id ?? 'Check',
              status: section.status ?? 'unknown',
              summary: section.summary ?? '',
              grantedPoints: section.grantedPoints,
              maxPoints: section.maxPoints,
            ),
          )
          .toList(growable: false),
      urlProblems: _diagnosticSummaries(pana?.urlProblems, const [
        'url',
        'problem',
        'message',
      ]),
      analysisScreenshots: _diagnosticSummaries(pana?.screenshots, const [
        'description',
        'path',
        'url',
      ]),
      archiveUrl: package.latest.archiveUrl,
      archiveSha256: package.latest.archiveSha256,
      metricsUpdated: scorecard?.updated,
      analysisUpdated: pana?.timestamp,
      scorecardPackageVersion: scorecard?.packageVersion,
      scorecardRuntimeVersion: scorecard?.runtimeVersion,
      panaVersion: pana?.panaRuntimeInfo?.panaVersion,
      analyzedSdkVersion: pana?.panaRuntimeInfo?.sdkVersion,
      analyzedFlutterVersion:
          flutterVersions?.flutterVersion ?? flutterVersions?.frameworkVersion,
      repositorySummary: resultRepository == null
          ? null
          : PackageRepositorySummary(
              provider: resultRepository.provider,
              host: resultRepository.host,
              repository: resultRepository.repository,
              branch: resultRepository.branch,
            ),
      analysisGrantedPoints: result?.grantedPoints,
      analysisMaxPoints: result?.maxPoints,
      weeklyDownloads: weekly?.totalWeeklyDownloads ?? const <int>[],
      majorVersionDownloads: _versionDownloads(
        weekly?.majorRangeWeeklyDownloads,
      ),
      weeklyDownloadsNewestDate: weekly?.newestDate,
    );
  }

  /// Package name.
  final String name;

  /// Latest version.
  final String version;

  /// Latest pubspec description.
  final String description;

  /// Latest publication time.
  final DateTime published;

  /// Canonical pub.dev package page.
  final String packageUrl;

  /// Canonical pub.dev changelog page.
  final String changelogUrl;

  /// Whether the latest release is retracted.
  final bool retracted;

  /// Verified publisher identifier.
  final String? publisher;

  /// Pubspec environment constraints.
  final Map<String, String> environment;

  /// Homepage URL.
  final String? homepage;

  /// Repository URL.
  final String? repository;

  /// Issue tracker URL.
  final String? issueTracker;

  /// Documentation URL.
  final String? documentationUrl;

  /// Contributing guide URL inferred by pana.
  final String? contributingUrl;

  /// Funding URLs.
  final List<String> fundingUrls;

  /// Pubspec topics.
  final List<String> topics;

  /// Supported platforms derived from score tags.
  final List<String> platforms;

  /// Supported runtimes derived from score tags.
  final List<String> runtimes;

  /// License identifiers and paths.
  final List<String> licenses;

  /// Pubspec publication target.
  final String? publishTo;

  /// Pubspec screenshots.
  final List<PackageScreenshotSummary> screenshots;

  /// Direct runtime dependencies.
  final Map<String, PackageDependencySummary> directDependencies;

  /// Direct development dependencies.
  final Map<String, PackageDependencySummary> devDependencies;

  /// Pubspec dependency overrides.
  final Map<String, PackageDependencySummary> dependencyOverrides;

  /// All dependencies observed by pana.
  final List<String> transitiveDependencies;

  /// Package executables.
  final Map<String, String?> executables;

  /// Workspace members.
  final List<String> workspace;

  /// Pub workspace resolution mode.
  final String? resolution;

  /// Granted pub points.
  final int? grantedPoints;

  /// Maximum pub points.
  final int? maxPoints;

  /// Like count.
  final int? likeCount;

  /// Downloads in the latest 30-day window.
  final int? downloadCount30Days;

  /// Published versions.
  final List<PackageRelease> releases;

  /// Whether the package is discontinued.
  final bool isDiscontinued;

  /// Replacement package, when discontinued.
  final String? replacedBy;

  /// Whether the package is hidden from search.
  final bool isUnlisted;

  /// Security advisories.
  final List<PackageAdvisorySummary> advisories;

  /// Time the advisory set was refreshed.
  final DateTime? advisoriesUpdated;

  /// Pana report status.
  final String? analysisStatus;

  /// Dartdoc report status.
  final String? dartdocStatus;

  /// Scorecard task status.
  final String? taskStatus;

  /// Individual pana report sections.
  final List<PackageHealthSection> healthSections;

  /// URL problems reported by pana.
  final List<String> urlProblems;

  /// Screenshot checks reported by pana.
  final List<String> analysisScreenshots;

  /// Latest archive URL.
  final String archiveUrl;

  /// Latest archive SHA-256.
  final String archiveSha256;

  /// Scorecard update time.
  final DateTime? metricsUpdated;

  /// Pana analysis time.
  final DateTime? analysisUpdated;

  /// Package version analyzed by the scorecard.
  final String? scorecardPackageVersion;

  /// Scorecard runtime version.
  final String? scorecardRuntimeVersion;

  /// Pana version.
  final String? panaVersion;

  /// SDK version used for analysis.
  final String? analyzedSdkVersion;

  /// Flutter version used for analysis.
  final String? analyzedFlutterVersion;

  /// Repository identity inferred by pana.
  final PackageRepositorySummary? repositorySummary;

  /// Pana result points.
  final int? analysisGrantedPoints;

  /// Pana result maximum points.
  final int? analysisMaxPoints;

  /// Total weekly download history.
  final List<int> weeklyDownloads;

  /// Weekly downloads grouped by major-version ranges.
  final List<PackageVersionDownloads> majorVersionDownloads;

  /// Date of the newest weekly count.
  final DateTime? weeklyDownloadsNewestDate;
}

/// Builds a compact terminal sparkline for a sequence of download counts.
String downloadSparkline(List<int> values) {
  if (values.isEmpty) return 'Not available';
  const levels = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];
  final minValue = values.reduce((a, b) => a < b ? a : b);
  final maxValue = values.reduce((a, b) => a > b ? a : b);
  if (maxValue == minValue) return List.filled(values.length, '▁').join();
  return values
      .map(
        (value) =>
            levels[(((value - minValue) / (maxValue - minValue)) * 7).round()],
      )
      .join();
}

/// Returns an immutable recent window from a complete download history.
List<int> recentDownloadCounts(List<int> values, {int limit = 26}) {
  if (limit <= 0) {
    throw ArgumentError.value(limit, 'limit', 'Must be greater than zero.');
  }
  final start = values.length > limit ? values.length - limit : 0;
  return List.unmodifiable(values.skip(start));
}

List<PackageRelease> _newestFirst(Iterable<PackageRelease> releases) {
  final ordered = releases.toList();
  ordered.sort((a, b) => b.published.compareTo(a.published));
  return List.unmodifiable(ordered);
}

List<PackageVersionDownloads> _versionDownloads(
  List<VersionRangeWeeklyDownloads>? values,
) => (values ?? const <VersionRangeWeeklyDownloads>[])
    .map(
      (value) => PackageVersionDownloads(
        versionRange: value.versionRange,
        counts: value.counts,
      ),
    )
    .toList(growable: false);

List<String> _tagValues(List<String> tags, String prefix) => tags
    .where((tag) => tag.startsWith(prefix))
    .map((tag) => tag.substring(prefix.length))
    .toList(growable: false);

PackageDependencySummary _dependencySummary(
  String name,
  Dependency dependency,
) => switch (dependency) {
  HostedDependency(:final version, :final hosted) => PackageDependencySummary(
    source: PackageDependencySource.hosted,
    constraint: '$version',
    packageName: hosted == null ? null : hosted.declaredName ?? name,
    url: hosted?.url?.toString(),
  ),
  GitDependency(:final url, :final ref, :final path) =>
    PackageDependencySummary(
      source: PackageDependencySource.git,
      url: '$url',
      ref: ref,
      path: path,
    ),
  PathDependency(:final path) => PackageDependencySummary(
    source: PackageDependencySource.path,
    path: path,
  ),
  SdkDependency(:final sdk, :final version) => PackageDependencySummary(
    source: PackageDependencySource.sdk,
    sdk: sdk,
    constraint: '$version',
  ),
};

/// Renders analyzer diagnostics through an explicit field allowlist.
///
/// These entries are untyped server data whose shape can change without
/// notice. Only the named keys are read, so a new or nested field can never
/// leak raw JSON into the terminal.
List<String> _diagnosticSummaries(
  List<dynamic>? values,
  List<String> allowedKeys,
) => (values ?? const <dynamic>[])
    .map((value) {
      if (value is String && value.isNotEmpty) return value;
      if (value is! Map) return null;
      final parts = <String>[];
      for (final key in allowedKeys) {
        final field = value[key];
        if (field is String && field.isNotEmpty ||
            field is num ||
            field is bool) {
          parts.add('$key: $field');
        }
      }
      return parts.isEmpty ? null : parts.join('; ');
    })
    .whereType<String>()
    .toList(growable: false);
