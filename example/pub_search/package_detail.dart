import 'package:noir/noir.dart';

import '../src/demo_scaffold.dart';
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

const _detailTabs = <SelectOption<PackageDetailTab>>[
  SelectOption(name: '1 OVERVIEW', value: PackageDetailTab.overview),
  SelectOption(name: '2 VERSIONS', value: PackageDetailTab.versions),
  SelectOption(name: '3 DEPENDENCIES', value: PackageDetailTab.dependencies),
  SelectOption(name: '4 HEALTH', value: PackageDetailTab.health),
];

/// Spaced package detail surface used by the pub search example.
class PubPackageDetail extends StatelessWidget {
  /// Creates a detail surface with application-owned scroll/focus state.
  const PubPackageDetail({
    required this.package,
    required this.activeTab,
    required this.onTabSelected,
    required this.scrollController,
    required this.scrollFocusNode,
    super.key,
  });

  /// Package data to display.
  final PubPackageSnapshot package;

  /// Visible tab.
  final PackageDetailTab activeTab;

  /// Selects a section from a tab click.
  final ValueChanged<PackageDetailTab> onTabSelected;

  /// Vertical content position.
  final ScrollController scrollController;

  /// Keyboard focus for scrolling.
  final FocusNode scrollFocusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = switch (activeTab) {
      PackageDetailTab.overview => _buildOverview(package, theme),
      PackageDetailTab.versions => _buildVersions(package, theme),
      PackageDetailTab.dependencies => _buildDependencies(package, theme),
      PackageDetailTab.health => _buildHealth(package, theme),
    };
    return DemoScaffold(
      title: package.name,
      hint: package.description,
      titleTrailing: [
        Text(
          package.version,
          style: const TextStyle(
            color: pubEmphasis,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (package.publisher != null)
          Text(package.publisher, style: TextStyle(color: theme.textMuted)),
      ],
      child: Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'dart pub add ${package.name}',
              style: const TextStyle(
                color: pubEmphasis,
                fontWeight: FontWeight.bold,
              ),
            ),
            _headlineMetrics(package, theme),
            const SizedBox(height: 1),
            TabSelect<PackageDetailTab>(
              options: _detailTabs,
              selectedIndex: activeTab.index,
              tabWidth: null,
              showDescription: false,
              showUnderline: false,
              requestFocusOnPointer: false,
              color: theme.textMuted,
              selectedBackgroundColor: theme.accent,
              selectedTextColor: theme.accentForeground,
              selectedTextAttributes: Attr.bold,
              onChanged: (index, option) {
                final tab = option.value;
                if (tab != null) onTabSelected(tab);
              },
            ),
            Expanded(
              child: DemoPanel(
                focused: scrollFocusNode.hasFocus,
                child: ScrollBox(
                  controller: scrollController,
                  focusNode: scrollFocusNode,
                  autofocus: true,
                  child: content,
                ),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              '←→/1–4/click tabs  ↑↓/PgUp/PgDn scroll  / search  Esc results',
              style: TextStyle(color: theme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _headlineMetrics(PubPackageSnapshot package, ThemeData theme) => Row(
  children: [
    Expanded(
      child: _metric(
        theme,
        '${package.grantedPoints ?? '—'}/${package.maxPoints ?? '—'}',
        'POINTS',
      ),
    ),
    Expanded(
      child: _metric(
        theme,
        _number(package.downloadCount30Days),
        'DOWNLOADS 30D',
      ),
    ),
    Expanded(child: _metric(theme, _number(package.likeCount), 'LIKES')),
    Expanded(child: _metric(theme, '${package.releases.length}', 'VERSIONS')),
  ],
);

Widget _metric(ThemeData theme, String value, String label) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      value,
      style: const TextStyle(color: pubEmphasis, fontWeight: FontWeight.bold),
    ),
    Text(label, style: TextStyle(color: theme.textMuted)),
  ],
);

Widget _buildOverview(PubPackageSnapshot package, ThemeData theme) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    ..._section(theme, 'PACKAGE PROFILE', [
      _fact(theme, 'PUBLISHED', _date(package.published)),
      _fact(theme, 'LATEST', package.version),
      _fact(theme, 'STATUS', _packageStatus(package)),
      _fact(theme, 'REPLACED BY', package.replacedBy),
    ]),
    ..._section(theme, 'RUNS ON', [
      _fact(theme, 'PLATFORMS', _joined(package.platforms)),
      _fact(theme, 'RUNTIMES', _joined(package.runtimes)),
      ..._mapFacts(theme, package.environment),
    ]),
    ..._section(theme, 'DISCOVERY', [
      _fact(theme, 'TOPICS', _joined(package.topics)),
      _fact(theme, 'LICENSES', _joined(package.licenses)),
    ]),
    ..._section(theme, 'LINKS', [
      _fact(theme, 'PUB.DEV', package.packageUrl),
      _fact(theme, 'CHANGELOG', package.changelogUrl),
      _fact(theme, 'HOMEPAGE', package.homepage),
      _fact(theme, 'REPOSITORY', package.repository),
      _fact(theme, 'ISSUES', package.issueTracker),
      _fact(theme, 'DOCUMENTATION', package.documentationUrl),
      _fact(theme, 'CONTRIBUTING', package.contributingUrl),
      _fact(theme, 'FUNDING', _joined(package.fundingUrls)),
    ]),
    ..._section(theme, 'PACKAGE CONFIG', [
      _fact(theme, 'PUBLISH TO', package.publishTo),
      _fact(theme, 'RESOLUTION', package.resolution),
      _fact(theme, 'WORKSPACE', _joined(package.workspace)),
      _fact(theme, 'EXECUTABLES', _mapValue(package.executables)),
      _fact(
        theme,
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

Widget _buildVersions(PubPackageSnapshot package, ThemeData theme) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    ..._section(theme, 'PUBLISHED VERSIONS', [
      if (package.releases.isEmpty) const Text('Not provided'),
      for (final release in package.releases) ...[
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text:
                    '${release.version.padRight(18)} ${_date(release.published)}  ',
              ),
              TextSpan(
                text: release.retracted ? 'RETRACTED' : 'active',
                style: release.retracted
                    ? TextStyle(color: theme.danger)
                    : null,
              ),
              TextSpan(text: '  ${_documentationLabel(release)}'),
            ],
          ),
        ),
        _fact(theme, 'ARCHIVE', release.archiveUrl),
        _fact(theme, 'SHA-256', release.archiveSha256),
        const SizedBox(height: 1),
      ],
    ]),
    ..._section(theme, 'LATEST ARCHIVE', [
      _fact(theme, 'URL', package.archiveUrl),
      _fact(theme, 'SHA-256', package.archiveSha256),
      _fact(theme, 'RETRACTED', package.retracted ? 'yes' : 'no'),
    ]),
    ..._section(theme, 'SCORECARD TARGET', [
      _fact(theme, 'PACKAGE VERSION', package.scorecardPackageVersion),
      _fact(theme, 'RUNTIME VERSION', package.scorecardRuntimeVersion),
      _fact(theme, 'METRICS UPDATED', _dateTime(package.metricsUpdated)),
    ]),
  ],
);

