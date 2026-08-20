import 'dart:async';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/pub_search/app.dart';
import '../../example/pub_search/catalog.dart';
import '../../example/pub_search/models.dart';
import '../../example/pub_search/theme.dart';
import '../helpers/tui_test_app.dart';
import 'pub_search_test_data.dart';

void main() {
  test('runs the initial search and opens the confirmed package', () async {
    final catalog = _FakePubCatalog()
      ..searchResults.add(_page(['noir', 'noir_router']))
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

  test(
    'single-clicking a package opens detail and hides the query cursor',
    () async {
      final catalog = _FakePubCatalog()
        ..searchResults.add(_page(['noir']))
        ..detailResults['noir'] = Future.value(examplePubPackage);
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
        width: 100,
        height: 32,
      );

      try {
        await _settle(app);
        final queryCursor = app.captureFrame().cursor;
        expect(queryCursor.visible, isTrue);
        expect(queryCursor.style, CursorStyle.block);
        expect(queryCursor.color, pubTheme.cursor);
        expect(queryCursor.blinking, isTrue);

        final result = app.captureFrame().findText('noir').last;
        app.mockMouse.click(result.x, result.y);
        await _settle(app);

        expect(catalog.detailCalls, ['noir']);
        expect(_render(app), contains('dart pub add noir'));
        expect(app.captureFrame().cursor.visible, isFalse);
      } finally {
        app.dispose();
      }
    },
  );

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
        _page(['searchable']),
        _page(['sorted']),
      ]);
    final app = createTuiTestApp(
      PubSearchApp(
        catalog: catalog,
        onQuit: () {},
        initialQuery: '',
        autoSearch: false,
      ),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);

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

  test('search help follows query and result focus', () async {
    final catalog = _FakePubCatalog()..searchResults.add(_page(['noir']));
    final app = createTuiTestApp(PubSearchApp(catalog: catalog, onQuit: () {}));

    try {
      await _settle(app);
      expect(
        _render(app),
        contains('Enter search  Tab results  Click SORT/FILTER  Esc quit'),
      );

      app.mockInput.pressTab();
      await _settle(app);

      expect(
        _render(app),
        contains('↑↓ select  Enter/click  / search  s/f/click  Esc quit'),
      );
    } finally {
      app.dispose();
    }
  });

  test('search help advertises only available page commands', () async {
    const cases = [
      (page: 1, hasNext: false, expected: null),
      (page: 1, hasNext: true, expected: 'n next'),
      (page: 2, hasNext: false, expected: 'p prev'),
      (page: 2, hasNext: true, expected: 'n/p page'),
    ];
    const pageCommands = ['n next', 'p prev', 'n/p page'];

    for (final testCase in cases) {
      final catalog = _FakePubCatalog()
        ..searchResults.add(
          _page(['noir'], page: testCase.page, hasNextPage: testCase.hasNext),
        );
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
      );

      try {
        await _settle(app);
        app.mockInput.pressTab();
        await _settle(app);
        final frame = _render(app);

        for (final command in pageCommands) {
          expect(
            frame,
            command == testCase.expected
                ? contains(command)
                : isNot(contains(command)),
          );
        }
      } finally {
        app.dispose();
      }
    }
  });

  test('search help omits Tab before any result control exists', () async {
    final initialSearch = Completer<PackageSearchPage>();
    final catalog = _FakePubCatalog()..searchResults.add(initialSearch.future);
    final app = createTuiTestApp(PubSearchApp(catalog: catalog, onQuit: () {}));

    try {
      await _settle(app);
      expect(_render(app), contains('Searching pub.dev…'));
      expect(_render(app), contains('Enter search   Esc quit'));
      expect(_render(app), isNot(contains('Tab results')));
      expect(_render(app), isNot(contains('SORT  ')));
      expect(_render(app), isNot(contains('FILTER  ')));

      initialSearch.completeError(Exception('search unavailable'));
      await _settle(app);

      expect(_render(app), contains('Search unavailable'));
      expect(_render(app), contains('Enter search   Esc quit'));
      expect(_render(app), isNot(contains('Tab results')));
      expect(_render(app), isNot(contains('SORT  ')));
      expect(_render(app), isNot(contains('FILTER  ')));
    } finally {
      app.dispose();
    }
  });

  test('focused suggestions advertise choosing instead of opening', () async {
    final catalog = _FakePubCatalog()
      ..suggestions.addAll(const [
        PubSuggestion.package('noir'),
        PubSuggestion.package('noir_router'),
      ]);
    final app = createTuiTestApp(
      PubSearchApp(
        catalog: catalog,
        onQuit: () {},
        initialQuery: '',
        autoSearch: false,
      ),
    );

    try {
      await _settle(app);
      app.mockInput.typeText('noi');
      await _settle(app);
      expect(
        _render(app),
        contains('Enter search   Tab suggestions   Esc quit'),
      );
      app.mockInput.pressTab();
      await _settle(app);

      expect(
        _render(app),
        contains('↑↓ select  Enter/click choose  / search  Esc quit'),
      );
      expect(_render(app), isNot(contains('Enter/click open')));
    } finally {
      app.dispose();
    }
  });

  test(
    'query stays focused when suggestions appear after visiting results',
    () async {
      final catalog = _FakePubCatalog()
        ..searchResults.addAll([
          _page(['kept_package'], hasNextPage: true),
          _page(['paged_away']),
        ])
        ..detailResults['kept_package'] = Future.value(examplePubPackage)
        ..suggestions.addAll(const [
          PubSuggestion.package('http'),
          PubSuggestion.package('html'),
        ]);
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
        width: 100,
        height: 32,
      );

      try {
        await _settle(app);
        final queryFocused = _panelBorders(app).query;

        app.mockInput
          ..pressTab()
          ..pressEnter();
        await _settle(app);
        app.mockInput.pressEscape();
        await _settle(app);
        app.mockInput.typeText('/');
        await _settle(app);

        // Clear the seeded "noir" query, then type a prefix that yields
        // suggestions. If the suggestion Select autofocuses, `p` pages.
        for (var i = 0; i < 4; i++) {
          app.mockInput.pressBackspace();
        }
        app.mockInput.typeText('http');
        await _settle(app);

        expect(_render(app), contains('http'));
        expect(_render(app), contains('SUGGESTIONS'));
        expect(_render(app), isNot(contains('SORT  TOP')));
        expect(_render(app), isNot(contains('PAGE  1')));
        expect(_render(app), isNot(contains('paged_away')));
        expect(catalog.searchCalls, hasLength(1));
        expect(_panelBorders(app).query, queryFocused);
      } finally {
        app.dispose();
      }
    },
  );

  test('waits for three characters before showing suggestions', () async {
    final catalog = _FakePubCatalog()
      ..suggestions.addAll(const [
        PubSuggestion.package('noir'),
        PubSuggestion.package('noir_router'),
      ]);
    final app = createTuiTestApp(
      PubSearchApp(
        catalog: catalog,
        onQuit: () {},
        initialQuery: '',
        autoSearch: false,
      ),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      app.mockInput.typeText('n');
      await _settle(app);
      expect(_render(app), isNot(contains('SUGGESTIONS')));
      expect(catalog.completeCalls, isEmpty);

      app.mockInput.typeText('o');
      await _settle(app);
      expect(_render(app), isNot(contains('SUGGESTIONS')));
      expect(catalog.completeCalls, isEmpty);

      app.mockInput.typeText('i');
      await _settle(app);
      expect(catalog.completeCalls, ['noi']);
      expect(_render(app), contains('SUGGESTIONS'));
      expect(_render(app), contains('noir_router'));
    } finally {
      app.dispose();
    }
  });

  test('shows prefix suggestions while the query is being edited', () async {
    final catalog = _FakePubCatalog()
      ..suggestions.addAll(const [
        PubSuggestion.package('noir'),
        PubSuggestion.package('noir_router'),
        PubSuggestion.topic('terminal', 12),
      ]);
    final app = createTuiTestApp(
      PubSearchApp(
        catalog: catalog,
        onQuit: () {},
        initialQuery: '',
        autoSearch: false,
      ),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      app.mockInput.typeText('noi');
      await _settle(app);

      expect(catalog.completeCalls, isNotEmpty);
      expect(catalog.completeCalls.last, 'noi');
      expect(_render(app), contains('noir_router'));
      expect(_render(app), contains('SUGGESTIONS'));
      expect(catalog.searchCalls, isEmpty);
    } finally {
      app.dispose();
    }
  });

  test('a selected topic applies only to the next search', () async {
    final catalog = _FakePubCatalog()
      ..suggestions.add(const PubSuggestion.topic('terminal', 12))
      ..searchResults.addAll([
        _page(['topic_result']),
        _page(['plain_result']),
      ]);
    final app = createTuiTestApp(
      PubSearchApp(
        catalog: catalog,
        onQuit: () {},
        initialQuery: '',
        autoSearch: false,
      ),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      app.mockInput.typeText('ter');
      await _settle(app);
      app.mockInput
        ..pressTab()
        ..pressEnter();
      await _settle(app);

      expect(catalog.searchCalls.single.topic, 'terminal');
      expect(_render(app), contains('topic_result'));

      app.mockInput
        ..typeText('/')
        ..pressEnter();
      await _settle(app);

      expect(catalog.searchCalls, hasLength(2));
      expect(catalog.searchCalls.last.topic, isNull);
      expect(_render(app), contains('plain_result'));
    } finally {
      app.dispose();
    }
  });

  test('a selected topic survives result continuations', () async {
    final catalog = _FakePubCatalog()
      ..suggestions.add(const PubSuggestion.topic('terminal', 12))
      ..searchResults.addAll([
        _page(['topic_result'], hasNextPage: true),
        _page(['sorted_topic_result'], hasNextPage: true),
        _page(['filtered_topic_result'], hasNextPage: true),
        _page(['topic_page_two'], page: 2),
      ]);
    final app = createTuiTestApp(
      PubSearchApp(
        catalog: catalog,
        onQuit: () {},
        initialQuery: '',
        autoSearch: false,
      ),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      app.mockInput.typeText('ter');
      await _settle(app);
      app.mockInput
        ..pressTab()
        ..pressEnter();
      await _settle(app);

      app.mockInput.typeText('s');
      await _settle(app);
      app.mockInput.typeText('f');
      await _settle(app);
      app.mockInput.typeText('n');
      await _settle(app);

      expect(catalog.searchCalls, hasLength(4));
      expect(
        catalog.searchCalls.map((call) => call.topic),
        everyElement('terminal'),
      );
      expect(catalog.searchCalls[1].sort, PackageSort.text);
      expect(catalog.searchCalls[2].filter, PackageSearchFilter.dart);
      expect(catalog.searchCalls[3].page, 2);
      expect(_render(app), contains('TOPIC  terminal'));
    } finally {
      app.dispose();
    }
  });

  test('retrying a failed topic search preserves the topic', () async {
    final catalog = _FakePubCatalog()
      ..suggestions.add(const PubSuggestion.topic('terminal', 12))
      ..searchResults.addAll([
        Future<PackageSearchPage>.error(Exception('topic unavailable'))
          ..ignore(),
        _page(['topic_recovered']),
      ]);
    final app = createTuiTestApp(
      PubSearchApp(
        catalog: catalog,
        onQuit: () {},
        initialQuery: '',
        autoSearch: false,
      ),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      app.mockInput.typeText('ter');
      await _settle(app);
      app.mockInput
        ..pressTab()
        ..pressEnter();
      await _settle(app);
      expect(_render(app), contains('Search unavailable'));

      app.mockInput.pressEnter();
      await _settle(app);

      expect(catalog.searchCalls, hasLength(2));
      expect(catalog.searchCalls.map((call) => call.topic), [
        'terminal',
        'terminal',
      ]);
      expect(_render(app), contains('topic_recovered'));
    } finally {
      app.dispose();
    }
  });

  test('result shortcuts do not fire while suggestions own focus', () async {
    final catalog = _FakePubCatalog()
      ..suggestions.addAll(const [
        PubSuggestion.package('noira'),
        PubSuggestion.package('noira_router'),
      ])
      ..searchResults.add(_page(['existing_result'], hasNextPage: true));
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () {}),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      final query = app.captureFrame().findText('noir').first;
      app.mockMouse.click(query.x + 4, query.y);
      await _settle(app);
      app.mockInput.typeText('a');
      await _settle(app);
      app.mockInput.pressTab();
      await _settle(app);
      expect(_render(app), contains('SUGGESTIONS'));

      app.mockInput
        ..typeText('s')
        ..typeText('f')
        ..typeText('n')
        ..typeText('p');
      await _settle(app);

      expect(catalog.searchCalls, hasLength(1));
      expect(_render(app), contains('SUGGESTIONS'));
    } finally {
      app.dispose();
    }
  });

  test(
    'returning to an unchanged query reveals completed suggestions',
    () async {
      final completion = Completer<List<PubSuggestion>>();
      final catalog = _FakePubCatalog()
        ..completionResult = completion.future
        ..searchResults.add(_page(['existing_result']));
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
        width: 100,
        height: 32,
      );

      try {
        await _settle(app);
        final query = app.captureFrame().findText('noir').first;
        app.mockMouse.click(query.x + 4, query.y);
        await _settle(app);
        app.mockInput.typeText('x');
        await _settle(app);
        app.mockInput.pressTab();
        await _settle(app);

        completion.complete(const [PubSuggestion.package('noirx_package')]);
        await _settle(app);
        expect(_render(app), contains('RESULTS'));
        expect(_render(app), isNot(contains('SUGGESTIONS')));

        final editedQuery = app.captureFrame().findText('noirx').first;
        app.mockMouse.click(editedQuery.x + 5, editedQuery.y);
        await _settle(app);

        expect(_render(app), contains('SUGGESTIONS'));
        expect(_render(app), contains('noirx_package'));
      } finally {
        app.dispose();
      }
    },
  );

  test('the slash shortcut focuses search without editing the query', () async {
    final catalog = _FakePubCatalog()..searchResults.add(_page(['noir']));
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () {}),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      app.mockInput
        ..pressTab()
        ..typeText('/');
      await _settle(app);

      expect(_render(app), isNot(contains('noir/')));
      expect(_render(app), contains('Enter search  Tab results'));
    } finally {
      app.dispose();
    }
  });

  test('confirming a package suggestion opens that package', () async {
    final catalog = _FakePubCatalog()
      ..suggestions.addAll(const [
        PubSuggestion.package('noir'),
        PubSuggestion.package('noir_router'),
      ])
      ..detailResults['noir'] = Future.value(examplePubPackage);
    final app = createTuiTestApp(
      PubSearchApp(
        catalog: catalog,
        onQuit: () {},
        initialQuery: '',
        autoSearch: false,
      ),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      app.mockInput.typeText('noi');
      await _settle(app);
      app.mockInput
        ..pressTab()
        ..pressEnter();
      await _settle(app);

      expect(catalog.detailCalls, ['noir']);
      expect(_render(app), contains('dart pub add noir'));
    } finally {
      app.dispose();
    }
  });

  test('idle search is query-first and does not paint result chrome', () async {
    final app = createTuiTestApp(
      PubSearchApp(
        catalog: _FakePubCatalog(),
        onQuit: () {},
        initialQuery: '',
        autoSearch: false,
      ),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      final frame = _render(app);
      expect(frame, contains('PUB / FIND'));
      expect(frame, contains('LIVE PUB.DEV'));
      expect(frame, isNot(contains('OFFLINE DATA')));
      expect(frame, contains('Press Enter to search pub.dev.'));
      expect(frame, isNot(contains('SORT')));
      expect(frame, isNot(contains('FILTER')));
      expect(frame, isNot(contains('PAGE  ')));
      expect(frame, isNot(contains('Type a query and press Enter.')));
    } finally {
      app.dispose();
    }
  });

  test(
    'queued auto-search does not paint idle copy against a prefilled query',
    () async {
      final catalog = _FakePubCatalog()..searchResults.add(_page(['noir']));
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
        width: 100,
        height: 32,
      );

      try {
        app.pumpFrame();
        final frame = app.captureFrame().toText();
        expect(frame, contains('noir'));
        expect(frame, isNot(contains('Type a query and press Enter.')));
        expect(frame, contains('Searching pub.dev…'));
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'controller selection changes do not cover initial search loading',
    () async {
      final pendingSearch = Completer<PackageSearchPage>();
      final catalog = _FakePubCatalog()
        ..suggestions.add(const PubSuggestion.package('noir'))
        ..searchResults.add(pendingSearch.future);
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
      );

      try {
        await _settle(app);

        final frame = _render(app);
        expect(frame, contains('Searching pub.dev…'));
        expect(frame, isNot(contains('SUGGESTIONS')));
        expect(catalog.completeCalls, isEmpty);
        final captured = app.captureFrame();
        expect(
          captured.findText('Searching pub.dev…').single.y,
          captured.findText('RESULTS').single.y + 1,
        );
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'cycles filter on the search surface and sends it to the catalog',
    () async {
      final catalog = _FakePubCatalog()
        ..searchResults.addAll([
          _page(['noir']),
          _page(['filtered']),
        ]);
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
        width: 100,
        height: 32,
      );

      try {
        await _settle(app);
        expect(_render(app), contains('FILTER  ANY'));

        app.mockInput
          ..pressTab()
          ..typeText('f');
        await _settle(app);

        expect(_render(app), contains('FILTER  DART'));
        expect(catalog.searchCalls.last.filter, PackageSearchFilter.dart);
        expect(_render(app), contains('filtered'));
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'clicking Sort cycles the live query and highlights its value',
    () async {
      final catalog = _FakePubCatalog()
        ..searchResults.addAll([
          _page(['noir']),
          _page(['sorted']),
        ]);
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
        width: 100,
        height: 32,
      );

      try {
        await _settle(app);
        final sort = app.captureFrame().findText('SORT').last;
        app.mockMouse.click(sort.x, sort.y);
        await _settle(app);

        expect(catalog.searchCalls, hasLength(2));
        expect(catalog.searchCalls.last.sort, PackageSort.text);
        expect(_render(app), contains('SORT  TEXT'));
        expect(_render(app), contains('sorted'));
        final style = _tabStyle(app, 'TEXT');
        expect(style.background, _painted(pubTheme.accent));
        expect(style.foreground, _painted(pubTheme.accentForeground));
        expect(style.bold, isTrue);
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'clicking Filter cycles the live query and highlights its value',
    () async {
      final catalog = _FakePubCatalog()
        ..searchResults.addAll([
          _page(['noir']),
          _page(['filtered']),
        ]);
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
        width: 100,
        height: 32,
      );

      try {
        await _settle(app);
        final filter = app.captureFrame().findText('FILTER').last;
        app.mockMouse.click(filter.x, filter.y);
        await _settle(app);

        expect(catalog.searchCalls, hasLength(2));
        expect(catalog.searchCalls.last.filter, PackageSearchFilter.dart);
        expect(_render(app), contains('FILTER  DART'));
        expect(_render(app), contains('filtered'));
        final style = _tabStyle(app, 'DART');
        expect(style.background, _painted(pubTheme.accent));
        expect(style.foreground, _painted(pubTheme.accentForeground));
        expect(style.bold, isTrue);
      } finally {
        app.dispose();
      }
    },
  );

  test('moves the panel focus highlight when Tab changes focus', () async {
    final catalog = _FakePubCatalog()..searchResults.add(_page(['noir']));
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
      expect(app.captureFrame().cursor.visible, isFalse);
    } finally {
      app.dispose();
    }
  });

  test('detail panel highlights while its scroll view holds focus', () async {
    final catalog = _FakePubCatalog()
      ..searchResults.add(_page(['noir']))
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

      final border = _detailPanelBorder(app);
      expect(border, Color.fromHex(pubTheme.accent.toHex()));
      expect(border, isNot(Color.fromHex(pubTheme.border.toHex())));
    } finally {
      app.dispose();
    }
  });

  test('keeps a results panel at 60x16', () async {
    final catalog = _FakePubCatalog()
      ..searchResults.add(_page(['visible_pkg']));
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () {}),
      width: 60,
      height: 16,
    );

    try {
      await _settle(app);
      final frame = _render(app);
      expect(frame, contains('PACKAGES'));
      expect(frame, contains('visible_pkg'));
      expect(frame, isNot(contains('RangeError')));
    } finally {
      app.dispose();
    }
  });

  test('keeps paged result help and a row visible at 60x16', () async {
    final catalog = _FakePubCatalog()
      ..searchResults.add(_page(['visible_pkg'], hasNextPage: true));
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () {}),
      width: 60,
      height: 16,
    );

    try {
      await _settle(app);
      app.mockInput.pressTab();
      await _settle(app);

      final frame = app.captureFrame();
      final helpStart = frame.findText('↑↓ select').single;
      final helpEnd = frame.findText('Esc').single;
      expect(helpEnd.y, helpStart.y);
      expect(frame.toText(), contains('visible_pkg'));
    } finally {
      app.dispose();
    }
  });

  test('keeps a long topic and page status readable at 60 columns', () async {
    const topic = 'terminal-user-interface-tooling';
    final catalog = _FakePubCatalog()
      ..suggestions.add(const PubSuggestion.topic(topic, 12))
      ..searchResults.add(_page(['topic_result']));
    final app = createTuiTestApp(
      PubSearchApp(
        catalog: catalog,
        onQuit: () {},
        initialQuery: '',
        autoSearch: false,
      ),
      width: 60,
      height: 16,
    );

    try {
      await _settle(app);
      app.mockInput.typeText('ter');
      await _settle(app);
      app.mockInput
        ..pressTab()
        ..pressEnter();
      await _settle(app);

      final frame = app.captureFrame();
      expect(frame.toText(), contains('TOPIC'));
      expect(frame.toText(), contains('PAGE  1'));
      expect(
        frame.findText('TOPIC').single.y,
        frame.findText('PAGE  1').single.y,
      );
    } finally {
      app.dispose();
    }
  });

  test('keeps result rows inside the panel at 80x24', () async {
    final catalog = _FakePubCatalog()
      ..searchResults.add(
        _page(List.generate(15, (index) => 'package_$index')),
      );
    final app = createTuiTestApp(PubSearchApp(catalog: catalog, onQuit: () {}));

    try {
      await _settle(app);
      final frame = app.captureFrame();
      final bottomBorder = [
        for (var y = 0; y < frame.height; y++)
          if (frame.getChar(2, y) == '└') y,
      ].last;
      final paintedResults = [
        for (var index = 0; index < 15; index++)
          ...frame.findText('package_$index'),
      ];

      expect(paintedResults, isNotEmpty);
      expect(
        paintedResults.every((position) => position.y < bottomBorder),
        isTrue,
      );
    } finally {
      app.dispose();
    }
  });

  test('keeps search help on one row at 80 columns', () async {
    final catalog = _FakePubCatalog()..searchResults.add(_page(['noir']));
    final app = createTuiTestApp(PubSearchApp(catalog: catalog, onQuit: () {}));

    try {
      await _settle(app);
      final frame = app.captureFrame();
      final help = frame.findText('Enter search').single;
      final quit = frame.findText('quit').single;

      expect(quit.y, help.y);
    } finally {
      app.dispose();
    }
  });

  test('Escape returns to results before requesting quit', () async {
    var quits = 0;
    final catalog = _FakePubCatalog()
      ..searchResults.add(_page(['noir']))
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
    'Escape exits through the tree when no quit callback is supplied',
    () async {
      final app = createTuiTestApp(
        PubSearchApp(
          catalog: _FakePubCatalog(),
          initialQuery: '',
          autoSearch: false,
        ),
      );

      try {
        await _settle(app);
        app.mockInput.pressEscape();
        await _settle(app);

        expect(app.exitRequests, [0]);
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'switches the four quiet detail tabs and scrolls their content',
    () async {
      final catalog = _FakePubCatalog()
        ..searchResults.add(_page(['noir']))
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
        final overview = _tabStyle(app, '1 OVERVIEW');
        expect(overview.background, _painted(pubTheme.accent));
        expect(overview.foreground, _painted(pubTheme.accentForeground));
        expect(overview.bold, isTrue);
        expect(
          _tabStyle(app, '2 VERSIONS').background,
          isNot(_painted(pubTheme.accent)),
        );

        app.mockInput.pressArrow(ArrowDirection.right);
        await _settle(app);
        expect(_render(app), contains('2 VERSIONS'));
        expect(
          _tabStyle(app, '1 OVERVIEW').background,
          isNot(_painted(pubTheme.accent)),
        );
        final versions = _tabStyle(app, '2 VERSIONS');
        expect(versions.background, _painted(pubTheme.accent));
        expect(versions.foreground, _painted(pubTheme.accentForeground));
        expect(versions.bold, isTrue);
        expect(_render(app), contains('PUBLISHED VERSIONS'));
        expect(_render(app), isNot(contains('documented (documented)')));
        expect(
          _render(app),
          contains('https://pub.dev/api/archives/noir-0.0.1-alpha.1.tar.gz'),
        );

        app.mockInput.typeText('3');
        await _settle(app);
        expect(_render(app), contains('3 DEPENDENCIES'));
        expect(_render(app), contains('DIRECT DEPENDENCIES'));
        expect(
          _render(app),
          contains('git https://example.com/noir_plugin.git'),
        );

        app.mockInput.typeText('4');
        await _settle(app);
        expect(_render(app), contains('4 HEALTH'));
        expect(_render(app), contains('PUB SCORE'));
        expect(_render(app), contains('WEEKLY DOWNLOADS'));
        expect(_render(app), contains('▁'));
        expect(_render(app), isNot(contains('RECENT ')));
        expect(_render(app), isNot(contains('T00:00:00')));

        app.mockInput.pressArrow(ArrowDirection.left);
        await _settle(app);
        expect(_render(app), contains('3 DEPENDENCIES'));
        expect(_render(app), contains('DIRECT DEPENDENCIES'));

        app.mockInput.pressArrow(ArrowDirection.right);
        await _settle(app);
        expect(_render(app), contains('4 HEALTH'));

        final beforeScroll = _render(app);
        app.mockInput.pressPageDown();
        await _settle(app);
        expect(_render(app), isNot(beforeScroll));
      } finally {
        app.dispose();
      }
    },
  );

  test('health omits score progress when the maximum is zero', () async {
    final package = PubPackageSnapshot(
      name: 'zero_score',
      version: '1.0.0',
      description: 'Score data with no available maximum.',
      published: DateTime.utc(2026),
      grantedPoints: 1,
      maxPoints: 0,
    );
    final catalog = _FakePubCatalog()
      ..searchResults.add(_page(['zero_score']))
      ..detailResults['zero_score'] = Future.value(package);
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
      app.mockInput.typeText('4');
      await _settle(app);

      expect(_render(app), contains('1 / 0'));
      expect(_render(app), isNot(contains('█')));
    } finally {
      app.dispose();
    }
  });

  test('keeps detail controls on one row at 60 columns', () async {
    final catalog = _FakePubCatalog()
      ..searchResults.add(_page(['noir']))
      ..detailResults['noir'] = Future.value(examplePubPackage);
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () {}),
      width: 60,
      height: 16,
    );

    try {
      await _settle(app);
      app.mockInput
        ..pressTab()
        ..pressEnter();
      await _settle(app);

      final frame = app.captureFrame();
      final start = frame.findText('←→/1–4/click tabs').single;
      final end = frame.findText('Esc').last;
      expect(end.y, start.y);
      expect(frame.toText(), contains('DOWNLOADS 30D'));
      expect(frame.toText(), contains('PACKAGE PROFILE'));
    } finally {
      app.dispose();
    }
  });

  test('clicking a detail tab selects that section', () async {
    final catalog = _FakePubCatalog()
      ..searchResults.add(_page(['noir']))
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

      expect(
        _render(app),
        contains('←→/1–4/click tabs  ↑↓/PgUp/PgDn  / search  Esc back'),
      );

      const cases = [
        ('1 OVERVIEW', 'PACKAGE PROFILE', '2'),
        ('2 VERSIONS', 'PUBLISHED VERSIONS', '1'),
        ('3 DEPENDENCIES', 'DIRECT DEPENDENCIES', '1'),
        ('4 HEALTH', 'PUB SCORE', '1'),
      ];
      for (final (label, content, alternateTab) in cases) {
        for (final rightPadding in [false, true]) {
          app.mockInput.typeText(alternateTab);
          await _settle(app);
          final tab = app.captureFrame().findText(label).single;
          final paddingX = rightPadding ? tab.x + label.length : tab.x - 1;
          app.mockMouse.click(paddingX, tab.y);
          await _settle(app);

          expect(_render(app), contains(content));
          final frame = app.captureFrame();
          final style = _tabStyle(app, label);
          expect(style.background, _painted(pubTheme.accent));
          expect(style.foreground, _painted(pubTheme.accentForeground));
          expect(style.bold, isTrue);
          expect(
            frame.getBackgroundColor(paddingX, tab.y),
            _painted(pubTheme.accent),
          );
          expect(frame.cursor.visible, isFalse);
        }
      }
    } finally {
      app.dispose();
    }
  });

  test(
    'shows empty and retryable search states without clearing the query',
    () async {
      final failedSearch = Completer<PackageSearchPage>();
      final catalog = _FakePubCatalog()
        ..searchResults.addAll([failedSearch.future, _page([])]);
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
        expect(_render(app), contains('Enter search  Tab controls  Esc quit'));
        expect(_render(app), isNot(contains('Tab results')));
        expect(_render(app), contains('SORT  TOP'));
        expect(_render(app), contains('FILTER  ANY'));
      } finally {
        app.dispose();
      }
    },
  );

  test('empty filtered results keep keyboard controls to escape', () async {
    final catalog = _FakePubCatalog()
      ..searchResults.addAll([
        _page(['all_result']),
        _page([]),
        _page(['flutter_result']),
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
        ..typeText('f');
      await _settle(app);

      expect(_render(app), contains('No packages found'));
      expect(_render(app), contains('FILTER  DART'));
      expect(_render(app), contains('Tab controls'));

      // Empty results return focus to the query. Tab reaches Sort, then
      // Filter; Enter activates the same cycle action as a left click.
      app.mockInput.pressTab();
      await _settle(app);
      expect(
        _render(app),
        contains('Enter/Space cycle sort  Tab filter  Esc quit'),
      );

      app.mockInput.pressTab();
      await _settle(app);
      expect(
        _render(app),
        contains('Enter/Space cycle filter  Tab search  Esc quit'),
      );

      app.mockInput.pressEnter();
      await _settle(app);

      expect(catalog.searchCalls.map((call) => call.filter), [
        PackageSearchFilter.any,
        PackageSearchFilter.dart,
        PackageSearchFilter.flutter,
      ]);
      expect(_render(app), contains('flutter_result'));
    } finally {
      app.dispose();
    }
  });

  test(
    'keeps the last successful results visible after a refresh error',
    () async {
      final failedRefresh = Completer<PackageSearchPage>();
      final catalog = _FakePubCatalog()
        ..searchResults.addAll([
          _page(['last_good_package']),
          failedRefresh.future,
          _page(['recovered_package']),
        ]);
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
        width: 100,
        height: 32,
      );

      try {
        await _settle(app);
        expect(_render(app), contains('last_good_package'));

        app.mockInput
          ..pressTab()
          ..typeText('s');
        await _settle(app);
        failedRefresh.completeError(Exception('refresh unavailable'));
        await _settle(app);

        expect(_render(app), contains('Search unavailable'));
        expect(_render(app), contains('last_good_package'));
        expect(app.captureFrame().cursor.visible, isTrue);

        app.mockInput.pressEnter();
        await _settle(app);

        expect(catalog.searchCalls, hasLength(3));
        expect(_render(app), contains('recovered_package'));
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
          _page(['noir']),
          _page([]),
          _page(['recovered']),
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
      ..searchResults.add(_page(['new_catalog_package']));
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
        _page(['page_one'], hasNextPage: true),
        _page(['page_two'], page: 2),
        _page(['page_one_again'], hasNextPage: true),
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

  test(
    'paging continues the displayed query after an unsubmitted edit',
    () async {
      final catalog = _FakePubCatalog()
        ..searchResults.addAll([
          _page(['page_one'], hasNextPage: true),
          _page(['page_two'], page: 2),
        ]);
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
        width: 100,
        height: 32,
      );

      try {
        await _settle(app);
        final query = app.captureFrame().findText('noir').first;
        app.mockMouse.click(query.x + 4, query.y);
        await _settle(app);
        app.mockInput.typeText('x');
        await _settle(app);

        app.mockInput
          ..pressTab()
          ..typeText('n');
        await _settle(app);

        expect(catalog.searchCalls, hasLength(2));
        expect(catalog.searchCalls.last.query, 'noir');
        expect(catalog.searchCalls.last.page, 2);
        expect(_render(app), contains('page_two'));
      } finally {
        app.dispose();
      }
    },
  );

  test('starts the next page at its first result', () async {
    final catalog = _FakePubCatalog()
      ..searchResults.addAll([
        _page(['page1_a', 'page1_b', 'page1_c'], hasNextPage: true),
        _page(['page2_a', 'page2_b', 'page2_c'], page: 2),
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
        _page(['page_one'], hasNextPage: true),
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
      // Last results stay mounted so result-scoped shortcuts keep working.

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

  test(
    'keeps last results and sort shortcuts while a refresh is loading',
    () async {
      final refresh = Completer<PackageSearchPage>();
      final afterRefresh = Completer<PackageSearchPage>();
      final catalog = _FakePubCatalog()
        ..searchResults.addAll([
          _page(['kept_package']),
          refresh.future,
          afterRefresh.future,
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
          ..typeText('s');
        await _settle(app);

        expect(_render(app), contains('Searching pub.dev…'));
        expect(_render(app), contains('kept_package'));
        expect(_render(app), contains('SORT  TEXT'));

        // A second `s` used to be ignored: loading unmounted the Select, so
        // `_resultsFocus.hasFocus` was false and the key was dropped.
        app.mockInput.typeText('s');
        await _settle(app);
        expect(catalog.searchCalls.map((call) => call.sort), [
          PackageSort.top,
          PackageSort.text,
          PackageSort.created,
        ]);
        expect(_render(app), contains('SORT  CREATED'));
        expect(_render(app), contains('kept_package'));
      } finally {
        app.dispose();
      }
    },
  );

  test('opening a package abandons an in-flight refresh', () async {
    final refresh = Completer<PackageSearchPage>();
    final catalog = _FakePubCatalog()
      ..searchResults.addAll([
        _page(['kept_package']),
        refresh.future,
      ])
      ..detailResults['kept_package'] = Future.value(examplePubPackage);
    final app = createTuiTestApp(
      PubSearchApp(catalog: catalog, onQuit: () {}),
      width: 100,
      height: 32,
    );

    try {
      await _settle(app);
      app.mockInput
        ..pressTab()
        ..typeText('s');
      await _settle(app);
      expect(_render(app), contains('Searching pub.dev…'));

      app.mockInput.pressEnter();
      await _settle(app);
      app.mockInput.pressEscape();
      await _settle(app);

      expect(_render(app), contains('kept_package'));
      expect(_render(app), isNot(contains('Searching pub.dev…')));
      expect(_render(app), contains('SORT  TOP'));
    } finally {
      app.dispose();
    }
  });

  test(
    'opening last results clears a failed refresh before returning',
    () async {
      final failedRefresh = Completer<PackageSearchPage>();
      final catalog = _FakePubCatalog()
        ..searchResults.addAll([
          _page(['last_good_package']),
          failedRefresh.future,
        ])
        ..detailResults['last_good_package'] = Future.value(examplePubPackage);
      final app = createTuiTestApp(
        PubSearchApp(catalog: catalog, onQuit: () {}),
        width: 100,
        height: 32,
      );

      try {
        await _settle(app);
        app.mockInput
          ..pressTab()
          ..typeText('s');
        await _settle(app);
        failedRefresh.completeError(Exception('refresh unavailable'));
        await _settle(app);

        app.mockInput
          ..pressTab()
          ..pressEnter();
        await _settle(app);
        expect(_render(app), contains('PACKAGE PROFILE'));

        app.mockInput.pressEscape();
        await _settle(app);

        expect(_render(app), contains('last_good_package'));
        expect(_render(app), isNot(contains('Search unavailable')));
        expect(_render(app), isNot(contains('Unknown error')));
      } finally {
        app.dispose();
      }
    },
  );

  test('opening a package restores the last good page number', () async {
    final secondPage = Completer<PackageSearchPage>();
    final catalog = _FakePubCatalog()
      ..searchResults.addAll([
        _page(['page_one'], hasNextPage: true),
        secondPage.future,
      ])
      ..detailResults['page_one'] = Future.value(examplePubPackage);
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
      expect(_render(app), contains('PAGE  2'));

      app.mockInput.pressEnter();
      await _settle(app);
      app.mockInput.pressEscape();
      await _settle(app);

      expect(_render(app), contains('page_one'));
      expect(_render(app), contains('PAGE  1'));
      expect(_render(app), isNot(contains('Searching pub.dev…')));
    } finally {
      app.dispose();
    }
  });

  test('retries a failed package detail request', () async {
    final failedDetail = Completer<PubPackageSnapshot>();
    final catalog = _FakePubCatalog()
      ..searchResults.add(_page(['noir']))
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

  test('keeps last results when the refresh fails before a frame', () async {
    // A rejection that resolves in a microtask never paints the intervening
    // loading frame, so the result list is rebuilt straight from ready into
    // the error layout's LAST RESULTS branch.
    // `ignore()` only suppresses the unhandled-error report for a future that
    // is already failed when the app awaits it; the await still throws.
    final refreshFailure = Future<PackageSearchPage>.error(
      Exception('refresh unavailable'),
    )..ignore();
    final catalog = _FakePubCatalog()
      ..searchResults.addAll([
        _page(['last_good_package']),
        refreshFailure,
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

      expect(_render(app), contains('Search unavailable'));
      expect(_render(app), contains('last_good_package'));
    } finally {
      app.dispose();
    }
  });
}

typedef _SearchCall = ({
  String query,
  int page,
  PackageSort sort,
  PackageSearchFilter filter,
  String? topic,
});

final class _FakePubCatalog implements PubCatalog {
  final searchResults = <Future<PackageSearchPage>>[];
  final detailResults = <String, Future<PubPackageSnapshot>>{};
  final suggestions = <PubSuggestion>[];
  final searchCalls = <_SearchCall>[];
  final completeCalls = <String>[];
  Future<List<PubSuggestion>>? completionResult;
  final detailCalls = <String>[];
  bool closed = false;

  @override
  Future<PackageSearchPage> search(
    String query, {
    int page = 1,
    PackageSort sort = PackageSort.top,
    PackageSearchFilter filter = PackageSearchFilter.any,
    String? topic,
  }) {
    searchCalls.add((
      query: query,
      page: page,
      sort: sort,
      filter: filter,
      topic: topic,
    ));
    return searchResults.removeAt(0);
  }

  @override
  Future<List<PubSuggestion>> complete(String prefix) async {
    completeCalls.add(prefix);
    final completionResult = this.completionResult;
    if (completionResult != null) return completionResult;
    final needle = prefix.trim().toLowerCase();
    return suggestions
        .where((item) => item.name.toLowerCase().startsWith(needle))
        .toList(growable: false);
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

Future<PackageSearchPage> _page(
  List<String> packages, {
  int page = 1,
  bool hasNextPage = false,
}) => Future.value(
  PackageSearchPage(page: page, packages: packages, hasNextPage: hasNextPage),
);

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
      if (frame.getChar(2, y) == '┌') y,
  ];
  expect(corners, hasLength(2), reason: 'expected query and result panels');
  return (
    query: frame.getForegroundColor(2, corners.first),
    results: frame.getForegroundColor(2, corners.last),
  );
}

Color _detailPanelBorder(TuiTestApp app) {
  app.pumpFrame();
  final frame = app.captureFrame();
  final corners = [
    for (var y = 0; y < frame.height; y++)
      if (frame.getChar(2, y) == '┌') y,
  ];
  expect(corners, isNotEmpty, reason: 'expected a detail content panel');
  return frame.getForegroundColor(2, corners.last);
}

typedef _TabStyle = ({Color foreground, Color background, bool bold});

_TabStyle _tabStyle(TuiTestApp app, String label) {
  app.pumpFrame();
  final frame = app.captureFrame();
  final position = frame.findText(label).single;
  final cell = frame.getCell(position.x, position.y);
  return (
    foreground: frame.getForegroundColor(position.x, position.y),
    background: frame.getBackgroundColor(position.x, position.y),
    bold: cell.isBold,
  );
}

Color _painted(Color color) => Color.fromHex(color.toHex());

Future<void> _settle(TuiTestApp app) async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  app.pumpFrame();
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
