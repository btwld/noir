import '../../example/pub_search/models.dart';

final examplePubPackage = PubPackageSnapshot(
  name: 'noir',
  version: '0.0.1-alpha.1',
  description: 'A Flutter-like reactive terminal UI framework for Dart.',
  published: DateTime.utc(2026, 8, 16, 12),
  packageUrl: 'https://pub.dev/packages/noir',
  changelogUrl: 'https://pub.dev/packages/noir/changelog',
  publisher: 'leoafarias.com',
  environment: const {'sdk': '>=3.10.0 <4.0.0'},
  homepage: 'https://github.com/leoafarias/noir',
  repository: 'https://github.com/leoafarias/noir',
  issueTracker: 'https://github.com/leoafarias/noir/issues',
  documentationUrl: 'https://pub.dev/documentation/noir/latest/',
  contributingUrl: 'https://github.com/leoafarias/noir/CONTRIBUTING.md',
  fundingUrls: const ['https://github.com/sponsors/leoafarias'],
  topics: const ['tui', 'terminal', 'widgets'],
  platforms: const ['linux', 'macos', 'windows'],
  runtimes: const ['native-aot'],
  licenses: const ['BSD-3-Clause (LICENSE)'],
  publishTo: 'https://pub.dev',
  screenshots: const [
    PackageScreenshotSummary(
      description: 'Quiet terminal UI',
      path: 'screenshots/noir.png',
    ),
  ],
  directDependencies: const {
    'characters': PackageDependencySummary(
      source: PackageDependencySource.hosted,
      constraint: '^1.3.0',
    ),
    'ffi': PackageDependencySummary(
      source: PackageDependencySource.hosted,
      constraint: '^2.1.0',
    ),
    'meta': PackageDependencySummary(
      source: PackageDependencySource.hosted,
      constraint: '^1.12.0',
    ),
    'noir_plugin': PackageDependencySummary(
      source: PackageDependencySource.git,
      url: 'https://example.com/noir_plugin.git',
      ref: 'main',
      path: 'packages/plugin',
    ),
  },
  devDependencies: const {
    'test': PackageDependencySummary(
      source: PackageDependencySource.hosted,
      constraint: '^1.25.0',
    ),
    'analyzer': PackageDependencySummary(
      source: PackageDependencySource.hosted,
      constraint: '^8.2.0',
    ),
  },
  dependencyOverrides: const {
    'meta': PackageDependencySummary(
      source: PackageDependencySource.hosted,
      constraint: '^1.12.0',
    ),
  },
  transitiveDependencies: const ['characters', 'ffi', 'meta', 'hooks'],
  executables: const {'noir': null},
  grantedPoints: 160,
  maxPoints: 160,
  likeCount: 12,
  downloadCount30Days: 56,
  releases: [
    PackageRelease(
      version: '0.0.1-alpha.1',
      published: _published,
      retracted: false,
      archiveUrl: 'https://pub.dev/api/archives/noir-0.0.1-alpha.1.tar.gz',
      archiveSha256: 'abc123',
      hasDocumentation: true,
      documentationStatus: 'documented',
    ),
    PackageRelease(
      version: '0.0.1-alpha.0',
      published: _earlier,
      retracted: false,
      archiveUrl: 'https://pub.dev/api/archives/noir-0.0.1-alpha.0.tar.gz',
      archiveSha256: 'def456',
      hasDocumentation: true,
      documentationStatus: 'documented',
    ),
  ],
  advisories: [
    PackageAdvisorySummary(
      id: 'GHSA-test',
      summary: 'A sample advisory',
      details: 'Upgrade when a patched release is available.',
      url: 'https://pub.dev/advisories/GHSA-test',
      affectedVersions: ['0.0.1-alpha.1'],
    ),
  ],
  advisoriesUpdated: _updated,
  analysisStatus: 'success',
  dartdocStatus: 'success',
  taskStatus: 'completed',
  healthSections: const [
    PackageHealthSection(
      title: 'Documentation',
      status: 'success',
      summary: 'All checks passed.',
      grantedPoints: 160,
      maxPoints: 160,
    ),
  ],
  archiveUrl: 'https://pub.dev/api/archives/noir-0.0.1-alpha.1.tar.gz',
  archiveSha256: 'abc123',
  metricsUpdated: _updated,
  analysisUpdated: _updated,
  scorecardPackageVersion: '0.0.1-alpha.1',
  scorecardRuntimeVersion: '2026.08.12',
  panaVersion: '0.22.17',
  analyzedSdkVersion: '3.10.0',
  repositorySummary: const PackageRepositorySummary(
    provider: 'github',
    host: 'github.com',
    repository: 'leoafarias/noir',
    branch: 'main',
  ),
  analysisGrantedPoints: 160,
  analysisMaxPoints: 160,
  weeklyDownloads: const [4, 5, 7, 9, 12, 16],
  majorVersionDownloads: [
    PackageVersionDownloads(
      versionRange: '>=0.0.0 <1.0.0',
      counts: [4, 5, 7, 9, 12, 16],
    ),
  ],
  weeklyDownloadsNewestDate: _newestDownloads,
);

final _published = DateTime.utc(2026, 8, 16, 12);
final _earlier = DateTime.utc(2026, 8, 9, 12);
final _updated = DateTime.utc(2026, 8, 17);
final _newestDownloads = DateTime.utc(2026, 8, 15);
