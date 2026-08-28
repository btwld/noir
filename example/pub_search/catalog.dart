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

/// Input the catalog refuses before it contacts pub.dev.
///
/// Distinct from [PubCatalogException] because it names what the person should
/// do next rather than an operation that failed. Both types are rendered
/// verbatim in the example's error panel, so neither may expose a Dart type
/// name the way a bare `FormatException` would.
final class PubQueryException implements Exception {
  /// Creates a rejection presenting [message] verbatim.
  const PubQueryException(this.message);

  /// Instruction shown to the user.
  final String message;

  @override
  String toString() => message;
}

/// Data source used by the pub search example.
abstract interface class PubCatalog {
  /// Searches package names.
  Future<PackageSearchPage> search(
    String query, {
    int page = 1,
    PackageSort sort = PackageSort.top,
    PackageSearchFilter filter = PackageSearchFilter.any,
    String? topic,
  });

  /// Prefix-matches hosted package names and topics for one lookup.
  ///
  /// Prefixes shorter than three characters yield no suggestions. The live
  /// catalog caps the result at twelve package names and four topics; test
  /// catalogs may return more so the UI can exercise overflow.
  Future<List<PubSuggestion>> complete(String prefix);

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
  Future<List<String>?>? _packageNames;
  Future<Map<String, int>?>? _topicCounts;

  @override
  Future<PackageSearchPage> search(
    String query, {
    int page = 1,
    PackageSort sort = PackageSort.top,
    PackageSearchFilter filter = PackageSearchFilter.any,
    String? topic,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      throw const PubQueryException(
        'Enter a package name or search expression.',
      );
    }
    late final SearchResults result;
    try {
      result = await _client.search(
        normalized,
        page: page,
        sort: _toSearchOrder(sort),
        tags: _tagsFor(filter),
        topics: [if (topic != null && topic.isNotEmpty) topic],
      );
    } on Exception {
      throw const PubCatalogException('Search pub.dev');
    }
    return PackageSearchPage(
      page: page,
      packages: result.packages
          .map((package) => package.package)
          .toList(growable: false),
      hasNextPage: result.next != null,
      message: result.message,
    );
  }

  @override
  Future<List<PubSuggestion>> complete(String prefix) async {
    final needle = prefix.trim().toLowerCase();
    if (needle.length < 3) return const [];
    // Attach recovery to both requests before awaiting either one. A partial
    // endpoint failure should not discard useful suggestions from the other
    // hosted list, while two failures still become one safe boundary error.
    // Successful corpora stay cached so later prefixes do not refetch.
    final packageNamesRequest = _packageNamesCorpus();
    final topicCountsRequest = _topicCountsCorpus();
    final packageNames = await packageNamesRequest;
    final topicCounts = await topicCountsRequest;
    if (packageNames == null && topicCounts == null) {
      throw const PubCatalogException('Load name completion');
    }
    // Twelve names and four topics is the live suggestion budget: enough to
    // scan, not enough to dump the hosted completion lists into the overlay.
    final packages = (packageNames ?? const <String>[])
        .where((name) => name.toLowerCase().startsWith(needle))
        .take(12)
        .map(PubSuggestion.package);
    final topics = (topicCounts ?? const <String, int>{}).entries
        .where((entry) => entry.key.toLowerCase().startsWith(needle))
        .take(4)
        .map((entry) => PubSuggestion.topic(entry.key, entry.value));
    return [...packages, ...topics];
  }

  @override
  Future<PubPackageSnapshot> loadPackage(String name) async {
    try {
      // Only the package record is required. Every other endpoint is optional,
      // so a failing score, publisher, or advisory lookup renders its absent
      // state instead of losing the package the user actually asked for.
      final packageFuture = _client.packageInfo(name);
      final metricsFuture = _optional(_client.packageMetrics(name));
      final publisherFuture = _optional(_client.packagePublisher(name));
      final optionsFuture = _optional(_client.packageOptions(name));
      final documentationFuture = _optional(_client.documentation(name));
      final advisoriesFuture = _optional(_client.packageAdvisories(name));

      final package = await packageFuture;
      final metrics = await metricsFuture;
      final score =
          metrics?.score ?? await _optional(_client.packageScore(name));
      return PubPackageSnapshot.fromApi(
        package: package,
        score: score,
        metrics: metrics,
        publisher: await publisherFuture,
        options: await optionsFuture,
        documentation: await documentationFuture,
        advisories: await advisoriesFuture,
      );
    } on Object {
      throw PubCatalogException('Load $name from pub.dev');
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _packageNames = null;
    _topicCounts = null;
    _client.close();
  }

  Future<List<String>?> _packageNamesCorpus() {
    final inFlight = _packageNames;
    if (inFlight != null) return inFlight;
    late final Future<List<String>?> future;
    future = _optional(_client.packageNameCompletion()).then((value) {
      if (value == null && identical(_packageNames, future)) {
        _packageNames = null;
      }
      return value;
    });
    _packageNames = future;
    return future;
  }

  Future<Map<String, int>?> _topicCountsCorpus() {
    final inFlight = _topicCounts;
    if (inFlight != null) return inFlight;
    late final Future<Map<String, int>?> future;
    future = _optional(_client.topicNameCompletion()).then((value) {
      if (value == null && identical(_topicCounts, future)) {
        _topicCounts = null;
      }
      return value;
    });
    _topicCounts = future;
    return future;
  }

  Future<T?> _optional<T>(Future<T> request) async {
    try {
      return await request;
    } on Exception {
      return null;
    }
  }

  List<String> _tagsFor(PackageSearchFilter filter) => switch (filter) {
    PackageSearchFilter.any => const [],
    PackageSearchFilter.dart => [PackageTag.sdkDart],
    PackageSearchFilter.flutter => [PackageTag.sdkFlutter],
    PackageSearchFilter.favorite => [PackageTag.isFlutterFavorite],
  };

  SearchOrder _toSearchOrder(PackageSort sort) => switch (sort) {
    PackageSort.top => SearchOrder.top,
    PackageSort.text => SearchOrder.text,
    PackageSort.created => SearchOrder.created,
    PackageSort.updated => SearchOrder.updated,
    PackageSort.downloads => SearchOrder.downloads,
    PackageSort.likes => SearchOrder.like,
    PackageSort.points => SearchOrder.points,
    PackageSort.trending => SearchOrder.trending,
  };
}
