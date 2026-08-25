import 'dart:async';

import 'package:noir/noir.dart';

import '../../example/pub_search/app.dart';
import '../../example/pub_search/catalog.dart';
import '../../example/pub_search/models.dart';

/// Deterministic host used only by the documentation recorder.
void main() => runTuiApp(
  PubSearchApp(catalog: _RecordingCatalog(), autoSearch: false),
  enableMouse: true,
);

final class _RecordingCatalog implements PubCatalog {
  var _closed = false;

  @override
  Future<PackageSearchPage> search(
    String query, {
    int page = 1,
    PackageSort sort = PackageSort.top,
    PackageSearchFilter filter = PackageSearchFilter.any,
    String? topic,
  }) async {
    _requireOpen();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    _requireOpen();
    return PackageSearchPage(
      page: page,
      packages: const ['noir', 'noir_hooks', 'noir_cli', 'open_tui'],
      hasNextPage: false,
      message: 'Deterministic documentation fixture',
    );
  }

  @override
  Future<List<PubSuggestion>> complete(String prefix) async {
    _requireOpen();
    return const [];
  }

  @override
  Future<PubPackageSnapshot> loadPackage(String name) async {
    _requireOpen();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    _requireOpen();
    return PubPackageSnapshot(
      name: name,
      version: '0.0.1-alpha.3',
      description: 'Flutter-inspired reactive terminal UI for Dart.',
      published: DateTime.utc(2026, 8, 25),
      packageUrl: 'https://pub.dev/packages/$name',
      repository: 'https://github.com/leoafarias/noir',
      publisher: 'noir.dev',
      environment: const {'sdk': '>=3.10.0 <4.0.0'},
      topics: const ['terminal', 'tui', 'widgets'],
      platforms: const ['linux', 'macos', 'windows'],
      licenses: const ['BSD-3-Clause'],
      grantedPoints: 150,
      maxPoints: 160,
      likeCount: 128,
      downloadCount30Days: 4096,
      releases: [
        PackageRelease(
          version: '0.0.1-alpha.3',
          published: DateTime.utc(2026, 8, 25),
          retracted: false,
          hasDocumentation: true,
          documentationStatus: 'documented',
        ),
      ],
    );
  }

  @override
  void close() => _closed = true;

  void _requireOpen() {
    if (_closed) throw StateError('Recording catalog is closed.');
  }
}
