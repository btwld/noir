# Quiet Tabs Pub Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose the missing weekly-download metrics in `pub_api_client`, open an upstream pull request, and validate that branch through a polished, testable Quiet Tabs pub.dev search example built with Noir.

**Architecture:** The upstream client gains backwards-compatible typed models for the existing `weeklyVersionDownloads` JSON object. Noir consumes that PR branch only as a dev dependency; an application-owned catalog adapter translates pub client responses into immutable example models, while a stateful shell renders separate search and tabbed-detail views and accepts a fake catalog in tests.

**Tech Stack:** Dart 3.10+, `pub_api_client`, `dart_mappable`, Noir widgets, `package:test`, Noir's `createTuiTestApp` and golden helpers, Git/GitHub CLI.

## Global Constraints

- Work on the upstream clone at `.context/pub_api_client`; its default branch is `main` and the feature branch is `feat/weekly-version-downloads`.
- Open a pull request against `leoafarias/pub_api_client:main`; do not publish or version-bump either package.
- Noir depends on the upstream feature branch as a root git **dev dependency**; Noir's runtime dependencies remain unchanged. This library ignores `pubspec.lock`, so the local resolver lock proves the exact resolved commit without becoming a tracked artifact.
- Search and detail reads are public and side-effect-free. Do not add authentication, like/unlike calls, or another raw HTTP client.
- Noir widgets do not call FFI. All app-created catalogs, controllers, focus nodes, and scroll controllers are disposed deterministically.
- Async UI completions check `mounted` and a request generation before `setState`.
- Use only the four repository test harnesses already named in `AGENTS.md`; visual goldens retain buffer, style, and cursor sidecars.
- Do not run real-terminal, PTY, raw-mode, signal, crash, native-build, publication, release, tag, or manual-workflow operations.
- Noir implementation commits wait for the repository's independent behavior/diff review gate; upstream commits follow the upstream repository's own clean test gate.

---

### Task 1: Expose weekly download metrics in `pub_api_client`

**Files:**
- Create: `.context/pub_api_client/test/package_score_card_test.dart`
- Modify: `.context/pub_api_client/test/pubdev_api_test.dart`
- Modify: `.context/pub_api_client/lib/src/models/package_score_card.dart`
- Regenerate: `.context/pub_api_client/lib/src/models/package_score_card.mapper.dart`
- Modify: `.context/pub_api_client/README.md`

**Interfaces:**
- Consumes: raw `scorecard.weeklyVersionDownloads` with `totalWeeklyDownloads`, `majorRangeWeeklyDownloads`, `minorRangeWeeklyDownloads`, `patchRangeWeeklyDownloads`, and `newestDate`.
- Produces: `PackageScoreCard.weeklyVersionDownloads`, `WeeklyVersionDownloads`, and `VersionRangeWeeklyDownloads` from `package:pub_api_client/pub_api_client.dart`.

- [x] **Step 1: Create the upstream feature branch**

Run from `.context/pub_api_client`:

```bash
git switch -c feat/weekly-version-downloads
```

Expected: the worktree reports branch `feat/weekly-version-downloads` based on `origin/main` at `986d53e` or its fetched successor.

Before editing, repeat the live shape audit:

```bash
curl -sS --fail https://pub.dev/api/packages/pub_api_client/metrics |
  jq '{scorecard: (.scorecard | keys), weekly: (.scorecard.weeklyVersionDownloads | keys), pana: (.scorecard.panaReport | keys)}'
```

Expected: every `scorecard` and `panaReport` key already has a typed model except `weeklyVersionDownloads`; its nested keys are exactly the five consumed by this task. If the live shape has changed, extend the deterministic payload and models for every additional confirmed field before proceeding.

- [x] **Step 2: Write the focused failing decode test**

Create `test/package_score_card_test.dart` with a real mapper round-trip. The first assertion uses the existing public `toMap()` surface, so RED is an assertion failure rather than an undefined-symbol compile error:

```dart
import 'package:pub_api_client/pub_api_client.dart';
import 'package:test/test.dart';

void main() {
  group('weekly version downloads', () {
    test('decodes every weekly download series from package metrics', () {
      final metrics = PackageMetrics.fromMap(_metricsPayload());
      final mapped = metrics.scorecard.toMap();

      expect(
        mapped['weeklyVersionDownloads'],
        {
          'totalWeeklyDownloads': [10, 20, 30],
          'majorRangeWeeklyDownloads': [
            {
              'counts': [8, 18, 28],
              'versionRange': '>=3.0.0-0 <4.0.0',
            },
          ],
          'minorRangeWeeklyDownloads': [
            {
              'counts': [7, 17, 27],
              'versionRange': '>=3.2.0-0 <3.3.0',
            },
          ],
          'patchRangeWeeklyDownloads': [
            {
              'counts': [6, 16, 26],
              'versionRange': '>=3.2.0-0 <3.2.1',
            },
          ],
          'newestDate': '2026-08-15T00:00:00.000Z',
        },
      );
    });
  });
}

Map<String, dynamic> _metricsPayload() => {
  'score': {
    'grantedPoints': 160,
    'maxPoints': 160,
    'likeCount': 69,
    'popularityScore': null,
    'downloadCount30Days': 156812,
    'tags': <String>[],
  },
  'scorecard': {
    'packageName': 'pub_api_client',
    'packageVersion': '3.2.0',
    'runtimeVersion': '2026.08.12',
    'updated': '2026-08-13T20:56:41.306172Z',
    'dartdocReport': null,
    'panaReport': null,
    'taskStatus': 'completed',
    'weeklyVersionDownloads': {
      'totalWeeklyDownloads': [10, 20, 30],
      'majorRangeWeeklyDownloads': [
        {
          'counts': [8, 18, 28],
          'versionRange': '>=3.0.0-0 <4.0.0',
        },
      ],
      'minorRangeWeeklyDownloads': [
        {
          'counts': [7, 17, 27],
          'versionRange': '>=3.2.0-0 <3.3.0',
        },
      ],
      'patchRangeWeeklyDownloads': [
        {
          'counts': [6, 16, 26],
          'versionRange': '>=3.2.0-0 <3.2.1',
        },
      ],
      'newestDate': '2026-08-15T00:00:00.000Z',
    },
  },
};
```

