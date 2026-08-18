import 'package:pub_api_client/pub_api_client.dart';
import 'package:test/test.dart';

import '../../example/pub_search/catalog.dart';
import '../../example/pub_search/models.dart';

void main() {
  group('PubPackageSnapshot.fromApi', () {
    test('maps the complete package detail surface', () {
      final metricsPayload = _metricsPayload();
      final snapshot = PubPackageSnapshot.fromApi(
        package: PubPackage.fromMap(_packagePayload()),
        score: PackageScore.fromMap(
          metricsPayload['score'] as Map<String, dynamic>,
        ),
        metrics: PackageMetrics.fromMap(metricsPayload),
        publisher: PackagePublisher.fromMap({'publisherId': 'leoafarias.com'}),
        options: PackageOptions.fromMap({
          'isDiscontinued': false,
          'isUnlisted': false,
          'replacedBy': null,
        }),
        documentation: PackageDocumentation.fromMap({
          'name': 'noir',
          'versions': [
            {
              'version': '0.0.1-alpha.1',
              'status': 'documented',
              'hasDocumentation': true,
            },
          ],
        }),
        advisories: PackageAdvisories.fromMap({
          'advisories': [
            {
              'id': 'GHSA-test',
              'summary': 'A sample advisory',
              'details': 'Upgrade when a patched release is available.',
              'affected': [
                {
                  'versions': ['0.0.1-alpha.1'],
                },
              ],
              'database_specific': {
                'pub_display_url': 'https://pub.dev/advisories/GHSA-test',
              },
            },
          ],
          'advisoriesUpdated': '2026-08-17T00:00:00.000Z',
        }),
      );

      expect(snapshot.name, 'noir');
      expect(snapshot.version, '0.0.1-alpha.1');
      expect(snapshot.packageUrl, 'https://pub.dev/packages/noir');
      expect(snapshot.changelogUrl, 'https://pub.dev/packages/noir/changelog');
      expect(snapshot.publisher, 'leoafarias.com');
      expect(snapshot.environment['sdk'], '>=3.10.0 <4.0.0');
      expect(snapshot.topics, ['tui', 'terminal']);
      expect(snapshot.platforms, ['linux', 'macos', 'windows']);
      expect(snapshot.directDependencies['ffi']?.constraint, '^2.1.0');
      expect(
        snapshot.directDependencies['git_pkg'],
        isA<PackageDependencySummary>()
            .having(
              (dependency) => dependency.source,
              'source',
              PackageDependencySource.git,
            )
            .having(
              (dependency) => dependency.url,
              'url',
              'https://example.com/packages.git',
            )
            .having((dependency) => dependency.ref, 'ref', 'stable')
            .having((dependency) => dependency.path, 'path', 'pkgs/core'),
      );
      expect(
        snapshot.directDependencies['hosted_pkg'],
        isA<PackageDependencySummary>()
            .having(
              (dependency) => dependency.source,
              'source',
              PackageDependencySource.hosted,
            )
            .having(
              (dependency) => dependency.constraint,
              'constraint',
              '^2.0.0',
            )
            .having(
              (dependency) => dependency.packageName,
              'package',
              'actual_pkg',
            )
            .having(
              (dependency) => dependency.url,
              'url',
              'https://pub.example',
            ),
      );
      expect(snapshot.directDependencies['local_pkg']?.path, '../local_pkg');
      expect(snapshot.directDependencies['flutter']?.sdk, 'flutter');
      expect(snapshot.directDependencies['flutter']?.constraint, '^3.0.0');
      expect(snapshot.dependencyOverrides['meta']?.constraint, '^1.12.0');
      expect(snapshot.releases.single.hasDocumentation, isTrue);
      expect(
        snapshot.releases.single.archiveUrl,
        'https://pub.dev/api/archives/noir-0.0.1-alpha.1.tar.gz',
      );
      expect(snapshot.releases.single.archiveSha256, 'abc123');
      expect(snapshot.weeklyDownloads, [4, 9, 16]);
      expect(
        snapshot.majorVersionDownloads.single.versionRange,
        '>=0.0.0 <1.0.0',
      );
      expect(snapshot.analysisStatus, 'success');
      expect(snapshot.advisories.single.affectedVersions, ['0.0.1-alpha.1']);
      expect(snapshot.fundingUrls, ['https://github.com/sponsors/leoafarias']);
      expect(snapshot.executables, {'noir': null});
      expect(snapshot.healthSections.single.grantedPoints, 160);
      expect(snapshot.urlProblems, [
        'url: https://example.com/old; problem: redirects',
      ]);
      expect(snapshot.analysisScreenshots, [
        'description: Package overview; url: https://example.com/noir.png',
      ]);
      expect(snapshot.urlProblems.single, isNot(contains('do-not-display')));
      expect(
        snapshot.analysisScreenshots.single,
        isNot(contains('do-not-display')),
      );
    });

    test('keeps unavailable optional responses honest', () {
      final snapshot = PubPackageSnapshot.fromApi(
        package: PubPackage.fromMap(_packagePayload()),
        score: null,
        metrics: null,
        publisher: null,
        options: null,
        documentation: null,
        advisories: null,
      );

      expect(snapshot.publisher, isNull);
      expect(snapshot.grantedPoints, isNull);
      expect(snapshot.weeklyDownloads, isEmpty);
      expect(snapshot.analysisStatus, isNull);
      expect(snapshot.advisories, isEmpty);
      expect(snapshot.releases.single.hasDocumentation, isNull);
    });
  });

  test('downloadSparkline scales values and handles unavailable data', () {
    expect(downloadSparkline([0, 10, 20]), '▁▅█');
    expect(downloadSparkline([0, 0, 0]), '▁▁▁');
    expect(downloadSparkline(const []), 'Not available');
    expect(
      recentDownloadCounts(List.generate(52, (index) => index)),
      List.generate(26, (index) => index + 26),
    );
  });

  test('application models defensively snapshot mutable collections', () {
    final packages = <String>['noir'];
    final affected = <String>['0.0.1'];
    final counts = <int>[1, 2];
    final topics = <String>['terminal'];
    final dependencies = <String, PackageDependencySummary>{
      'ffi': const PackageDependencySummary(
        source: PackageDependencySource.hosted,
        constraint: '^2.1.0',
      ),
    };
    final releases = <PackageRelease>[
      PackageRelease(
        version: '1.0.0',
        published: DateTime.utc(2026),
        retracted: false,
        archiveUrl: 'https://example.com/archive.tar.gz',
        archiveSha256: 'abc',
      ),
    ];
    final page = PackageSearchPage(
      query: 'noir',
      page: 1,
      sort: PackageSort.top,
      packages: packages,
      hasNextPage: false,
    );
    final advisory = PackageAdvisorySummary(
      id: 'GHSA-test',
      affectedVersions: affected,
    );
    final downloads = PackageVersionDownloads(
      versionRange: '^1.0.0',
      counts: counts,
    );
    final snapshot = PubPackageSnapshot(
      name: 'noir',
      version: '1.0.0',
      description: 'Terminal UI',
      published: DateTime.utc(2026),
      topics: topics,
      directDependencies: dependencies,
      releases: releases,
    );

    packages.add('mutated');
    affected.add('9.9.9');
    counts.add(3);
    topics.add('mutated');
    dependencies.clear();
    releases.clear();

    expect(page.packages, ['noir']);
    expect(advisory.affectedVersions, ['0.0.1']);
    expect(downloads.counts, [1, 2]);
    expect(snapshot.topics, ['terminal']);
    expect(snapshot.directDependencies, contains('ffi'));
    expect(snapshot.releases.single.version, '1.0.0');
    expect(() => snapshot.topics.add('blocked'), throwsUnsupportedError);
    expect(snapshot.directDependencies.clear, throwsUnsupportedError);
  });

  group('PubApiCatalog', () {
    test('normalizes search and maps the selected sort order', () async {
      final client = _FakePubClient();
      final catalog = PubApiCatalog(client: client);

      final page = await catalog.search(
        '  terminal ui  ',
        page: 2,
        sort: PackageSort.downloads,
      );

      expect(client.searchQuery, 'terminal ui');
      expect(client.searchPage, 2);
      expect(client.searchOrder, SearchOrder.downloads);
      expect(page.packages, ['noir', 'tui']);
      expect(page.hasNextPage, isTrue);
      catalog.close();
      expect(client.closed, isTrue);
    });

    test('maps every public sort order to the client', () async {
      const expected = {
        PackageSort.top: SearchOrder.top,
        PackageSort.text: SearchOrder.text,
        PackageSort.created: SearchOrder.created,
        PackageSort.updated: SearchOrder.updated,
        PackageSort.popularity: SearchOrder.popularity,
        PackageSort.downloads: SearchOrder.downloads,
        PackageSort.likes: SearchOrder.like,
        PackageSort.points: SearchOrder.points,
      };
      final client = _FakePubClient();
      final catalog = PubApiCatalog(client: client);

      for (final entry in expected.entries) {
        await catalog.search('noir', sort: entry.key);
        expect(client.searchOrder, entry.value, reason: '${entry.key}');
      }
      catalog.close();
    });

    test('loads and combines all public package detail responses', () async {
      final client = _FakePubClient();
      final catalog = PubApiCatalog(client: client);

      final snapshot = await catalog.loadPackage('noir');

      expect(snapshot.name, 'noir');
      expect(snapshot.publisher, 'leoafarias.com');
      expect(snapshot.weeklyDownloads, [4, 9, 16]);
      expect(client.loadedPackage, 'noir');
      catalog.close();
    });

    test('keeps detail usable when an optional endpoint fails', () async {
      final client = _FakePubClient()
        ..metricsError = Exception('temporary metrics response body');
      final catalog = PubApiCatalog(client: client);

      final snapshot = await catalog.loadPackage('noir');

      expect(snapshot.name, 'noir');
      expect(snapshot.grantedPoints, 160);
      expect(snapshot.weeklyDownloads, isEmpty);
      catalog.close();
    });

    test(
      'labels required failures without exposing response details',
      () async {
        final searchClient = _FakePubClient()
          ..searchError = Exception('private search response body');
        final searchCatalog = PubApiCatalog(client: searchClient);

        await expectLater(
          searchCatalog.search('noir'),
          throwsA(
            isA<PubCatalogException>()
                .having(
                  (error) => error.operation,
                  'operation',
                  'Search pub.dev',
                )
                .having(
                  (error) => '$error',
                  'safe message',
                  'Search pub.dev failed. Please try again.',
                ),
          ),
        );
        searchCatalog.close();

        final detailClient = _FakePubClient()
          ..packageError = Exception('private detail response body');
        final detailCatalog = PubApiCatalog(client: detailClient);

        await expectLater(
          detailCatalog.loadPackage('noir'),
          throwsA(
            isA<PubCatalogException>()
                .having(
                  (error) => error.operation,
                  'operation',
                  'Load noir from pub.dev',
                )
                .having(
                  (error) => '$error',
                  'safe message',
                  'Load noir from pub.dev failed. Please try again.',
                ),
          ),
        );
        detailCatalog.close();
      },
    );

    test('rejects an empty query before requesting pub.dev', () async {
      final client = _FakePubClient();
      final catalog = PubApiCatalog(client: client);

      await expectLater(catalog.search('   '), throwsA(isA<FormatException>()));
      expect(client.searchQuery, isNull);
      catalog.close();
    });
  });
}