Widget _buildDependencies(
  PubPackageSnapshot package,
  ThemeData theme,
) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    ..._section(
      theme,
      'DIRECT DEPENDENCIES',
      _dependencyFacts(theme, package.directDependencies),
    ),
    ..._section(
      theme,
      'DEV DEPENDENCIES',
      _dependencyFacts(theme, package.devDependencies),
    ),
    ..._section(
      theme,
      'DEPENDENCY OVERRIDES',
      _dependencyFacts(theme, package.dependencyOverrides),
    ),
    ..._section(theme, 'ALL ANALYZED DEPENDENCIES', [
      Text(_joined(package.transitiveDependencies) ?? 'Not provided'),
    ]),
    // Executables, workspace members, and resolution are pubspec configuration
    // rather than dependencies; Overview's PACKAGE CONFIG is their one home.
  ],
);

Widget _buildHealth(PubPackageSnapshot package, ThemeData theme) {
  final recentWeekly = recentDownloadCounts(package.weeklyDownloads);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ..._section(theme, 'PUB SCORE', [
        Row(
          spacing: 1,
          children: [
            _fact(
              theme,
              'POINTS',
              '${package.grantedPoints ?? '—'} / ${package.maxPoints ?? '—'}',
            )!,
            if (package.grantedPoints != null &&
                package.maxPoints != null &&
                package.maxPoints! > 0)
              ProgressBar(
                value: package.grantedPoints! / package.maxPoints!,
                width: 24,
              ),
          ],
        ),
        _fact(theme, 'LIKES', _number(package.likeCount)),
        _fact(theme, 'DOWNLOADS / 30D', _number(package.downloadCount30Days)),
      ]),
      ..._section(theme, 'WEEKLY DOWNLOADS', [
        Text(
          downloadSparkline(recentWeekly),
          style: TextStyle(color: theme.accent, fontWeight: FontWeight.bold),
        ),
        _fact(
          theme,
          'HISTORY',
          package.weeklyDownloads.isEmpty
              ? null
              : '${package.weeklyDownloads.length} weeks',
        ),
        _fact(theme, 'NEWEST WEEK', _date(package.weeklyDownloadsNewestDate)),
        ..._rangeFacts(theme, 'MAJOR', package.majorVersionDownloads),
        ..._rangeFacts(theme, 'MINOR', package.minorVersionDownloads),
        ..._rangeFacts(theme, 'PATCH', package.patchVersionDownloads),
      ]),
      ..._section(theme, 'ANALYSIS', [
        _fact(theme, 'PANA', package.analysisStatus),
        _fact(theme, 'DARTDOC', package.dartdocStatus),
        _fact(theme, 'TASK', package.taskStatus),
        _fact(
          theme,
          'RESULT POINTS',
          package.analysisGrantedPoints == null &&
                  package.analysisMaxPoints == null
              ? null
              : '${package.analysisGrantedPoints ?? '—'} / ${package.analysisMaxPoints ?? '—'}',
        ),
        _fact(theme, 'ANALYZED', _dateTime(package.analysisUpdated)),
        _fact(theme, 'PANA VERSION', package.panaVersion),
        _fact(theme, 'SDK', package.analyzedSdkVersion),
        _fact(theme, 'FLUTTER', package.analyzedFlutterVersion),
      ]),
      ..._section(theme, 'REPORT SECTIONS', [
        if (package.healthSections.isEmpty) const Text('Not provided'),
        for (final section in package.healthSections)
          Text(
            '${section.title} — ${section.status}  '
            '${section.grantedPoints ?? '—'}/${section.maxPoints ?? '—'}  '
            '${section.summary}',
          ),
      ]),
      ..._section(theme, 'SECURITY', [
        _fact(theme, 'UPDATED', _dateTime(package.advisoriesUpdated)),
        if (package.advisories.isEmpty) const Text('No advisories reported'),
        for (final advisory in package.advisories) ...[
          Text(
            '${advisory.id} — ${advisory.summary ?? 'No summary'}',
            style: TextStyle(color: theme.warning),
          ),
          _fact(theme, 'DETAILS', advisory.details),
          _fact(theme, 'AFFECTED', _joined(advisory.affectedVersions)),
          _fact(theme, 'URL', advisory.url),
        ],
      ]),
      ..._section(theme, 'DIAGNOSTICS', [
        _fact(theme, 'URL PROBLEMS', _joined(package.urlProblems)),
        _fact(theme, 'SCREENSHOT CHECKS', _joined(package.analysisScreenshots)),
      ]),
      ..._section(theme, 'REPOSITORY', [
        _fact(theme, 'PROVIDER', package.repositorySummary?.provider),
        _fact(theme, 'HOST', package.repositorySummary?.host),
        _fact(theme, 'REPOSITORY', package.repositorySummary?.repository),
        _fact(theme, 'BRANCH', package.repositorySummary?.branch),
        _fact(theme, 'UNLISTED', package.isUnlisted ? 'yes' : 'no'),
        _fact(theme, 'DISCONTINUED', package.isDiscontinued ? 'yes' : 'no'),
      ]),
    ],
  );
}