- [x] **Step 3: Run the test and verify RED**

Run:

```bash
dart test test/package_score_card_test.dart
```

Expected: FAIL because `PackageScoreCard.toMap()` drops `weeklyVersionDownloads`.

- [x] **Step 4: Add the backwards-compatible typed models**

Add this field to `PackageScoreCard`; keep it optional because older and third-party pub servers may omit it:

```dart
final WeeklyVersionDownloads? weeklyVersionDownloads;
```

Add `this.weeklyVersionDownloads` to the constructor, then add these public models in `package_score_card.dart`:

```dart
@MappableClass()
class WeeklyVersionDownloads with WeeklyVersionDownloadsMappable {
  final List<int> totalWeeklyDownloads;
  final List<VersionRangeWeeklyDownloads> majorRangeWeeklyDownloads;
  final List<VersionRangeWeeklyDownloads> minorRangeWeeklyDownloads;
  final List<VersionRangeWeeklyDownloads> patchRangeWeeklyDownloads;
  final DateTime? newestDate;

  const WeeklyVersionDownloads({
    this.totalWeeklyDownloads = const [],
    this.majorRangeWeeklyDownloads = const [],
    this.minorRangeWeeklyDownloads = const [],
    this.patchRangeWeeklyDownloads = const [],
    this.newestDate,
  });

  static const fromMap = WeeklyVersionDownloadsMapper.fromMap;
  static const fromJson = WeeklyVersionDownloadsMapper.fromJson;
}

@MappableClass()
class VersionRangeWeeklyDownloads with VersionRangeWeeklyDownloadsMappable {
  final List<int> counts;
  final String versionRange;

  const VersionRangeWeeklyDownloads({
    this.counts = const [],
    required this.versionRange,
  });

  static const fromMap = VersionRangeWeeklyDownloadsMapper.fromMap;
  static const fromJson = VersionRangeWeeklyDownloadsMapper.fromJson;
}
```

- [x] **Step 5: Regenerate mappers**

Run:

```bash
dart pub get
dart run build_runner build --delete-conflicting-outputs
```

Expected: `package_score_card.mapper.dart` contains mappers and copy-with types for both new classes and maps the optional scorecard field.

- [x] **Step 6: Strengthen the now-green test around the typed API and compatibility**

Replace the generic `mapped` assertion setup with typed assertions while retaining the round-trip assertion, and add the absent-field case:

```dart
final weekly = metrics.scorecard.weeklyVersionDownloads!;
expect(weekly.totalWeeklyDownloads, [10, 20, 30]);
expect(
  weekly.majorRangeWeeklyDownloads.single.versionRange,
  '>=3.0.0-0 <4.0.0',
);
expect(weekly.minorRangeWeeklyDownloads.single.counts, [7, 17, 27]);
expect(weekly.patchRangeWeeklyDownloads.single.counts, [6, 16, 26]);
expect(weekly.newestDate, DateTime.utc(2026, 8, 15));
expect(metrics.scorecard.toMap(), contains('weeklyVersionDownloads'));

final legacy = _metricsPayload();
(legacy['scorecard'] as Map<String, dynamic>)
    .remove('weeklyVersionDownloads');
expect(
  PackageMetrics.fromMap(legacy).scorecard.weeklyVersionDownloads,
  isNull,
);
```

In the existing `Get package metrics` integration test, add:

```dart
final weekly = metrics.scorecard.weeklyVersionDownloads;
expect(weekly, isNotNull);
expect(weekly!.totalWeeklyDownloads, isNotEmpty);
expect(weekly.newestDate, isNotNull);
```

Apply the same assertions to `metrics2` when it is non-null. This validates the model against current pub.dev while the new focused test remains the deterministic regression guard.

- [x] **Step 7: Run focused tests and verify GREEN**

Run:

```bash
dart test test/package_score_card_test.dart
```

Expected: PASS with both typed decode and compatibility coverage.

- [x] **Step 8: Document the public metric**

Expand README's “Get Package Metrics” example with:

```dart
final metrics = await client.packageMetrics('pkg_name');
final weekly = metrics?.scorecard.weeklyVersionDownloads;
if (weekly != null && weekly.totalWeeklyDownloads.isNotEmpty) {
  print('Latest weekly downloads: ${weekly.totalWeeklyDownloads.last}');
}
```

State that totals and major/minor/patch version-range histories are present when supplied by the server.

- [x] **Step 9: Verify the complete upstream change**

Run:

```bash
dart format --output=none --set-exit-if-changed lib/ test/
dart analyze
dart test
git diff --check
```

Expected: formatting and analysis succeed; the focused unit test and existing upstream suite pass; the diff contains only the model, generated mapper, focused/integration tests, and README.

- [x] **Step 10: Commit the upstream slice**