final class _FakePubClient extends PubClient {
  _FakePubClient() : super(userAgent: 'noir-test');

  String? searchQuery;
  int? searchPage;
  SearchOrder? searchOrder;
  String? loadedPackage;
  bool closed = false;
  Exception? searchError;
  Exception? packageError;
  Exception? metricsError;

  @override
  Future<SearchResults> search(
    String query, {
    int page = 1,
    SearchOrder sort = SearchOrder.top,
    List<String> tags = const [],
    List<String> topics = const [],
  }) async {
    if (searchError case final error?) throw error;
    searchQuery = query;
    searchPage = page;
    searchOrder = sort;
    return const SearchResults(
      packages: [
        PackageResult(package: 'noir'),
        PackageResult(package: 'tui'),
      ],
      next: 'https://pub.dev/api/search?page=3&q=terminal+ui',
    );
  }

  @override
  Future<PubPackage> packageInfo(String packageName) async {
    if (packageError case final error?) throw error;
    loadedPackage = packageName;
    return PubPackage.fromMap(_packagePayload());
  }

  @override
  Future<PackageMetrics?> packageMetrics(String packageName) async {
    if (metricsError case final error?) throw error;
    return PackageMetrics.fromMap(_metricsPayload());
  }

  @override
  Future<PackageScore> packageScore(String packageName) async =>
      PackageScore.fromMap(_metricsPayload()['score'] as Map<String, dynamic>);

