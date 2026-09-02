import 'package:noir/noir.dart';

import '../shared/demo_scaffold.dart';
import 'models.dart';
import 'theme.dart';

/// The four calm, full-width package detail sections.
enum PackageDetailTab {
  /// Identity, compatibility, discovery, and links.
  overview,

  /// Published versions and documentation availability.
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
      ],
      child: Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _packageMetadata(package, theme),
            const Flexible(child: SizedBox(height: 1)),
            _installCommand(package.name, theme),
            const Flexible(child: SizedBox(height: 1)),
            _headlineMetrics(package, theme),
            const Flexible(child: SizedBox(height: 1)),
            TabSelect<PackageDetailTab>(
              key: const ValueKey<String>('tabs'),
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
              // Header gaps yield before the viewport on short terminals.
              flex: 20,
              child: Panel(
                focused: scrollFocusNode.hasFocus,
                child: ScrollBox(
                  key: const ValueKey<String>('detail'),
                  controller: scrollController,
                  focusNode: scrollFocusNode,
                  autofocus: true,
                  child: content,
                ),
              ),
            ),
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

Widget _packageMetadata(PubPackageSnapshot package, ThemeData theme) => Wrap(
  spacing: 2,
  children: [
    ?_packageBadge(package),
    Text(
      'Published ${_date(package.published)}',
      style: TextStyle(color: theme.textMuted),
    ),
    if (package.publisher case final publisher?)
      Text('by $publisher', style: TextStyle(color: theme.textMuted)),
  ],
);

Widget? _packageBadge(PubPackageSnapshot package) {
  if (package.isDiscontinued) {
    return const Badge(label: 'DISCONTINUED', variant: BadgeVariant.danger);
  }
  if (package.isUnlisted) {
    return const Badge(label: 'UNLISTED', variant: BadgeVariant.warning);
  }
  if (package.retracted) {
    return const Badge(label: 'LATEST RETRACTED', variant: BadgeVariant.danger);
  }
  return null;
}

Widget _installCommand(String packageName, ThemeData theme) => RichText(
  text: TextSpan(
    children: [
      TextSpan(
        text: '${_padCells('INSTALL', 10)} ',
        style: TextStyle(color: theme.accent, fontWeight: FontWeight.bold),
      ),
      TextSpan(
        text: r'$ ',
        style: TextStyle(color: theme.textMuted),
      ),
      TextSpan(
        text: 'dart pub add $packageName',
        style: const TextStyle(color: pubEmphasis, fontWeight: FontWeight.bold),
      ),
    ],
  ),
);

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

/// Two groups fit a 100-column frame: 44 + Wrap spacing 2 + 44.
const _summaryGroupWidth = 44;
const _summarySparklineWidth = 20;

Widget _summaryGroup(
  String title,
  List<Widget?> children, {
  String? emptyText,
}) {
  final present = children.whereType<Widget>().toList(growable: false);
  final items = [
    ...present,
    if (present.isEmpty && emptyText != null) Text(emptyText),
  ];
  return SizedBox(
    width: _summaryGroupWidth,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        ...items,
      ],
    ),
  );
}

Widget _summaryWrap(List<Widget> groups) => Wrap(
  spacing: 2,
  runSpacing: 1,
  alignment: WrapAlignment.spaceBetween,
  children: groups,
);

Widget _buildOverview(PubPackageSnapshot package, ThemeData theme) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    _summaryWrap([
      _summaryGroup('PACKAGE', [
        _fact(theme, 'PUBLISHED', _date(package.published)),
        _fact(theme, 'LATEST', package.version),
        _fact(theme, 'REPLACED BY', package.replacedBy),
      ]),
      _summaryGroup('COMPATIBILITY', [
        if (package.environment.isEmpty)
          const Text('No SDK constraints reported')
        else
          ..._mapFacts(theme, package.environment),
        _fact(
          theme,
          'PLATFORMS',
          _joined(package.platforms) ?? 'No platforms listed',
        ),
        _fact(
          theme,
          'RUNTIMES',
          _joined(package.runtimes) ?? 'No runtimes listed',
        ),
      ]),
    ]),
    const SizedBox(height: 1),
    _summaryWrap([
      _summaryGroup('DISCOVERY', [
        _fact(theme, 'TOPICS', _joined(package.topics) ?? 'No topics listed'),
        _fact(
          theme,
          'LICENSES',
          _joined(package.licenses) ?? 'No licenses listed',
        ),
      ]),
      _summaryGroup('PACKAGE CONFIG', [
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
      ], emptyText: 'No package configuration reported'),
    ]),
    const SizedBox(height: 1),
    ..._section('PROJECT LINKS', [
      _fact(theme, 'PUB.DEV', package.packageUrl),
      _fact(
        theme,
        'CHANGELOG',
        package.changelogUrl.isEmpty
            ? null
            : 'View changelog ${Icons.arrowUpRight}',
        uri: package.changelogUrl,
      ),
      _fact(theme, 'HOMEPAGE', package.homepage),
      _fact(theme, 'REPOSITORY', package.repository),
      _fact(theme, 'ISSUES', package.issueTracker),
      _fact(theme, 'DOCUMENTATION', package.documentationUrl),
      _fact(theme, 'CONTRIBUTING', package.contributingUrl),
      for (final url in package.fundingUrls) _fact(theme, 'FUNDING', url),
    ], emptyText: 'No project links provided'),
  ],
);