```bash
git add lib/src/models/package_score_card.dart lib/src/models/package_score_card.mapper.dart test/package_score_card_test.dart test/pubdev_api_test.dart README.md
git commit -m "feat: expose weekly version download metrics"
```

Expected: one coherent commit on `feat/weekly-version-downloads`.

---

### Task 2: Push and open the upstream pull request

**Files:**
- No new source files; this task publishes the verified Task 1 commit only.

**Interfaces:**
- Consumes: committed branch `feat/weekly-version-downloads`.
- Produces: a GitHub PR URL and a remote branch that Noir can name in `pubspec.yaml`.

- [x] **Step 1: Recheck the exact outgoing diff**

Run from `.context/pub_api_client`:

```bash
git status --short
git diff --check origin/main...HEAD
git log --oneline origin/main..HEAD
```

Expected: clean status, no whitespace errors, exactly one feature commit.

- [x] **Step 2: Push the feature branch**

```bash
git push -u origin feat/weekly-version-downloads
```

Expected: GitHub creates or updates `leoafarias/pub_api_client:feat/weekly-version-downloads`.

- [x] **Step 3: Open the pull request**

Create the PR against `main` with title `feat: expose weekly version download metrics`. The body must contain:

```markdown
## Summary
- model pub.dev's `weeklyVersionDownloads` scorecard payload
- expose total and major/minor/patch version-range histories
- keep the field optional for older or third-party pub servers
- document the new typed surface

## Validation
- `dart format --output=none --set-exit-if-changed lib/ test/`
- `dart analyze`
- `dart test`
```

Run `gh pr create --base main --head feat/weekly-version-downloads` with that title/body, then record the returned URL.

- [x] **Step 4: Confirm remote PR state**

```bash
gh pr view --json number,url,state,headRefName,baseRefName,statusCheckRollup
```

Expected: OPEN PR, head `feat/weekly-version-downloads`, base `main`; do not rerun or manually dispatch workflows.

---

### Task 3: Pin Noir to the PR branch and build the catalog layer

**Files:**
- Modify: `pubspec.yaml`
- Create: `example/pub_search/models.dart`
- Create: `example/pub_search/catalog.dart`
- Create: `test/example/pub_search_catalog_test.dart`

**Interfaces:**
- Consumes: `PackageMetrics.scorecard.weeklyVersionDownloads` from Task 1.
- Produces: `PackageSort`, `PackageSearchPage`, `PackageRelease`, `PackageAdvisorySummary`, `PackageHealthSection`, `PubPackageSnapshot`, `PubCatalog`, and `PubApiCatalog`.

- [x] **Step 1: Add the upstream branch as a dev dependency**

Add under `dev_dependencies` in `pubspec.yaml`:

```yaml
  pub_api_client:
    git:
      url: https://github.com/leoafarias/pub_api_client.git
      ref: feat/weekly-version-downloads
```

Run:

```bash
dart pub get
```

Expected: the ignored local `pubspec.lock` records source `git`, the GitHub URL, branch ref, and the exact upstream commit SHA; existing runtime dependencies are unchanged.

- [x] **Step 2: Write the failing catalog mapping tests**

Create `test/example/pub_search_catalog_test.dart`. Build public upstream response objects with `PubPackage.fromMap`, `PackageMetrics.fromMap`, `PackagePublisher.fromMap`, `PackageOptions.fromMap`, `PackageDocumentation.fromMap`, and `PackageAdvisories.fromMap`, then call the wished-for mapper:

```dart
final snapshot = PubPackageSnapshot.fromApi(
  package: PubPackage.fromMap(packagePayload),
  score: PackageScore.fromMap(metricsPayload['score'] as Map<String, dynamic>),
  metrics: PackageMetrics.fromMap(metricsPayload),
  publisher: PackagePublisher.fromMap({'publisherId': 'leoafarias.com'}),
  options: PackageOptions.fromMap({
    'isDiscontinued': false,
    'isUnlisted': false,
    'replacedBy': null,
  }),
  documentation: PackageDocumentation.fromMap(documentationPayload),
  advisories: PackageAdvisories.fromMap({
    'advisories': <Object?>[],
    'advisoriesUpdated': '2026-08-17T00:00:00.000Z',
  }),
);

expect(snapshot.name, 'noir');
expect(snapshot.version, '0.0.1-alpha.1');
expect(snapshot.publisher, 'leoafarias.com');
expect(snapshot.topics, ['tui', 'terminal']);
expect(snapshot.platforms, ['linux', 'macos', 'windows']);
expect(snapshot.directDependencies['ffi'], '^2.1.0');
expect(snapshot.releases.single.hasDocumentation, isTrue);
expect(snapshot.weeklyDownloads, [4, 9, 16]);
expect(snapshot.analysisStatus, 'success');
```

Add separate tests for absent metrics/publisher/topics and for the pure sparkline helper:

```dart
expect(downloadSparkline([0, 10, 20]), '▁▅█');
expect(downloadSparkline(const []), 'Not available');
```

- [x] **Step 3: Run the focused test and establish RED**

Run:

```bash
dart test test/example/pub_search_catalog_test.dart --concurrency=1
```

Expected first: compile failure because the example model/catalog files do not exist. Add only the declared class/function signatures with `UnimplementedError`, rerun, and establish the intended assertion failure from the unimplemented mapping.

- [x] **Step 4: Implement immutable application models**

The following block records the initial TDD signature sketch, not the final
reviewed API. Independent review required canonical constructors to copy every
collection, dependency maps to use `PackageDependencySummary`, diagnostics to
use explicit field allowlists, and release summaries to retain per-version
archive metadata. See `example/pub_search/models.dart` for the canonical API.

