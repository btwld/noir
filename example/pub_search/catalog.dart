import 'package:pub_api_client/pub_api_client.dart';

import 'models.dart';

/// Safe, operation-labelled failure exposed by the live catalog boundary.
final class PubCatalogException implements Exception {
  /// Creates a failure for [operation] without retaining response details.
  const PubCatalogException(this.operation);

  /// Human-readable operation that could not be completed.
  final String operation;

  @override
  String toString() => '$operation failed. Please try again.';
}

/// Data source used by the pub search example.
abstract interface class PubCatalog {
  /// Searches package names.
  Future<PackageSearchPage> search(
    String query, {
    int page = 1,
    PackageSort sort = PackageSort.top,
  });

  /// Loads all useful public detail responses for [name].
  Future<PubPackageSnapshot> loadPackage(String name);

  /// Releases resources owned by the catalog.
  void close();
}

/// Live [PubCatalog] backed exclusively by `package:pub_api_client`.
final class PubApiCatalog implements PubCatalog {
  /// Creates a live catalog, optionally with an injected client for tests.
  PubApiCatalog({PubClient? client})
    : _client = client ?? PubClient(userAgent: 'noir-pub-example');

  final PubClient _client;
  var _closed = false;

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
    late final SearchResults result;
    try {
      result = await _client.search(
        normalized,
        page: page,
        sort: _toSearchOrder(sort),
      );
    } on Exception {
      throw const PubCatalogException('Search pub.dev');
    }
    return PackageSearchPage(
      query: normalized,
      page: page,
      sort: sort,
      packages: List.unmodifiable(
        result.packages.map((package) => package.package),
      ),
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

    late final PubPackage package;
    try {
      package = await packageFuture;
    } on Exception {
      throw PubCatalogException('Load $name from pub.dev');
    }
    final metrics = await metricsFuture;
    final score = metrics?.score ?? await _optional(_client.packageScore(name));
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
  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }

  Future<T?> _optional<T>(Future<T> request) async {
    try {
      return await request;
    } on Exception {
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
