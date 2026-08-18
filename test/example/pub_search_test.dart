import 'dart:async';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/pub_search/app.dart';
import '../../example/pub_search/catalog.dart';
import '../../example/pub_search/models.dart';
import '../helpers/tui_test_app.dart';
import 'pub_search_test_data.dart';

void main() {
  test('runs the initial search and opens the confirmed package', () async {
    final catalog = _FakePubCatalog()
      ..searchResults.add(
        Future.value(
          PackageSearchPage(
            page: 1,
            packages: ['noir', 'noir_router'],
            hasNextPage: false,
          ),
        ),
      )
      ..detailResults['noir'] = Future.value(examplePubPackage);
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () {}),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      expect(catalog.searchCalls.single.query, 'noir');
      expect(_render(app), contains('noir_router'));
      expect(_render(app), contains('LIVE PUB.DEV'));
      expect(_render(app), contains('sdk:flutter'));

      app.mockInput
        ..pressTab()
        ..pressEnter();
      await _settle(app);

      expect(catalog.detailCalls, ['noir']);
      expect(_render(app), contains('dart pub add noir'));
    } finally {
      app.dispose();
    }
    expect(catalog.closed, isTrue);
  });

  test('ignores a stale search completion', () async {
    final oldSearch = Completer<PackageSearchPage>();
    final newSearch = Completer<PackageSearchPage>();
    final catalog = _FakePubCatalog()
      ..searchResults.addAll([oldSearch.future, newSearch.future]);
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () {}),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      app.mockInput
        ..pressBackspace()
        ..pressBackspace()
        ..pressBackspace()
        ..pressBackspace()
        ..typeText('terminal')
        ..pressEnter();
      await _settle(app);

      newSearch.complete(
        PackageSearchPage(
          page: 1,
          packages: ['new_result'],
          hasNextPage: false,
        ),
      );
      await _settle(app);
      oldSearch.complete(
        PackageSearchPage(
          page: 1,
          packages: ['stale_result'],
          hasNextPage: false,
        ),
      );
      await _settle(app);

      expect(_render(app), contains('new_result'));
      expect(_render(app), isNot(contains('stale_result')));
    } finally {
      app.dispose();
    }
  });

  test('keeps letters editable and scopes result shortcuts', () async {
    final catalog = _FakePubCatalog()
      ..searchResults.addAll([
        Future.value(
          PackageSearchPage(
            page: 1,
            packages: ['searchable'],
            hasNextPage: false,
          ),
        ),
        Future.value(
          PackageSearchPage(page: 1, packages: ['sorted'], hasNextPage: false),
        ),
      ]);
    final app = createTuiTestApp(
      PubSearchApp(
        catalog: catalog,
        onQuit: () {},
        initialQuery: '',
        autoSearch: false,
        connection: PubSearchConnection.offline,
      ),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      // A caller-supplied catalog is not pub.dev, and the header says so.
      expect(_render(app), contains('OFFLINE DATA'));

      app.mockInput
        ..typeText('s')
        ..pressEnter();
      await _settle(app);
      expect(catalog.searchCalls.single.query, 's');
      expect(catalog.searchCalls.single.sort, PackageSort.top);

      app.mockInput
        ..pressTab()
        ..typeText('s');
      await _settle(app);
      expect(catalog.searchCalls.last.sort, PackageSort.text);
      expect(_render(app), contains('sorted'));
    } finally {
      app.dispose();
    }
  });

  test('moves the panel focus highlight when Tab changes focus', () async {
    final catalog = _FakePubCatalog()
      ..searchResults.add(
        Future.value(
          PackageSearchPage(page: 1, packages: ['noir'], hasNextPage: false),
        ),
      );
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () {}),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      final before = _panelBorders(app);
      expect(before.query, isNot(before.results));

      // Tab alone changes focus without any app-level setState, so the
      // highlight only follows if the state listens to its own focus nodes.
      app.mockInput.pressTab();
      await _settle(app);
      final after = _panelBorders(app);

      expect(after.query, before.results);
      expect(after.results, before.query);
    } finally {
      app.dispose();
    }
  });

  test('Escape returns to results before requesting quit', () async {
    var quits = 0;
    final catalog = _FakePubCatalog()
      ..searchResults.add(
        Future.value(
          PackageSearchPage(page: 1, packages: ['noir'], hasNextPage: false),
        ),
      )
      ..detailResults['noir'] = Future.value(examplePubPackage);
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () => quits++),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      app.mockInput
        ..pressTab()
        ..pressEnter();
      await _settle(app);
      app.mockInput.pressEscape();
      await _settle(app);
      expect(_render(app), contains('noir'));
      expect(quits, 0);

      app.mockInput.pressEscape();
      expect(quits, 1);
    } finally {
      app.dispose();
    }
  });

  test(
    'switches the four quiet detail tabs and scrolls their content',
    () async {
      final catalog = _FakePubCatalog()
        ..searchResults.add(
          Future.value(
            PackageSearchPage(page: 1, packages: ['noir'], hasNextPage: false),
          ),
        )
        ..detailResults['noir'] = Future.value(examplePubPackage);
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
        width: 100,
        height: 32,
      );

      try {
        await _settle(app);
        app.mockInput
          ..pressTab()
          ..pressEnter();
        await _settle(app);

        expect(_render(app), contains('1 OVERVIEW'));
        expect(_render(app), contains('RUNS ON'));

        app.mockInput.pressArrow(ArrowDirection.right);
        await _settle(app);
        expect(_render(app), contains('PUBLISHED VERSIONS'));
        expect(
          _render(app),
          contains('https://pub.dev/api/archives/noir-0.0.1-alpha.1.tar.gz'),
        );

        app.mockInput.typeText('3');
        await _settle(app);
        expect(_render(app), contains('DIRECT DEPENDENCIES'));
        expect(
          _render(app),
          contains('git https://example.com/noir_plugin.git'),
        );

        app.mockInput.typeText('4');
        await _settle(app);
        expect(_render(app), contains('WEEKLY DOWNLOADS'));
        expect(_render(app), contains('▁'));

        final beforeScroll = _render(app);
        app.mockInput.pressPageDown();
        await _settle(app);
        expect(_render(app), isNot(beforeScroll));
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'shows empty and retryable search states without clearing the query',
    () async {
      final failedSearch = Completer<PackageSearchPage>();
      final catalog = _FakePubCatalog()
        ..searchResults.addAll([
          failedSearch.future,
          Future.value(
            PackageSearchPage(page: 1, packages: [], hasNextPage: false),
          ),
        ]);
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
        width: 100,
        height: 32,
      );

      try {
        await _settle(app);
        failedSearch.completeError(Exception('network unavailable'));
        await _settle(app);
        expect(_render(app), contains('Search unavailable'));
        expect(_render(app), contains('noir'));

        app.mockInput.pressEnter();
        await _settle(app);
        expect(catalog.searchCalls, hasLength(2));
        expect(catalog.searchCalls.last.query, 'noir');
        expect(_render(app), contains('No packages found'));
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'keeps the last successful results visible after a refresh error',
    () async {
      final failedRefresh = Completer<PackageSearchPage>();
      final catalog = _FakePubCatalog()
        ..searchResults.addAll([
          Future.value(
            PackageSearchPage(
              page: 1,
              packages: ['last_good_package'],
              hasNextPage: false,
            ),
          ),
          failedRefresh.future,
        ]);
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
        width: 100,
        height: 32,
      );

      try {
        await _settle(app);
        expect(_render(app), contains('last_good_package'));

        app.mockInput.pressEnter();
        await _settle(app);
        failedRefresh.completeError(Exception('refresh unavailable'));
        await _settle(app);

        expect(_render(app), contains('Search unavailable'));
        expect(_render(app), contains('last_good_package'));
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'returns focus to the query after results-focused empty search',
    () async {
      var quits = 0;
      final catalog = _FakePubCatalog()
        ..searchResults.addAll([
          Future.value(
            PackageSearchPage(
              page: 1,
              packages: const ['noir'],
              hasNextPage: false,
            ),
          ),
          Future.value(
            PackageSearchPage(page: 1, packages: const [], hasNextPage: false),
          ),
          Future.value(
            PackageSearchPage(
              page: 1,
              packages: const ['recovered'],
              hasNextPage: false,
            ),
          ),
        ]);
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () => quits++),
        width: 100,
        height: 32,
      );

      try {
        await _settle(app);
        app.mockInput
          ..pressTab()
          ..typeText('s');
        await _settle(app);
        expect(_render(app), contains('No packages found'));

        app.mockInput
          ..typeText('x')
          ..pressEnter();
        await _settle(app);

        expect(catalog.searchCalls, hasLength(3));
        expect(catalog.searchCalls.last.query, 'noirx');
        expect(_render(app), contains('recovered'));
        app.mockInput.pressEscape();
        expect(quits, 1);
      } finally {
        app.dispose();
      }
    },
  );

  test('reconciles catalog replacement and ignores the old response', () async {
    final oldSearch = Completer<PackageSearchPage>();
    final oldCatalog = _FakePubCatalog()..searchResults.add(oldSearch.future);
    final newCatalog = _FakePubCatalog()
      ..searchResults.add(
        Future.value(
          PackageSearchPage(
            page: 1,
            packages: const ['new_catalog_package'],
            hasNextPage: false,
          ),
        ),
      );
    late _CatalogHostState host;
    final app = createTuiTestApp(
      _CatalogHost(
        initialCatalog: oldCatalog,
        onReady: (state) => host = state,
      ),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      host.replaceCatalog(newCatalog);
      await _settle(app);

      expect(oldCatalog.closed, isTrue);
      expect(newCatalog.searchCalls, hasLength(1));
      expect(_render(app), contains('new_catalog_package'));

      oldSearch.complete(
        PackageSearchPage(
          page: 1,
          packages: const ['stale_old_package'],
          hasNextPage: false,
        ),
      );
      await _settle(app);

      expect(_render(app), contains('new_catalog_package'));
      expect(_render(app), isNot(contains('stale_old_package')));
    } finally {
      app.dispose();
    }
    expect(newCatalog.closed, isTrue);
  });

  test('pages forward and backward only from result focus', () async {
    final catalog = _FakePubCatalog()
      ..searchResults.addAll([
        Future.value(
          PackageSearchPage(page: 1, packages: ['page_one'], hasNextPage: true),
        ),
        Future.value(
          PackageSearchPage(
            page: 2,
            packages: ['page_two'],
            hasNextPage: false,
          ),
        ),
        Future.value(
          PackageSearchPage(
            page: 1,
            packages: ['page_one_again'],
            hasNextPage: true,
          ),
        ),
      ]);
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () {}),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      app.mockInput
        ..pressTab()
        ..typeText('n');
      await _settle(app);
      expect(catalog.searchCalls.last.page, 2);
      expect(_render(app), contains('page_two'));

      app.mockInput.typeText('p');
      await _settle(app);
      expect(catalog.searchCalls.last.page, 1);
      expect(_render(app), contains('page_one_again'));
    } finally {
      app.dispose();
    }
  });

  test('starts the next page at its first result', () async {
    final catalog = _FakePubCatalog()
      ..searchResults.addAll([
        Future.value(
          PackageSearchPage(
            page: 1,
            packages: ['page1_a', 'page1_b', 'page1_c'],
            hasNextPage: true,
          ),
        ),
        Future.value(
          PackageSearchPage(
            page: 2,
            packages: ['page2_a', 'page2_b', 'page2_c'],
            hasNextPage: false,
          ),
        ),
      ])
      ..detailResults['page2_a'] = Future.value(examplePubPackage);
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () {}),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      app.mockInput
        ..pressTab()
        ..pressArrow(ArrowDirection.down)
        ..pressArrow(ArrowDirection.down);
      await _settle(app);

      // Paging replaces the list, so the third-row highlight must not carry
      // over onto an unrelated package.
      app.mockInput.typeText('n');
      await _settle(app);
      expect(_render(app), contains('page2_a'));

      app.mockInput.pressEnter();
      await _settle(app);
      expect(catalog.detailCalls, ['page2_a']);
    } finally {
      app.dispose();
    }
  });

  test('names the requested page while that page is loading', () async {
    final secondPage = Completer<PackageSearchPage>();
    final catalog = _FakePubCatalog()
      ..searchResults.addAll([
        Future.value(
          PackageSearchPage(page: 1, packages: ['page_one'], hasNextPage: true),
        ),
        secondPage.future,
      ]);
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () {}),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      expect(_render(app), contains('PAGE  1'));

      app.mockInput
        ..pressTab()
        ..typeText('n');
      await _settle(app);
      // The page 2 request is still in flight; the header must not keep
      // advertising the page the user already left.
      expect(_render(app), contains('Searching pub.dev…'));
      expect(_render(app), contains('PAGE  2'));

      secondPage.completeError(Exception('page unavailable'));
      await _settle(app);
      // The last good page 1 results stay on screen, so the header follows.
      expect(_render(app), contains('Search unavailable'));
      expect(_render(app), contains('page_one'));
      expect(_render(app), contains('PAGE  1'));
    } finally {
      app.dispose();
    }
  });

  test('retries a failed package detail request', () async {
    final failedDetail = Completer<PubPackageSnapshot>();
    final catalog = _FakePubCatalog()
      ..searchResults.add(
        Future.value(
          PackageSearchPage(page: 1, packages: ['noir'], hasNextPage: false),
        ),
      )
      ..detailResults['noir'] = failedDetail.future;
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () {}),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      app.mockInput
        ..pressTab()
        ..pressEnter();
      await _settle(app);
      failedDetail.completeError(Exception('detail unavailable'));
      await _settle(app);
      expect(_render(app), contains('Package unavailable'));

      catalog.detailResults['noir'] = Future.value(examplePubPackage);
      app.mockInput.typeText('r');
      await _settle(app);
      expect(catalog.detailCalls, ['noir', 'noir']);
      expect(_render(app), contains('dart pub add noir'));
    } finally {
      app.dispose();
    }
  });
}