```dart
enum PackageSort { top, text, created, updated, popularity, downloads, likes, points }

final class PackageSearchPage {
  const PackageSearchPage({
    required this.query,
    required this.page,
    required this.sort,
    required this.packages,
    required this.hasNextPage,
  });
  final String query;
  final int page;
  final PackageSort sort;
  final List<String> packages;
  final bool hasNextPage;
}

final class PackageRelease {
  const PackageRelease({
    required this.version,
    required this.published,
    required this.retracted,
    required this.hasDocumentation,
  });
  final String version;
  final DateTime published;
  final bool retracted;
  final bool? hasDocumentation;
}

final class PackageAdvisorySummary {
  const PackageAdvisorySummary({required this.id, this.summary, this.url});
  final String id;
  final String? summary;
  final String? url;
}

final class PackageHealthSection {
  const PackageHealthSection({
    required this.title,
    required this.status,
    required this.summary,
  });
  final String title;
  final String status;
  final String summary;
}

final class PubPackageSnapshot {
  const PubPackageSnapshot({
    required this.name,
    required this.version,
    required this.description,
    required this.published,
    required this.publisher,
    required this.sdkConstraint,
    required this.homepage,
    required this.repository,
    required this.issueTracker,
    required this.topics,
    required this.platforms,
    required this.runtimes,
    required this.licenses,
    required this.grantedPoints,
    required this.maxPoints,
    required this.likeCount,
    required this.downloadCount30Days,
    required this.directDependencies,
    required this.devDependencies,
    required this.transitiveDependencies,
    required this.releases,
    required this.isDiscontinued,
    required this.replacedBy,
    required this.isUnlisted,
    required this.advisories,
    required this.analysisStatus,
    required this.dartdocStatus,
    required this.healthSections,
    required this.urlProblems,
    required this.archiveUrl,
    required this.archiveSha256,
    required this.metricsUpdated,
    required this.weeklyDownloads,
  });

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
    final pana = metrics?.scorecard.panaReport;
    final docsByVersion = {
      for (final item in documentation?.versions ??
          const <PackageDocumentationVersion>[])
        item.version: item.hasDocumentation,
    };
    final metricLicenses = pana?.licenses
            ?.map((license) => license.spdxIdentifier)
            .whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    final licenses = metricLicenses.isNotEmpty
        ? metricLicenses
        : _tagValues(tags, 'license:');

    return PubPackageSnapshot(
      name: package.name,
      version: package.version,
      description: package.description,
      published: package.latest.published,
      publisher: publisher?.publisherId,
      sdkConstraint: pubspec.environment?['sdk']?.toString(),
      homepage: pubspec.homepage,
      repository: pubspec.repository?.toString(),
      issueTracker: pubspec.issueTracker?.toString(),
      topics: List.unmodifiable(pubspec.topics ?? const <String>[]),
      platforms: List.unmodifiable(_tagValues(tags, 'platform:')),
      runtimes: List.unmodifiable(_tagValues(tags, 'runtime:')),
      licenses: List.unmodifiable(licenses),
      grantedPoints: effectiveScore?.grantedPoints,
      maxPoints: effectiveScore?.maxPoints,
      likeCount: effectiveScore?.likeCount,
      downloadCount30Days: effectiveScore?.downloadCount30Days,
      directDependencies: Map.unmodifiable(
        pubspec.dependencies.map(
          (name, dependency) => MapEntry(name, _dependencyValue(dependency)),
        ),
      ),
      devDependencies: Map.unmodifiable(
        pubspec.devDependencies.map(
          (name, dependency) => MapEntry(name, _dependencyValue(dependency)),
        ),
      ),
      transitiveDependencies: List.unmodifiable(
        pana?.allDependencies ?? const <String>[],
      ),
      releases: List.unmodifiable(
        package.versions.map(
          (release) => PackageRelease(
            version: release.version,
            published: release.published,
            retracted: release.retracted,
            hasDocumentation: docsByVersion[release.version],
          ),
        ),
      ),
      isDiscontinued:
          options?.isDiscontinued ?? package.isDiscontinued ?? false,
      replacedBy: options?.replacedBy ?? package.replacedBy,
      isUnlisted: options?.isUnlisted ?? false,
      advisories: List.unmodifiable(
        (advisories?.advisories ?? const <SecurityAdvisory>[]).map(
          (item) => PackageAdvisorySummary(
            id: item.id,
            summary: item.summary,
            url: item.pubDisplayUrl,
          ),
        ),
      ),
      analysisStatus: pana?.reportStatus,
      dartdocStatus: metrics?.scorecard.dartdocReport?.reportStatus,
      healthSections: List.unmodifiable(
        (pana?.report?.sections ?? const <Section>[]).map(
          (section) => PackageHealthSection(
            title: section.title ?? section.id ?? 'Check',
            status: section.status ?? 'unknown',
            summary: section.summary ?? '',
          ),
        ),
      ),
      urlProblems: List.unmodifiable(
        (pana?.urlProblems ?? const <Object>[]).map(_describeValue),
      ),
      archiveUrl: package.latest.archiveUrl,
      archiveSha256: package.latest.archiveSha256,
      metricsUpdated: metrics?.scorecard.updated,
      weeklyDownloads: List.unmodifiable(
        metrics?.scorecard.weeklyVersionDownloads?.totalWeeklyDownloads ??
            const <int>[],
      ),
    );
  }

  final String name;
  final String version;
  final String description;
  final DateTime published;
  final String? publisher;
  final String? sdkConstraint;
  final String? homepage;
  final String? repository;
  final String? issueTracker;
  final List<String> topics;
  final List<String> platforms;
  final List<String> runtimes;
  final List<String> licenses;
  final int? grantedPoints;
  final int? maxPoints;
  final int? likeCount;
  final int? downloadCount30Days;
  final Map<String, String> directDependencies;
  final Map<String, String> devDependencies;
  final List<String> transitiveDependencies;
  final List<PackageRelease> releases;
  final bool isDiscontinued;
  final String? replacedBy;
  final bool isUnlisted;
  final List<PackageAdvisorySummary> advisories;
  final String? analysisStatus;
  final String? dartdocStatus;
  final List<PackageHealthSection> healthSections;
  final List<String> urlProblems;
  final String archiveUrl;
  final String archiveSha256;
  final DateTime? metricsUpdated;
  final List<int> weeklyDownloads;
}

String downloadSparkline(List<int> values) {
  if (values.isEmpty) return 'Not available';
  const levels = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];
  final maxValue = values.reduce((a, b) => a > b ? a : b);
  if (maxValue == 0) return List.filled(values.length, '▁').join();
  return values
      .map((value) => levels[((value / maxValue) * 7).round()])
      .join();
}

List<String> _tagValues(List<String> tags, String prefix) => tags
    .where((tag) => tag.startsWith(prefix))
    .map((tag) => tag.substring(prefix.length))
    .toList(growable: false);

String _dependencyValue(Object dependency) {
  final value = '$dependency';
  final separator = value.indexOf(': ');
  return separator < 0 ? value : value.substring(separator + 2);
}
```

