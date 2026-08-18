import 'package:noir/noir.dart';

import 'models.dart';
import 'theme.dart';

/// The four calm, full-width package detail sections.
enum PackageDetailTab {
  /// Identity, compatibility, discovery, and links.
  overview,

  /// Published versions and artifacts.
  versions,

  /// Direct, development, override, and transitive dependencies.
  dependencies,

  /// Downloads, scoring, analysis, and advisories.
  health,
}

/// Spaced package detail surface used by the pub search example.
class PubPackageDetail extends StatelessWidget {
  /// Creates a detail surface with application-owned scroll/focus state.
  const PubPackageDetail({
    required this.package,
    required this.activeTab,
    required this.scrollController,
    required this.scrollFocusNode,
    super.key,
  });

  /// Package data to display.
  final PubPackageSnapshot package;

  /// Visible tab.
  final PackageDetailTab activeTab;

  /// Vertical content position.
  final ScrollController scrollController;

  /// Keyboard focus for scrolling.
  final FocusNode scrollFocusNode;

  @override
  Widget build(BuildContext context) {
    final content = switch (activeTab) {
      PackageDetailTab.overview => _buildOverview(package),
      PackageDetailTab.versions => _buildVersions(package),
      PackageDetailTab.dependencies => _buildDependencies(package),
      PackageDetailTab.health => _buildHealth(package),
    };
    return Container(
      color: pubBackground,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('PUB / PACKAGE', style: TextStyle(color: pubMuted)),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: package.name,
                  style: const TextStyle(
                    color: pubAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: '  ${package.version}',
                  style: const TextStyle(color: pubHighlight),
                ),
              ],
            ),
          ),
          Text(package.description, maxLines: 2),
          Text(
            'dart pub add ${package.name}',
            style: const TextStyle(
              color: pubHighlight,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          _headlineMetrics(package),
          const SizedBox(height: 1),
          Row(
            children: [
              for (final tab in PackageDetailTab.values)
                Expanded(child: _tabLabel(tab)),
            ],
          ),
          const SizedBox(height: 1),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: pubPanel,
                border: Border.all(color: pubBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              child: ScrollBox(
                controller: scrollController,
                focusNode: scrollFocusNode,
                autofocus: true,
                scrollbarColor: pubAccent,
                trackColor: pubBorder,
                child: content,
              ),
            ),
          ),
          const SizedBox(height: 1),
          const Text(
            '←→ / 1–4 section   ↑↓ / PgUp/PgDn scroll   / search   Esc results',
            style: TextStyle(color: pubMuted),
          ),
        ],
      ),
    );
  }

  Widget _tabLabel(PackageDetailTab tab) {
    final active = tab == activeTab;
    return Container(
      color: active ? pubActivePanel : pubBackground,
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        '${tab.index + 1} ${tab.name.toUpperCase()}',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: active ? pubAccent : pubMuted,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

Widget _headlineMetrics(PubPackageSnapshot package) => Row(
  children: [
    Expanded(
      child: _metric(
        '${package.grantedPoints ?? '—'}/${package.maxPoints ?? '—'}',
        'POINTS',
      ),
    ),
    Expanded(
      child: _metric(_number(package.downloadCount30Days), 'DOWNLOADS / 30D'),
    ),
    Expanded(child: _metric(_number(package.likeCount), 'LIKES')),
    Expanded(child: _metric('${package.releases.length}', 'VERSIONS')),
  ],
);

Widget _metric(String value, String label) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      value,
      style: const TextStyle(color: pubHighlight, fontWeight: FontWeight.bold),
    ),
    Text(label, style: const TextStyle(color: pubMuted)),
  ],
);

Widget _buildOverview(PubPackageSnapshot package) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    ..._section('PACKAGE PROFILE', [
      _fact('PUBLISHER', package.publisher),
      _fact('PUBLISHED', _date(package.published)),
      _fact('LATEST', package.version),
      _fact('STATUS', _packageStatus(package)),
      _fact('REPLACED BY', package.replacedBy),
    ]),
    ..._section('RUNS ON', [
      _fact('PLATFORMS', _joined(package.platforms)),
      _fact('RUNTIMES', _joined(package.runtimes)),
      ..._mapFacts(package.environment),
    ]),
    ..._section('DISCOVERY', [
      _fact('TOPICS', _joined(package.topics)),
      _fact('LICENSES', _joined(package.licenses)),
      _fact('SCORE TAGS', _joined(package.tags)),
      _fact('DERIVED TAGS', _joined(package.derivedTags)),
    ]),
    ..._section('LINKS', [
      _fact('PUB.DEV', package.packageUrl),
      _fact('CHANGELOG', package.changelogUrl),
      _fact('HOMEPAGE', package.homepage),
      _fact('REPOSITORY', package.repository),
      _fact('ISSUES', package.issueTracker),
      _fact('DOCUMENTATION', package.documentationUrl),
      _fact('CONTRIBUTING', package.contributingUrl),
      _fact('FUNDING', _joined(package.fundingUrls)),
    ]),
    ..._section('PACKAGE CONFIG', [
      _fact('PUBLISH TO', package.publishTo),
      _fact('RESOLUTION', package.resolution),
      _fact('WORKSPACE', _joined(package.workspace)),
      _fact('FLUTTER KEYS', _joined(package.flutterKeys)),
      _fact('IGNORED ADVISORIES', _joined(package.ignoredAdvisories)),
      _fact('EXECUTABLES', _mapValue(package.executables)),
      _fact(
        'SCREENSHOTS',
        package.screenshots.isEmpty
            ? null
            : package.screenshots
                  .map((item) => '${item.description} — ${item.path}')
                  .join('; '),
      ),
    ]),
  ],
);