Widget _buildVersions(PubPackageSnapshot package, ThemeData theme) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Wrap(
      spacing: 2,
      alignment: WrapAlignment.spaceBetween,
      children: [
        const Text(
          'PUBLISHED VERSIONS',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        if (package.changelogUrl.isNotEmpty)
          RichText(
            text: TextSpan(
              text: 'View changelog ${Icons.arrowUpRight}',
              uri: _semanticHttpUri(package.changelogUrl),
            ),
          ),
      ],
    ),
    if (package.releases.isEmpty)
      const Text('No published versions reported')
    else
      for (final release in package.releases)
        _releaseRow(theme, release, latest: release.version == package.version),
    const SizedBox(height: 1),
  ],
);

Widget _releaseRow(
  ThemeData theme,
  PackageRelease release, {
  required bool latest,
}) => Wrap(
  spacing: 2,
  children: [
    SizedBox(
      width: 24,
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: latest ? '${Icons.bulletSmall} ' : '  ',
              style: TextStyle(color: latest ? theme.accent : theme.textMuted),
            ),
            TextSpan(
              text: release.version,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    ),
    SizedBox(width: 15, child: Text(_date(release.published))),
    SizedBox(
      width: 18,
      child: RichText(
        text: TextSpan(
          children: [
            if (latest)
              TextSpan(
                text: 'LATEST',
                style: TextStyle(
                  color: theme.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (latest && release.retracted) const TextSpan(text: ' '),
            if (release.retracted)
              TextSpan(
                text: 'RETRACTED',
                style: TextStyle(
                  color: theme.danger,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    ),
    Text(
      _documentationLabel(release),
      style: TextStyle(color: theme.textMuted),
    ),
  ],
);

Widget _buildDependencies(PubPackageSnapshot package, ThemeData theme) {
  final directNameWidth = _dependencyNameWidth(package.directDependencies.keys);
  final devNameWidth = _dependencyNameWidth(package.devDependencies.keys);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _summaryWrap([
        _summaryGroup(
          'DEPENDENCIES',
          _dependencyFacts(
            theme,
            package.directDependencies,
            directNameWidth,
            emptyText: 'No direct dependencies',
          ),
        ),
        _summaryGroup(
          'DEV DEPENDENCIES',
          _dependencyFacts(
            theme,
            package.devDependencies,
            devNameWidth,
            emptyText: 'No development dependencies',
          ),
        ),
      ]),
      if (package.dependencyOverrides.isNotEmpty) ...[
        const SizedBox(height: 1),
        ..._section(
          'OVERRIDES',
          _dependencyFacts(
            theme,
            package.dependencyOverrides,
            _dependencyNameWidth(package.dependencyOverrides.keys),
            emptyText: 'No overrides',
          ),
        ),
      ],
      const SizedBox(height: 1),
      ..._section('ALL ANALYZED', [
        if (package.transitiveDependencies.isEmpty)
          const Text('No analyzed dependencies')
        else
          Wrap(
            spacing: 2,
            children: [
              for (final name in package.transitiveDependencies) Text(name),
            ],
          ),
      ]),
    ],
  );
}

Widget _buildHealth(PubPackageSnapshot package, ThemeData theme) {
  final recentWeekly = recentDownloadCounts(package.weeklyDownloads);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _summaryWrap([
        _summaryGroup('QUALITY', [
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
                  width: 16,
                ),
            ],
          ),
          _fact(theme, 'PANA', package.analysisStatus),
          _fact(theme, 'DARTDOC', package.dartdocStatus),
          _fact(theme, 'TASK', package.taskStatus),
        ]),
        _summaryGroup('DOWNLOAD TREND', [
          if (recentWeekly.isEmpty)
            const Text('No download history reported')
          else
            Text(
              downloadSparkline(recentWeekly),
              style: TextStyle(
                color: theme.accent,
                fontWeight: FontWeight.bold,
              ),
            ),
          _fact(
            theme,
            'HISTORY',
            package.weeklyDownloads.isEmpty
                ? null
                : '${package.weeklyDownloads.length} weeks',
          ),
          _fact(theme, 'NEWEST WEEK', _date(package.weeklyDownloadsNewestDate)),
          ..._rangeFacts(theme, 'MAJOR', package.majorVersionDownloads.take(1)),
        ]),
      ]),
      const SizedBox(height: 1),
      ..._section('REPORT SECTIONS', [
        if (package.healthSections.isEmpty)
          const Text('No analyzer reports available'),
        for (final (index, section) in package.healthSections.indexed) ...[
          _reportSectionHeader(theme, section),
          if (section.summary.trim().isNotEmpty) ...[
            const SizedBox(height: 1),
            _healthMarkdown(theme, section.summary),
          ],
          if (index < package.healthSections.length - 1)
            const SizedBox(height: 1),
        ],
      ]),
      ..._section('SECURITY', [
        _fact(theme, 'UPDATED', _dateTime(package.advisoriesUpdated)),
        if (package.advisories.isEmpty) const Text('No advisories reported'),
        for (final (index, advisory) in package.advisories.indexed) ...[
          Text(
            '${advisory.id} — ${advisory.summary ?? 'No summary'}',
            style: TextStyle(color: theme.warning),
          ),
          if (advisory.details != null &&
              advisory.details!.trim().isNotEmpty) ...[
            const SizedBox(height: 1),
            _healthMarkdown(theme, advisory.details!),
          ],
          if (advisory.affectedVersions.isNotEmpty) const SizedBox(height: 1),
          _affectedVersions(theme, advisory.affectedVersions),
          _fact(theme, 'URL', advisory.url),
          if (index < package.advisories.length - 1) const SizedBox(height: 1),
        ],
      ]),
      ..._section('TECHNICAL ANALYSIS', [
        _fact(theme, 'ANALYZED', _dateTime(package.analysisUpdated)),
        _fact(theme, 'PANA VERSION', package.panaVersion),
        _fact(theme, 'SDK', package.analyzedSdkVersion),
        _fact(theme, 'FLUTTER', package.analyzedFlutterVersion),
        _fact(theme, 'SCORECARD TARGET', package.scorecardPackageVersion),
        _fact(theme, 'SCORECARD RUNTIME', package.scorecardRuntimeVersion),
        _fact(theme, 'METRICS UPDATED', _dateTime(package.metricsUpdated)),
        _fact(
          theme,
          'RESULT POINTS',
          package.analysisGrantedPoints == null &&
                  package.analysisMaxPoints == null
              ? null
              : '${package.analysisGrantedPoints ?? '—'} / ${package.analysisMaxPoints ?? '—'}',
        ),
      ]),
      ..._section('DIAGNOSTICS', [
        _fact(theme, 'URL PROBLEMS', _joined(package.urlProblems)),
        _fact(theme, 'SCREENSHOT CHECKS', _joined(package.analysisScreenshots)),
      ]),
      ..._section('REPOSITORY', [
        _fact(theme, 'PROVIDER', package.repositorySummary?.provider),
        _fact(theme, 'HOST', package.repositorySummary?.host),
        _fact(theme, 'REPOSITORY', package.repositorySummary?.repository),
        _fact(theme, 'BRANCH', package.repositorySummary?.branch),
      ], trailingSpace: false),
    ],
  );
}