typedef _SearchCall = ({String query, int page, PackageSort sort});

final class _FakePubCatalog implements PubCatalog {
  final searchResults = <Future<PackageSearchPage>>[];
  final detailResults = <String, Future<PubPackageSnapshot>>{};
  final searchCalls = <_SearchCall>[];
  final detailCalls = <String>[];
  bool closed = false;

  @override
  Future<PackageSearchPage> search(
    String query, {
    int page = 1,
    PackageSort sort = PackageSort.top,
  }) {
    searchCalls.add((query: query, page: page, sort: sort));
    return searchResults.removeAt(0);
  }

  @override
  Future<PubPackageSnapshot> loadPackage(String name) {
    detailCalls.add(name);
    return detailResults[name]!;
  }

  @override
  void close() => closed = true;
}

final class _CatalogHost extends StatefulWidget {
  const _CatalogHost({required this.initialCatalog, required this.onReady});

  final PubCatalog initialCatalog;
  final ValueChanged<_CatalogHostState> onReady;

  @override
  State<_CatalogHost> createState() => _CatalogHostState();
}

final class _CatalogHostState extends State<_CatalogHost> {
  late PubCatalog _catalog;

  @override
  void initState() {
    super.initState();
    _catalog = widget.initialCatalog;
    widget.onReady(this);
  }

  void replaceCatalog(PubCatalog catalog) {
    setState(() => _catalog = catalog);
  }

  @override
  Widget build(BuildContext context) => PubSearchApp(catalog: _catalog);
}

String _render(TuiTestApp app) {
  app.pumpFrame();
  return app.captureFrame().toText();
}

typedef _PanelBorders = ({Color query, Color results});

/// Reads the border color of the query and result panels from one frame.
///
/// Both panels are stretched inside the same horizontal padding, so their
/// top-left corners are the only `┌` glyphs in that column.
_PanelBorders _panelBorders(TuiTestApp app) {
  app.pumpFrame();
  final frame = app.captureFrame();
  final corners = [
    for (var y = 0; y < frame.height; y++)
      if (frame.getChar(3, y) == '┌') y,
  ];
  expect(corners, hasLength(2), reason: 'expected query and result panels');
  return (
    query: frame.getForegroundColor(3, corners.first),
    results: frame.getForegroundColor(3, corners.last),
  );
}

Future<void> _settle(TuiTestApp app) async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  app.pumpFrame();
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