  @override
  Future<PackagePublisher> packagePublisher(String packageName) async =>
      const PackagePublisher(publisherId: 'leoafarias.com');

  @override
  Future<PackageOptions> packageOptions(String packageName) async =>
      const PackageOptions();

  @override
  Future<PackageDocumentation> documentation(String packageName) async =>
      PackageDocumentation.fromMap({
        'name': 'noir',
        'versions': [
          {
            'version': '0.0.1-alpha.1',
            'status': 'documented',
            'hasDocumentation': true,
          },
        ],
      });

  @override
  Future<PackageAdvisories?> packageAdvisories(String packageName) async =>
      const PackageAdvisories(advisories: []);

  @override
  void close() {
    closed = true;
    super.close();
  }
}

Map<String, dynamic> _packagePayload() => {
  'name': 'noir',
  'latest': _versionPayload(),
  'versions': [_versionPayload()],
  'isDiscontinued': false,
  'replacedBy': null,
  'advisoriesUpdated': '2026-08-17T00:00:00.000Z',
};

Map<String, dynamic> _versionPayload() => {
  'version': '0.0.1-alpha.1',
  'pubspec': {
    'name': 'noir',
    'version': '0.0.1-alpha.1',
    'description': 'A Flutter-like reactive terminal UI framework for Dart.',
    'homepage': 'https://github.com/leoafarias/noir',
    'repository': 'https://github.com/leoafarias/noir',
    'issue_tracker': 'https://github.com/leoafarias/noir/issues',
    'documentation': 'https://pub.dev/documentation/noir/latest/',
    'funding': ['https://github.com/sponsors/leoafarias'],
    'topics': ['tui', 'terminal'],
    'ignored_advisories': ['GHSA-ignored'],
    'screenshots': [
      {'description': 'Quiet terminal UI', 'path': 'screenshots/noir.png'},
    ],
    'environment': {'sdk': '>=3.10.0 <4.0.0'},
    'dependencies': {
      'ffi': '^2.1.0',
      'git_pkg': {
        'git': {
          'url': 'https://example.com/packages.git',
          'ref': 'stable',
          'path': 'pkgs/core',
        },
      },
      'hosted_pkg': {
        'hosted': {'name': 'actual_pkg', 'url': 'https://pub.example'},
        'version': '^2.0.0',
      },
      'local_pkg': {'path': '../local_pkg'},
      'flutter': {'sdk': 'flutter', 'version': '^3.0.0'},
    },
    'dev_dependencies': {'test': '^1.25.0'},
    'dependency_overrides': {'meta': '^1.12.0'},
    'executables': {'noir': null},
    'publish_to': 'https://pub.dev',
  },
  'archive_url': 'https://pub.dev/api/archives/noir-0.0.1-alpha.1.tar.gz',
  'archive_sha256': 'abc123',
  'published': '2026-08-16T12:00:00.000Z',
  'retracted': false,
};