Widget _reportSectionHeader(ThemeData theme, PackageHealthSection section) {
  final points = '${section.grantedPoints ?? '—'}/${section.maxPoints ?? '—'}';
  return RichText(
    text: TextSpan(
      children: [
        TextSpan(
          text: section.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        TextSpan(
          text: '  ${section.status}  $points',
          style: TextStyle(color: theme.textMuted),
        ),
      ],
    ),
  );
}

/// Pana check titles are `h3`; paint them in accent so they read as scores,
/// not as another chrome line under the section header.
Widget _healthMarkdown(ThemeData theme, String markdown) {
  final base = MarkdownThemeData.fromTheme(theme);
  return MarkdownView(
    markdown: markdown,
    embedded: true,
    theme: base.copyWith(
      heading3: TextStyle(color: theme.accent, attributes: Attr.bold),
    ),
  );
}

Widget? _affectedVersions(ThemeData theme, List<String> versions) {
  if (versions.isEmpty) return null;
  if (versions.length <= 6) {
    return _fact(theme, 'AFFECTED', _joined(versions));
  }
  return _fact(theme, 'AFFECTED', '${versions.length} versions');
}

List<Widget> _section(
  String title,
  List<Widget?> children, {
  String? emptyText,
  bool trailingSpace = true,
}) {
  final items = children.whereType<Widget>().toList(growable: false);
  if (items.isNotEmpty) {
    return [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ...items,
      if (trailingSpace) const SizedBox(height: 1),
    ];
  }
  if (emptyText == null) return const [];
  return [
    Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    Text(emptyText),
    if (trailingSpace) const SizedBox(height: 1),
  ];
}

Widget? _fact(
  ThemeData theme,
  String label,
  String? value, {
  String? uri,
  int labelWidth = 16,
  TextStyle? valueStyle,
}) {
  if (value == null || value.isEmpty) return null;
  return RichText(
    text: TextSpan(
      children: [
        TextSpan(
          text: '${_padCells(label, labelWidth)} ',
          style: TextStyle(color: theme.textMuted),
        ),
        TextSpan(
          text: value,
          style: valueStyle,
          uri: _semanticHttpUri(uri ?? value),
        ),
      ],
    ),
  );
}

Uri? _semanticHttpUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
}