Import `package:pub_api_client/pub_api_client.dart` only in this data layer. Derive platform/runtime/license values from score tags, use the dependency variants re-exported by `pub_api_client` to preserve source metadata without importing `package:pubspec_parse` directly, summarize dynamic diagnostics through field-specific allowlists, and copy every mutable API list/map before exposing it.

- [x] **Step 5: Implement the catalog interface and live adapter**

Create `example/pub_search/catalog.dart`:

```dart
abstract interface class PubCatalog {
  Future<PackageSearchPage> search(
    String query, {
    int page = 1,
    PackageSort sort = PackageSort.top,
  });

  Future<PubPackageSnapshot> loadPackage(String name);
  void close();
}

final class PubApiCatalog implements PubCatalog {
  PubApiCatalog({PubClient? client})
      : _client = client ?? PubClient(userAgent: 'noir-pub-example');

  final PubClient _client;

  @override
  Future<PackageSearchPage> search(
    String query, {
    int page = 1,
    PackageSort sort = PackageSort.top,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Enter a package name or search expression.');
    }
    final result = await _client.search(
      normalized,
      page: page,
      sort: _toSearchOrder(sort),
    );
    return PackageSearchPage(
      query: normalized,
      page: page,
      sort: sort,
      packages: List.unmodifiable(result.packages.map((item) => item.package)),
      hasNextPage: result.next != null,
    );
  }

  @override
  Future<PubPackageSnapshot> loadPackage(String name) async {
    final packageFuture = _client.packageInfo(name);
    final metricsFuture = _optional(_client.packageMetrics(name));
    final publisherFuture = _optional(_client.packagePublisher(name));
    final optionsFuture = _optional(_client.packageOptions(name));
    final documentationFuture = _optional(_client.documentation(name));
    final advisoriesFuture = _optional(_client.packageAdvisories(name));

    final package = await packageFuture;
    final metrics = await metricsFuture;
    final score = metrics?.score ??
        await _optional(_client.packageScore(name));
    return PubPackageSnapshot.fromApi(
      package: package,
      score: score,
      metrics: metrics,
      publisher: await publisherFuture,
      options: await optionsFuture,
      documentation: await documentationFuture,
      advisories: await advisoriesFuture,
    );
  }

  @override
  void close() => _client.close();

  Future<T?> _optional<T>(Future<T> request) async {
    try {
      return await request;
    } on PubClientException {
      return null;
    }
  }

  SearchOrder _toSearchOrder(PackageSort sort) => switch (sort) {
    PackageSort.top => SearchOrder.top,
    PackageSort.text => SearchOrder.text,
    PackageSort.created => SearchOrder.created,
    PackageSort.updated => SearchOrder.updated,
    PackageSort.popularity => SearchOrder.popularity,
    PackageSort.downloads => SearchOrder.downloads,
    PackageSort.likes => SearchOrder.like,
    PackageSort.points => SearchOrder.points,
  };
}
```

Keep `packageInfo` outside `_optional` so a missing selected package remains a visible detail-load error. Optional endpoint failures render their honest absent states without discarding the mandatory package record.

- [x] **Step 6: Run catalog tests and refactor GREEN**

Run:

```bash
dart test test/example/pub_search_catalog_test.dart --concurrency=1
dart analyze --fatal-infos
```

Expected: mapping, optional-field, branch-model, and sparkline tests pass; strict analysis reports no transitive-import or mutability issue.

---

### Task 4: Build the search shell with deterministic async behavior

**Files:**
- Create: `example/pub_search/app.dart`
- Create: `example/pub_search.dart`
- Create: `test/example/pub_search_test.dart`

**Interfaces:**
- Consumes: `PubCatalog`, `PackageSearchPage`, and `PubPackageSnapshot` from Task 3.
- Produces: `PubSearchApp`, the runnable entrypoint, search/result navigation, stale-response suppression, retry, paging, and deterministic catalog ownership.