Map<String, dynamic> _metricsPayload() => {
  'score': {
    'grantedPoints': 160,
    'maxPoints': 160,
    'likeCount': 12,
    'popularityScore': 0.42,
    'downloadCount30Days': 56,
    'tags': [
      'platform:linux',
      'platform:macos',
      'platform:windows',
      'runtime:native-aot',
      'license:bsd-3-clause',
    ],
  },
  'scorecard': {
    'packageName': 'noir',
    'packageVersion': '0.0.1-alpha.1',
    'runtimeVersion': '2026.08.12',
    'updated': '2026-08-17T00:00:00.000Z',
    'taskStatus': 'completed',
    'dartdocReport': {'reportStatus': 'success'},
    'panaReport': {
      'timestamp': '2026-08-17T00:00:00.000Z',
      'reportStatus': 'success',
      'derivedTags': ['sdk:dart'],
      'allDependencies': ['ffi', 'meta'],
      'licenses': [
        {'path': 'LICENSE', 'spdxIdentifier': 'BSD-3-Clause'},
      ],
      'screenshots': [
        {
          'description': 'Package overview',
          'url': 'https://example.com/noir.png',
          'internal': {'token': 'do-not-display'},
        },
      ],
      'urlProblems': [
        {
          'url': 'https://example.com/old',
          'problem': 'redirects',
          'internal': {'token': 'do-not-display'},
        },
      ],
      'panaRuntimeInfo': {
        'panaVersion': '0.22.17',
        'sdkVersion': '3.10.0',
        'flutterVersions': null,
      },
      'report': {
        'sections': [
          {
            'id': 'documentation',
            'title': 'Documentation',
            'grantedPoints': 160,
            'maxPoints': 160,
            'status': 'success',
            'summary': 'All checks passed.',
          },
        ],
      },
      'result': {
        'homepageUrl': 'https://github.com/leoafarias/noir',
        'repositoryUrl': 'https://github.com/leoafarias/noir',
        'issueTrackerUrl': 'https://github.com/leoafarias/noir/issues',
        'documentationUrl': 'https://pub.dev/documentation/noir/latest/',
        'fundingUrls': ['https://github.com/sponsors/leoafarias'],
        'contributingUrl': 'https://github.com/leoafarias/noir/CONTRIBUTING.md',
        'grantedPoints': 160,
        'maxPoints': 160,
        'repository': {
          'provider': 'github',
          'host': 'github.com',
          'repository': 'leoafarias/noir',
          'branch': 'main',
        },
      },
    },
    'weeklyVersionDownloads': {
      'totalWeeklyDownloads': [4, 9, 16],
      'majorRangeWeeklyDownloads': [
        {
          'counts': [4, 9, 16],
          'versionRange': '>=0.0.0 <1.0.0',
        },
      ],
      'minorRangeWeeklyDownloads': <Object?>[],
      'patchRangeWeeklyDownloads': <Object?>[],
      'newestDate': '2026-08-15T00:00:00.000Z',
    },
  },
};