List<Widget> _mapFacts(ThemeData theme, Map<String, String> values) => [
  for (final entry in values.entries)
    ?_fact(theme, entry.key.toUpperCase(), entry.value),
];

List<Widget> _dependencyFacts(
  ThemeData theme,
  Map<String, PackageDependencySummary> values,
  int nameWidth, {
  required String emptyText,
}) {
  if (values.isEmpty) return [Text(emptyText)];
  return [
    for (final entry in values.entries)
      ..._dependencyRows(theme, entry.key, entry.value, nameWidth),
  ];
}

List<Widget> _dependencyRows(
  ThemeData theme,
  String name,
  PackageDependencySummary dependency,
  int nameWidth,
) {
  final (value, details) = switch (dependency.source) {
    PackageDependencySource.git => (
      'git',
      [
        ?dependency.url,
        if (dependency.ref case final ref?) 'ref $ref',
        if (dependency.path case final path?) 'path $path',
      ],
    ),
    PackageDependencySource.path => ('path', [?dependency.path]),
    _ => (dependency.displayValue, const <String>[]),
  };
  return [
    RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: _padCells(name, nameWidth),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text: '  $value',
            style: TextStyle(color: theme.textMuted),
          ),
        ],
      ),
    ),
    for (final detail in details)
      Text(
        '  ${Icons.arrowBranchDown} $detail',
        style: TextStyle(color: theme.textMuted),
      ),
  ];
}

int _dependencyNameWidth(Iterable<String> names) {
  var width = 8;
  for (final name in names) {
    final cells = terminalStringWidth(name);
    if (cells > width) width = cells;
  }
  return width > 32 ? 32 : width;
}

String _padCells(String text, int width) {
  final cells = terminalStringWidth(text);
  if (cells >= width) return text;
  return '$text${' ' * (width - cells)}';
}

List<Widget> _rangeFacts(
  ThemeData theme,
  String label,
  Iterable<PackageVersionDownloads> values,
) => [
  for (final value in values)
    ?_fact(
      theme,
      '$label ${value.versionRange}',
      downloadSparkline(
        recentDownloadCounts(value.counts, limit: _summarySparklineWidth),
      ),
    ),
];

String _documentationLabel(PackageRelease release) {
  final (label, canonical) = switch (release.hasDocumentation) {
    true => ('docs ready', 'documented'),
    false => ('no docs', 'no docs'),
    null => ('docs unknown', 'unknown'),
  };
  final status = release.documentationStatus?.trim();
  if (status == null || status.isEmpty) return label;
  final normalized = status.toLowerCase().replaceAll('-', ' ');
  if (normalized == canonical || normalized == 'completed') return label;
  return '$label ($status)';
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

const _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String? _date(DateTime? value) {
  if (value == null) return null;
  final utc = value.toUtc();
  return '${_months[utc.month - 1]} ${utc.day}, ${utc.year}';
}

String? _dateTime(DateTime? value) {
  if (value == null) return null;
  final utc = value.toUtc();
  final date = _date(utc)!;
  if (utc.hour == 0 && utc.minute == 0 && utc.second == 0) {
    return date;
  }
  final hours = utc.hour.toString().padLeft(2, '0');
  final minutes = utc.minute.toString().padLeft(2, '0');
  return '$date · $hours:$minutes UTC';
}