- [x] **Step 1: Write fake-backed failing interaction tests**

Create a `FakePubCatalog` in `test/example/pub_search_test.dart` that records search/detail calls, exposes queued `Completer` results, and records `close()`. Write parser-backed tests using `createTuiTestApp` for:

```dart
test('runs the initial noir search and opens the confirmed result', () async {
  final catalog = FakePubCatalog()
    ..searchResults.add(
      Future.value(
        PackageSearchPage(
          query: 'noir',
          page: 1,
          sort: PackageSort.top,
          packages: ['noir', 'noir_router'],
          hasNextPage: false,
        ),
      ),
    )
    ..detailResults['noir'] = Future.value(exampleSnapshot);
  final app = createTuiTestApp(
    PubSearchApp(catalog: catalog, onQuit: () {}),
    width: 100,
    height: 32,
  );
  addTearDown(app.dispose);

  await settlePubSearch(app);
  expect(catalog.searchCalls.single.query, 'noir');
  expect(app.captureFrame().toText(), contains('noir_router'));

  app.mockInput
    ..pressTab()
    ..pressEnter();
  await settlePubSearch(app);

  expect(catalog.detailCalls, ['noir']);
  expect(app.captureFrame().toText(), contains('dart pub add noir'));
});
```

Add tests that:

- type a replacement query and submit it;
- resolve an older search after a newer one and prove the older response is ignored;
- show an empty result state;
- show and retry a search/detail error without clearing the query;
- use `s`, `n`, and `p` only while results—not the `TextInput`—have focus;
- press Escape in detail to return to results, then Escape to call `onQuit`;
- dispose the app and assert `FakePubCatalog.closed`.

- [x] **Step 2: Run the interaction test and establish RED**

Run:

```bash
dart test test/example/pub_search_test.dart --concurrency=1
```

Expected first: compile failure for missing `PubSearchApp`; add only its constructor/state signatures, rerun, then observe behavioral failures for absent search, focus, and rendering behavior.

- [x] **Step 3: Implement the stateful shell**

Create `PubSearchApp` with this ownership/API contract:

```dart
class PubSearchApp extends StatefulWidget {
  const PubSearchApp({
    required this.catalog,
    this.onQuit,
    this.initialQuery = 'noir',
    this.autoSearch = true,
    this.autofocusSearch = true,
    super.key,
  });

  final PubCatalog catalog;
  final VoidCallback? onQuit;
  final String initialQuery;
  final bool autoSearch;
  final bool autofocusSearch;

  @override
  State<PubSearchApp> createState() => _PubSearchAppState();
}
```

The state creates and disposes one `TextEditingController`, search/result/detail `FocusNode`s, and a detail `ScrollController`. It takes ownership of `widget.catalog` and closes it in `dispose`. Track `_generation`; increment it for every search/detail request and ignore completions unless `mounted && generation == _generation`.

Independent review additionally required the state to listen to the query and result `FocusNode`s, as `example/focus_form.dart` already does. Their borders are painted from this state's `build`, and a focus move alone does not mark an ancestor element dirty, so without listeners the highlight lagged until an unrelated rebuild.

Represent view state explicitly:

```dart
enum PubSearchView { search, detail }
enum PubLoadState { idle, loading, ready, empty, error }
```

Build the search view with `Column`, a prominent `TextInput`, an `Expanded` result area containing `Select<String>`, and a one-row footer. Keep the result list visually sparse by rendering only package names and using blank-row spacing around the bordered results region. Root key handling must ignore printable keys while the search field has focus; while results have focus, `s` cycles sort, `n` advances only when available, `p` moves to a prior page, and `/` refocuses the query.

- [x] **Step 4: Add the real entrypoint**

Create `example/pub_search.dart` as the runnable/exporting facade:

```dart
// Run with: dart run example/pub_search.dart
import 'dart:io' as io;

import 'package:noir/noir.dart';

import 'pub_search/app.dart';
import 'pub_search/catalog.dart';

export 'pub_search/app.dart';
export 'pub_search/catalog.dart';
export 'pub_search/models.dart';
export 'pub_search/package_detail.dart';

void main() {
  late final TuiApp app;
  void quit() {
    app.dispose();
    io.exit(0);
  }

  app = runTuiApp(PubSearchApp(catalog: PubApiCatalog(), onQuit: quit));
  app.enableMouse();
}
```

Do not register an app-priority bare-letter shortcut. The app state closes the catalog when `app.dispose()` unmounts it, including normal Ctrl+C fallback cleanup.

- [x] **Step 5: Run focused interaction tests and verify GREEN**

Run:

```bash
dart test test/example/pub_search_test.dart --concurrency=1
dart analyze --fatal-infos
```

Expected: async, focus, retry, paging, stale-response, quit, and ownership tests pass without warnings.

---

### Task 5: Implement Quiet Tabs package detail and visual regression coverage

**Files:**
- Create: `example/pub_search/package_detail.dart`
- Modify: `example/pub_search/app.dart`
- Modify: `test/example/pub_search_test.dart`
- Create: `test/golden/pub_search_golden_test.dart`
- Create: `test/goldens/pub_search_detail.buffer.txt`
- Create: `test/goldens/pub_search_detail.styles.txt`
- Create: `test/goldens/pub_search_detail.cursor.txt`

**Interfaces:**
- Consumes: `PubPackageSnapshot` and `downloadSparkline` from Task 3.
- Produces: `PackageDetailTab`, `PubPackageDetail`, left/right and 1–4 tab navigation, scrollable tab content, and the approved 100×32 visual state.