Widget _buildVersions(PubPackageSnapshot package) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    ..._section('PUBLISHED VERSIONS', [
      if (package.releases.isEmpty) const Text('Not provided'),
      for (final release in package.releases) ...[
        Text(
          '${release.version.padRight(18)} ${_date(release.published)}  '
          '${release.retracted ? 'RETRACTED' : 'active'}  '
          '${release.hasDocumentation == null
              ? 'docs unknown'
              : release.hasDocumentation!
              ? 'documented'
              : 'no docs'}'
          '${release.documentationStatus == null ? '' : ' (${release.documentationStatus})'}',
        ),
        _fact('ARCHIVE', release.archiveUrl),
        _fact('SHA-256', release.archiveSha256),
        const SizedBox(height: 1),
      ],
    ]),
    ..._section('LATEST ARCHIVE', [
      _fact('URL', package.archiveUrl),
      _fact('SHA-256', package.archiveSha256),
      _fact('RETRACTED', package.retracted ? 'yes' : 'no'),
    ]),
    ..._section('SCORECARD TARGET', [
      _fact('PACKAGE VERSION', package.scorecardPackageVersion),
      _fact('RUNTIME VERSION', package.scorecardRuntimeVersion),
      _fact('METRICS UPDATED', _dateTime(package.metricsUpdated)),
    ]),
  ],
);

Widget _buildDependencies(PubPackageSnapshot package) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    ..._section(
      'DIRECT DEPENDENCIES',
      _dependencyFacts(package.directDependencies),
    ),
    ..._section('DEV DEPENDENCIES', _dependencyFacts(package.devDependencies)),
    ..._section(
      'DEPENDENCY OVERRIDES',
      _dependencyFacts(package.dependencyOverrides),
    ),
    ..._section('ALL ANALYZED DEPENDENCIES', [
      Text(_joined(package.transitiveDependencies) ?? 'Not provided'),
    ]),
    ..._section('EXECUTABLES & WORKSPACE', [
      _fact('EXECUTABLES', _mapValue(package.executables)),
      _fact('MEMBERS', _joined(package.workspace)),
      _fact('RESOLUTION', package.resolution),
    ]),
  ],
);