List<Widget> _section(ThemeData theme, String title, List<Widget?> children) {
  final items = children.whereType<Widget>().toList(growable: false);
  if (items.isEmpty) return const [];
  return [
    Text(
      title,
      style: TextStyle(color: theme.textMuted, fontWeight: FontWeight.bold),
    ),
    ...items,
    const SizedBox(height: 1),
  ];
}

Widget? _fact(ThemeData theme, String label, String? value) {
  if (value == null || value.isEmpty) return null;
  return RichText(
    text: TextSpan(
      children: [
        TextSpan(
          text: '${label.padRight(16)} ',
          style: TextStyle(color: theme.textMuted),
        ),
        TextSpan(text: value, uri: _semanticHttpUri(value)),
      ],
    ),
  );
}

Uri? _semanticHttpUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
}

List<Widget> _mapFacts(ThemeData theme, Map<String, String> values) =>
    values.isEmpty
    ? const [Text('Not provided')]
    : [
        for (final entry in values.entries)
          ?_fact(theme, entry.key.toUpperCase(), entry.value),
      ];

List<Widget> _dependencyFacts(
  ThemeData theme,
  Map<String, PackageDependencySummary> values,
) => values.isEmpty
    ? const [Text('None')]
    : [
        for (final entry in values.entries)
          ?_fact(theme, entry.key, entry.value.displayValue),
      ];

List<Widget> _rangeFacts(
  ThemeData theme,
  String label,
  List<PackageVersionDownloads> values,
) => [
  for (final value in values)
    ?_fact(
      theme,
      '$label ${value.versionRange}',
      downloadSparkline(recentDownloadCounts(value.counts)),
    ),
];

String _packageStatus(PubPackageSnapshot package) {
  if (package.isDiscontinued) return 'discontinued';
  if (package.isUnlisted) return 'unlisted';
  if (package.retracted) return 'latest release retracted';
  return 'active';
}

String _documentationLabel(PackageRelease release) {
  final status = release.documentationStatus?.trim();
  final availability = switch (release.hasDocumentation) {
    true => 'documented',
    false => 'no docs',
    null => 'docs unknown',
  };
  if (status == null || status.isEmpty) return availability;
  if (release.hasDocumentation == null) return status;
  if (status.toLowerCase() == availability) return availability;
  return '$availability ($status)';
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

String? _mapValue(Map<String, String?> values) => values.isEmpty
    ? null
    : values.entries
          .map((entry) => '${entry.key}: ${entry.value ?? entry.key}')
          .join(', ');

String? _date(DateTime? value) =>
    value?.toUtc().toIso8601String().split('T').first;

String? _dateTime(DateTime? value) {
  if (value == null) return null;
  final utc = value.toUtc();
  final date = _date(utc)!;
  if (utc.hour == 0 && utc.minute == 0 && utc.second == 0) {
    return date;
  }
  final hours = utc.hour.toString().padLeft(2, '0');
  final minutes = utc.minute.toString().padLeft(2, '0');
  return '$date $hours:$minutes UTC';
}