- [x] **Step 1: Extend interaction tests with failing tab assertions**

After opening detail, drive the parser with arrows and number characters:

```dart
expect(render(app), contains('Overview'));
expect(render(app), contains('RUNS ON'));

app.mockInput.pressArrow(ArrowDirection.right);
await settlePubSearch(app);
expect(render(app), contains('PUBLISHED VERSIONS'));

app.mockInput.typeText('3');
await settlePubSearch(app);
expect(render(app), contains('DIRECT DEPENDENCIES'));

app.mockInput.typeText('4');
await settlePubSearch(app);
expect(render(app), contains('WEEKLY DOWNLOADS'));
expect(render(app), contains('▁'));
```

Also assert PageDown changes the captured detail frame and Escape restores the same search result list.

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
dart test test/example/pub_search_test.dart --concurrency=1
```

Expected: FAIL because detail tabs and section content do not exist.

- [x] **Step 3: Implement the focused detail component**

Create:

```dart
enum PackageDetailTab { overview, versions, dependencies, health }

class PubPackageDetail extends StatelessWidget {
  const PubPackageDetail({
    required this.package,
    required this.activeTab,
    required this.scrollController,
    required this.scrollFocusNode,
    super.key,
  });

  final PubPackageSnapshot package;
  final PackageDetailTab activeTab;
  final ScrollController scrollController;
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
      color: const Color(0.03, 0.06, 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPackageHeader(package),
          const SizedBox(height: 1),
          _buildHeadlineMetrics(package),
          const SizedBox(height: 1),
          Row(
            children: [
              for (final tab in PackageDetailTab.values)
                Expanded(
                  child: Text(
                    '${tab.index + 1} ${tab.name}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: tab == activeTab
                          ? const Color(0.39, 0.85, 0.78)
                          : const Color(0.42, 0.51, 0.56),
                      fontWeight:
                          tab == activeTab ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 1),
          Expanded(
            child: ScrollBox(
              controller: scrollController,
              focusNode: scrollFocusNode,
              child: content,
            ),
          ),
          const Text(
            '←→ / 1–4 section  ↑↓ scroll  / search  Esc results',
            style: TextStyle(color: Color(0.37, 0.46, 0.50)),
          ),
        ],
      ),
    );
  }
}
```

Use a dark blue-black root, teal active accents, warm gold for the version/install command, muted labels, generous one-row gaps, and explicit visible borders. The top region contains package/version, description, `dart pub add <name>`, and points/download/version headline metrics. A `Row` renders all four tab labels, styling only `activeTab` as selected. The remaining `Expanded` region contains one vertical `ScrollBox` whose child is the active section's `Column`.

Define `_buildPackageHeader`, `_buildHeadlineMetrics`, `_buildOverview`, `_buildVersions`, `_buildDependencies`, and `_buildHealth` as private functions in the same file. Each returns only Noir `Text`, `RichText`, `Row`, `Column`, `Container`, and `SizedBox` widgets; each section starts with an uppercase muted label and separates logical groups by one blank row.

Render every field from the design contract. Use `Not provided` for absent values, `No advisories reported` for an empty advisory list, and never print raw JSON. Health includes the last up-to-26 weekly totals and their sparkline, analysis/dartdoc status, options, advisory summaries, URL problems, archive metadata, metrics timestamp, and score sections.

- [x] **Step 4: Wire tab navigation in the app shell**

In detail view only, handle:

```dart
if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
  _selectPreviousDetailTab();
  return KeyEventResult.handled;
}
if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
  _selectNextDetailTab();
  return KeyEventResult.handled;
}
if (event.character case final value? when '1234'.contains(value)) {
  _selectDetailTab(PackageDetailTab.values[int.parse(value) - 1]);
  return KeyEventResult.handled;
}
```

Reset the detail scroll controller to zero on every tab change and request the detail scroll focus after a package loads.

- [x] **Step 5: Run interaction tests and verify GREEN**

Run:

```bash
dart test test/example/pub_search_test.dart --concurrency=1
```

Expected: all search and detail interactions pass.

- [x] **Step 6: Write and generate the visual golden**

Create `test/golden/pub_search_golden_test.dart` with `GoldenTester(width: 100, height: 32)` and a populated, deterministic snapshot matching the live Noir package shape. Capture `PubPackageDetail` on `PackageDetailTab.overview`, using caller-owned focus/scroll controllers disposed in `tearDown`.

Run:

```bash
UPDATE_GOLDENS=1 dart test test/golden/pub_search_golden_test.dart --concurrency=1
```

Expected: creates `pub_search_detail.buffer.txt`, `.styles.txt`, and `.cursor.txt`.

- [x] **Step 7: Inspect and lock the golden**

Read all three sidecars. Confirm the package heading, install command, metrics, active Overview tab, labels, whitespace, and footer are visible at 100×32 and that the cursor state is intentional. Then rerun without the update flag:

```bash
dart test test/golden/pub_search_golden_test.dart --concurrency=1
```

Expected: PASS against the checked-in buffer/style/cursor artifacts.

---

### Task 6: Document the example and update the Noir skill

**Files:**
- Modify: `example/README.md`
- Modify: `README.md`
- Modify: `skills/noir/SKILL.md`
- Modify: `skills/noir/references/state-and-animation.md`
- Modify: `test/example/interactive_examples_test.dart`

**Interfaces:**
- Consumes: final run command, controls, ownership, and async behavior from Tasks 3–5.
- Produces: discoverable example catalogs, source guard for mouse enablement, and reusable skill guidance that compiles conceptually against the current API.

- [x] **Step 1: Write the failing catalog/source test**

Extend `interactive_examples_test.dart` so the mouse-capable entrypoint list includes `example/pub_search.dart`, and add source expectations:

```dart
final source = io.File('example/pub_search.dart').readAsStringSync();
expect(source, contains('app.enableMouse();'));
expect(source, contains("PubSearchApp(catalog: PubApiCatalog()"));
```

Run the focused test and expect failure until documentation/source catalogs are updated where asserted.

- [x] **Step 2: Update both example catalogs**

Add `dart run example/pub_search.dart` to `example/README.md` with a description covering live search, fake-backed testing, quiet tabs, paging/sort, and package metadata. Add the matching linked entry to README's Example Apps list. Document controls: Enter search/inspect, Tab focus, arrows navigate, `s` sort, `n`/`p` page, Left/Right or 1–4 switch detail tabs, `/` search, Escape back/quit, wheel/PageUp/PageDown scroll.

- [x] **Step 3: Update the Noir skill review findings**

Add `pub_search.dart` to the skill's reference-example list. In `references/state-and-animation.md`, add a compact “Async data sources” section containing this verified pattern:

```dart
final request = ++_generation;
try {
  final value = await widget.catalog.load();
  if (!mounted || request != _generation) return;
  setState(() => _value = value);
} on Exception catch (error) {
  if (!mounted || request != _generation) return;
  setState(() => _error = '$error');
}
```

State that the owner injects and closes the catalog/client, explicit loading/empty/error states belong in application state, and app-priority bare-letter handlers must not intercept editable text.

- [x] **Step 4: Run focused docs/example checks**

Run:

```bash
dart test test/example/pub_search_catalog_test.dart test/example/pub_search_test.dart test/example/interactive_examples_test.dart test/golden/pub_search_golden_test.dart --concurrency=1
dart format --output=none --set-exit-if-changed example/ test/example/ test/golden/
git diff --check
```

Expected: all new behavior, source guard, and visual coverage pass; documentation references real files and controls.

---

### Task 7: Full verification and handoff

**Files:**
- Review all changes relative to `origin/main` in Noir.
- Review upstream PR state and checks; do not manually rerun workflows.

**Interfaces:**
- Consumes: completed upstream PR and Noir implementation.
- Produces: requirement-by-requirement evidence and a reviewable local Noir diff.

- [x] **Step 1: Verify upstream PR and branch consumption**

Run:

```bash
gh pr view --repo leoafarias/pub_api_client --json number,url,state,headRefOid,statusCheckRollup
dart pub deps | rg 'pub_api_client|pubspec_parse'
```

Expected: PR is OPEN; `headRefOid` matches Noir's locked git commit; the dependency graph resolves the git client branch.

- [x] **Step 2: Run Noir's authorized gates**

Run in order:

```bash
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ scripts/
dart analyze --fatal-infos
dart test test/architecture/ --concurrency=1
dart test --concurrency=1
dart run scripts/fetch_opentui_binaries.dart --verify-only
dart pub publish --dry-run
git diff --check
```

Expected: every command passes; publish dry-run has no unintended runtime dependency or archive warning; native hashes remain unchanged.

- [x] **Step 3: Audit the final Noir diff against the spec**

Use `git diff origin/main...` and explicitly verify:

- live adapter uses only `pub_api_client` and closes it;
- fake-backed tests perform no network calls;
- all meaningful typed fields appear in one of the four tabs;
- weekly metrics come from the upstream typed property;
- stale async responses cannot overwrite newer state;
- search typing is not stolen by shortcuts;
- buffer/style/cursor goldens exist;
- docs and skill name the exact run command and controls;
- no framework internals, FFI calls, native files, or release metadata changed.

- [x] **Step 4: Obtain the required independent Noir behavior/diff review**

Present the verified local diff for an independent reviewer. Resolve any finding with a new failing regression test followed by the smallest fix and rerun the affected gates. Do not commit the Noir implementation before this repository-mandated review is complete.

Outcome: two independent reviews ran, one on behavior and one on the diff and
spec. Ownership boundaries, dev-only dependency resolution, async generation
guards, disposal, input precedence, and error sanitization were confirmed
against framework source. Two findings were resolved:

1. The query/result focus highlight did not follow a bare Tab or click, because
   the state read `FocusNode.hasFocus` during `build` without listening to
   those nodes. Fixed after a failing regression test that asserts the two
   panel border colors swap across a focus move.
2. The design document assigned archive metadata and license identifiers to the
   Health tab and described three headline metrics. The shipped placement is
   the intended one, so the document was corrected to match it.

- [x] **Step 5: Commit the reviewed Noir slice**

After independent approval only:

```bash
git add pubspec.yaml example/pub_search.dart example/pub_search/ test/example/pub_search_catalog_test.dart test/example/pub_search_test.dart test/example/pub_search_test_data.dart test/example/interactive_examples_test.dart test/golden/pub_search_golden_test.dart test/goldens/pub_search_detail.buffer.txt test/goldens/pub_search_detail.styles.txt test/goldens/pub_search_detail.cursor.txt example/README.md README.md skills/noir/SKILL.md skills/noir/references/state-and-animation.md docs/superpowers/
git commit -m "feat: add pub package search example"
```

Expected: one reviewed, verified Noir feature commit on the existing branch; do not rename the branch or open a Noir PR unless separately requested.