Widget _buildHealth(PubPackageSnapshot package) {
  final recentWeekly = recentDownloadCounts(package.weeklyDownloads);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ..._section('WEEKLY DOWNLOADS', [
        Text(
          downloadSparkline(recentWeekly),
          style: const TextStyle(color: pubAccent, fontWeight: FontWeight.bold),
        ),
        _fact(
          'HISTORY',
          package.weeklyDownloads.isEmpty
              ? null
              : '${package.weeklyDownloads.length} weeks',
        ),
        _fact('RECENT ${recentWeekly.length}', _joinedInts(recentWeekly)),
        _fact('NEWEST WEEK', _date(package.weeklyDownloadsNewestDate)),
        ..._rangeFacts('MAJOR', package.majorVersionDownloads),
        ..._rangeFacts('MINOR', package.minorVersionDownloads),
        ..._rangeFacts('PATCH', package.patchVersionDownloads),
      ]),
      ..._section('PUB SCORE', [
        _fact(
          'POINTS',
          '${package.grantedPoints ?? '—'} / ${package.maxPoints ?? '—'}',
        ),
        _fact('LIKES', _number(package.likeCount)),
        _fact('DOWNLOADS / 30D', _number(package.downloadCount30Days)),
        _fact(
          'POPULARITY',
          package.popularityScore == null
              ? null
              : '${(package.popularityScore! * 100).round()}%',
        ),
      ]),
      ..._section('ANALYSIS', [
        _fact('PANA', package.analysisStatus),
        _fact('DARTDOC', package.dartdocStatus),
        _fact('TASK', package.taskStatus),
        _fact(
          'RESULT POINTS',
          package.analysisGrantedPoints == null &&
                  package.analysisMaxPoints == null
              ? null
              : '${package.analysisGrantedPoints ?? '—'} / ${package.analysisMaxPoints ?? '—'}',
        ),
        _fact('ANALYZED', _dateTime(package.analysisUpdated)),
        _fact('PANA VERSION', package.panaVersion),
        _fact('SDK', package.analyzedSdkVersion),
        _fact('FLUTTER', package.analyzedFlutterVersion),
      ]),
      ..._section('REPORT SECTIONS', [
        if (package.healthSections.isEmpty) const Text('Not provided'),
        for (final section in package.healthSections)
          Text(
            '${section.title} — ${section.status}  '
            '${section.grantedPoints ?? '—'}/${section.maxPoints ?? '—'}  '
            '${section.summary}',
          ),
      ]),
      ..._section('SECURITY', [
        _fact('UPDATED', _dateTime(package.advisoriesUpdated)),
        if (package.advisories.isEmpty) const Text('No advisories reported'),
        for (final advisory in package.advisories) ...[
          Text(
            '${advisory.id} — ${advisory.summary ?? 'No summary'}',
            style: const TextStyle(color: pubHighlight),
          ),
          _fact('DETAILS', advisory.details),
          _fact('AFFECTED', _joined(advisory.affectedVersions)),
          _fact('URL', advisory.url),
        ],
      ]),
      ..._section('DIAGNOSTICS', [
        _fact('URL PROBLEMS', _joined(package.urlProblems)),
        _fact('SCREENSHOT CHECKS', _joined(package.analysisScreenshots)),
      ]),
      ..._section('REPOSITORY', [
        _fact('PROVIDER', package.repositorySummary?.provider),
        _fact('HOST', package.repositorySummary?.host),
        _fact('REPOSITORY', package.repositorySummary?.repository),
        _fact('BRANCH', package.repositorySummary?.branch),
        _fact('UNLISTED', package.isUnlisted ? 'yes' : 'no'),
        _fact('DISCONTINUED', package.isDiscontinued ? 'yes' : 'no'),
      ]),
    ],
  );
}

List<Widget> _section(String title, List<Widget> children) => [
  Text(
    title,
    style: const TextStyle(color: pubMuted, fontWeight: FontWeight.bold),
  ),
  const SizedBox(height: 1),
  ...children,
  const SizedBox(height: 1),
];

Widget _fact(String label, String? value) => RichText(
  text: TextSpan(
    children: [
      TextSpan(
        text: '${label.padRight(19)} ',
        style: const TextStyle(color: pubMuted),
      ),
      TextSpan(text: _available(value)),
    ],
  ),
);

List<Widget> _mapFacts(Map<String, String> values) => values.isEmpty
    ? const [Text('Not provided')]
    : [
        for (final entry in values.entries)
          _fact(entry.key.toUpperCase(), entry.value),
      ];

List<Widget> _dependencyFacts(Map<String, PackageDependencySummary> values) =>
    values.isEmpty
    ? const [Text('None')]
    : [
        for (final entry in values.entries)
          _fact(entry.key, entry.value.displayValue),
      ];

List<Widget> _rangeFacts(String label, List<PackageVersionDownloads> values) =>
    values
        .map((value) {
          final counts = recentDownloadCounts(value.counts);
          return _fact(
            '$label ${value.versionRange}',
            '${downloadSparkline(counts)}  ${_joinedInts(counts)}',
          );
        })
        .toList(growable: false);

String _packageStatus(PubPackageSnapshot package) {
  if (package.isDiscontinued) return 'discontinued';
  if (package.isUnlisted) return 'unlisted';
  if (package.retracted) return 'latest release retracted';
  return 'active';
}

String _number(num? value) {
  if (value == null) return '—';
  final digits = value.toString();
  final parts = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    parts.add(digits.substring((end - 3).clamp(0, end), end));
  }
  return parts.reversed.join(',');
}

String? _joined(List<String> values) =>
    values.isEmpty ? null : values.join(', ');

String? _joinedInts(List<int> values) =>
    values.isEmpty ? null : values.map(_number).join(', ');

String? _mapValue(Map<String, String?> values) => values.isEmpty
    ? null
    : values.entries
          .map((entry) => '${entry.key}: ${entry.value ?? entry.key}')
          .join(', ');

String _available(String? value) =>
    value == null || value.isEmpty ? 'Not provided' : value;

String? _date(DateTime? value) => value?.toIso8601String().split('T').first;

String? _dateTime(DateTime? value) => value?.toUtc().toIso8601String();
