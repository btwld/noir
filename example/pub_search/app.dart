import 'dart:async';
import 'dart:io' as io;

import 'package:noir/noir.dart';

import '../src/demo_scaffold.dart';
import 'catalog.dart';
import 'models.dart';
import 'package_detail.dart';
import 'theme.dart';

/// Which full-screen surface is currently visible.
enum PubSearchView {
  /// Query and package-name results.
  search,

  /// One package's detail surface.
  detail,
}

/// Explicit asynchronous request state used by the example.
enum PubLoadState {
  /// No request has run yet.
  idle,

  /// A request is active.
  loading,

  /// A request returned displayable data.
  ready,

  /// A search returned no packages.
  empty,

  /// A request failed.
  error,
}

enum _SearchMenu { sort, filter }

const _sortOptions = <SelectOption<PackageSort>>[
  SelectOption(
    name: 'TOP',
    description: 'Pub.dev ranking',
    value: PackageSort.top,
  ),
  SelectOption(
    name: 'RELEVANCE',
    description: 'Text relevance',
    value: PackageSort.text,
  ),
  SelectOption(
    name: 'CREATED',
    description: 'Newest packages',
    value: PackageSort.created,
  ),
  SelectOption(
    name: 'UPDATED',
    description: 'Recently updated',
    value: PackageSort.updated,
  ),
  SelectOption(
    name: 'DOWNLOADS',
    description: 'Most downloads',
    value: PackageSort.downloads,
  ),
  SelectOption(
    name: 'LIKES',
    description: 'Most likes',
    value: PackageSort.likes,
  ),
  SelectOption(
    name: 'POINTS',
    description: 'Most pub points',
    value: PackageSort.points,
  ),
  SelectOption(
    name: 'TRENDING',
    description: 'Trending now',
    value: PackageSort.trending,
  ),
];

const _filterOptions = <SelectOption<PackageSearchFilter>>[
  SelectOption(
    name: 'ANY',
    description: 'All packages',
    value: PackageSearchFilter.any,
  ),
  SelectOption(
    name: 'DART',
    description: 'Dart SDK',
    value: PackageSearchFilter.dart,
  ),
  SelectOption(
    name: 'FLUTTER',
    description: 'Flutter SDK',
    value: PackageSearchFilter.flutter,
  ),
  SelectOption(
    name: 'FAVORITE',
    description: 'Flutter favorites',
    value: PackageSearchFilter.favorite,
  ),
];

typedef _SearchCriteria = ({
  PackageSearchFilter filter,
  String query,
  PackageSort sort,
  String? topic,
});

const _completionDebounceDuration = Duration(milliseconds: 300);

/// Search-first pub.dev browser with a separate package detail view.
class PubSearchApp extends StatefulWidget {
  /// Creates the example around an owned [catalog].
  const PubSearchApp({
    required this.catalog,
    this.onQuit,
    this.initialQuery = 'noir',
    this.autoSearch = true,
    super.key,
  });

  /// Catalog closed when the app unmounts.
  final PubCatalog catalog;

  /// Optional quit callback used by injected hosts and tests.
  final VoidCallback? onQuit;

  /// Query placed in the input on first mount.
  final String initialQuery;

  /// Whether to search [initialQuery] after mounting.
  final bool autoSearch;

  @override
  State<PubSearchApp> createState() => _PubSearchAppState();
}

class _PubSearchAppState extends State<PubSearchApp> {
  final _scopeNode = FocusScopeNode(debugLabel: 'pub search');
  final _searchFocus = FocusNode(debugLabel: 'pub query');
  final _resultsFocus = FocusNode(debugLabel: 'pub results');
  final _sortFocus = FocusNode(debugLabel: 'pub sort');
  final _filterFocus = FocusNode(debugLabel: 'pub filter');
  final _menuFocus = FocusNode(debugLabel: 'pub menu');
  final _sortMenu = MenuController();
  final _filterMenu = MenuController();
  final _detailStatusFocus = FocusNode(debugLabel: 'pub detail status');
  final _detailFocus = FocusNode(debugLabel: 'pub detail');
  final _detailScroll = ScrollController();

  late final _chromeFocusNodes = <FocusNode>[
    _searchFocus,
    _resultsFocus,
    _sortFocus,
    _filterFocus,
    _detailFocus,
  ];

  late final TextEditingController _queryController;
  late String _completionText;
  PubSearchView _view = PubSearchView.search;
  late PubLoadState _searchState;
  PubLoadState _detailState = PubLoadState.idle;
  PackageSearchPage? _searchPage;
  PubPackageSnapshot? _package;
  PackageSort _sort = PackageSort.top;
  PackageSearchFilter _filter = PackageSearchFilter.any;
  _SearchMenu? _activeMenu;
  var _menuHighlightedIndex = 0;
  _SearchCriteria? _requestedCriteria;
  _SearchCriteria? _searchPageCriteria;
  var _suggestions = const <PubSuggestion>[];
  var _showSuggestions = false;
  Timer? _completionDebounce;
  var _completionLoading = false;
  var _completeGeneration = 0;
  PackageDetailTab _activeTab = PackageDetailTab.overview;
  String? _selectedPackage;
  String? _searchError;
  String? _detailError;
  var _selectedIndex = 0;
  var _generation = 0;
  // Page currently requested, which leads _searchPage while a request is in
  // flight so the header never advertises a page the user is not waiting for.
  var _page = 1;
  // One bit: the query editor and the result list are the only two
  // autofocus targets, and exactly one of them claims a fresh mount.
  var _autofocusResults = false;
  bool get _autofocusSearch => !_autofocusResults;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _completionText = _queryController.text;
    _queryController.addListener(_handleQueryChanged);
    // Both panels paint a focus-colored border from this state's build, and a
    // plain focus move never marks this element dirty on its own.
    for (final node in _chromeFocusNodes) {
      node.addListener(_handleFocusChanged);
    }
    _menuFocus.addListener(_handleMenuFocusChanged);
    // A queued auto-search is already a request, so the first paint is the
    // searching surface rather than an idle prompt against a prefilled query.
    // Drive-mode catalog launches must not hit pub.dev; skip the queue there.
    _searchState = _initialSearchState;
    if (_shouldAutoSearch) _queueAutoSearch(widget.catalog);
  }

  @override
  void didUpdateWidget(PubSearchApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.catalog, widget.catalog)) return;

    oldWidget.catalog.close();
    _resetForCatalogReplacement();
    if (_shouldAutoSearch) _queueAutoSearch(widget.catalog);
  }

  bool get _inDriveMode => io.Platform.environment['NOIR_DRIVE'] == '1';

  bool get _shouldAutoSearch => widget.autoSearch && !_inDriveMode;

  PubLoadState get _initialSearchState =>
      _shouldAutoSearch ? PubLoadState.loading : PubLoadState.idle;

  bool get _suggestionsVisible => _showSuggestions && _suggestions.isNotEmpty;

  void _queueAutoSearch(PubCatalog catalog) {
    scheduleMicrotask(() {
      if (!mounted || !identical(widget.catalog, catalog)) return;
      unawaited(_runSearch());
    });
  }

  void _resetForCatalogReplacement() {
    _generation++;
    _view = PubSearchView.search;
    _searchState = _initialSearchState;
    _detailState = PubLoadState.idle;
    _searchPage = null;
    _package = null;
    _sort = PackageSort.top;
    _filter = PackageSearchFilter.any;
    _activeMenu = null;
    _menuHighlightedIndex = 0;
    _sortMenu.close();
    _filterMenu.close();
    _requestedCriteria = null;
    _searchPageCriteria = null;
    _suggestions = const [];
    _showSuggestions = false;
    _invalidateCompletion();
    _activeTab = PackageDetailTab.overview;
    _selectedPackage = null;
    _selectedIndex = 0;
    _page = 1;
    _searchError = null;
    _detailError = null;
    _autofocusResults = false;
    _detailScroll.jumpTo(0);
  }

  @override
  void dispose() {
    _generation++;
    _invalidateCompletion();
    widget.catalog.close();
    _queryController.removeListener(_handleQueryChanged);
    _queryController.dispose();
    _scopeNode.dispose();
    for (final node in _chromeFocusNodes) {
      node.removeListener(_handleFocusChanged);
      node.dispose();
    }
    _menuFocus
      ..removeListener(_handleMenuFocusChanged)
      ..dispose();
    _detailStatusFocus.dispose();
    _detailScroll.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!mounted) return;
    // A leftover results autofocus would steal the query the next time a
    // Select mounts (suggestions appear while typing).
    if (_searchFocus.hasFocus) {
      _autofocusResults = false;
      _showSuggestions =
          _suggestions.isNotEmpty && _queryController.text.trim().length >= 3;
    }
    setState(() {});
  }

  void _handleMenuFocusChanged() {
    if (!mounted || _menuFocus.hasFocus || _activeMenu == null) return;
    _closeActiveMenu();
  }

  void _handleQueryChanged() {
    final text = _queryController.text;
    if (text == _completionText) return;
    _completionText = text;
    _scheduleComplete(text);
  }

  void _scheduleComplete(String prefix) {
    final needle = prefix.trim();
    setState(_invalidateCompletion);
    if (needle.length < 3) {
      return;
    }

    final request = _completeGeneration;
    _completionDebounce = Timer(_completionDebounceDuration, () {
      _completionDebounce = null;
      if (!mounted || request != _completeGeneration) return;
      setState(() => _completionLoading = true);
      unawaited(_runComplete(prefix, request));
    });
  }

  void _invalidateCompletion() {
    _completionDebounce?.cancel();
    _completionDebounce = null;
    _completeGeneration++;
    _completionLoading = false;
    _suggestions = const [];
    _showSuggestions = false;
  }

  Future<void> _runComplete(String prefix, int request) async {
    List<PubSuggestion>? items;
    try {
      items = await widget.catalog.complete(prefix);
    } on Exception {
      // Typeahead is opportunistic: a complete failure must not replace
      // search results or the query error with a second error surface.
      items = null;
    }
    if (!mounted || request != _completeGeneration) return;
    setState(() {
      _completionLoading = false;
      _suggestions = items ?? const [];
      _showSuggestions =
          items != null && items.isNotEmpty && _searchFocus.hasFocus;
    });
  }

  /// Whether [request] has been superseded, or this state is gone.
  ///
  /// Every awaited catalog call rechecks this before touching state, so a
  /// slower earlier response cannot overwrite a newer one.
  bool _isStale(int request) => !mounted || request != _generation;

  Future<void> _runSearch({
    int page = 1,
    String? query,
    String? topic,
    bool focusResultsOnSuccess = false,
    bool preserveFocusOnEmptyOrError = false,
  }) async {
    if (!mounted) return;
    final request = ++_generation;
    final criteria = (
      filter: _filter,
      query: (query ?? _queryController.text).trim(),
      sort: _sort,
      topic: topic,
    );
    _invalidateCompletion();
    final keepResultsFocus = _resultsFocus.hasFocus;
    setState(() {
      _view = PubSearchView.search;
      _searchState = PubLoadState.loading;
      _suggestions = const [];
      _showSuggestions = false;
      _searchError = null;
      _autofocusResults = keepResultsFocus;
      _page = page;
      _requestedCriteria = criteria;
      // Every search replaces the whole list, so a carried-over highlight would
      // point at an unrelated package on the incoming page.
      _selectedIndex = 0;
    });
    try {
      final result = await widget.catalog.search(
        criteria.query,
        page: page,
        sort: criteria.sort,
        filter: criteria.filter,
        topic: criteria.topic,
      );
      if (_isStale(request)) return;
      final isEmpty = result.packages.isEmpty;
      setState(() {
        _searchPage = result;
        _searchPageCriteria = criteria;
        _searchState = isEmpty ? PubLoadState.empty : PubLoadState.ready;
        if (isEmpty) {
          _autofocusResults = false;
        } else if (focusResultsOnSuccess) {
          _autofocusResults = true;
        }
      });
      if (isEmpty && !preserveFocusOnEmptyOrError) {
        _searchFocus.requestFocus();
      }
    } on Exception catch (error) {
      if (_isStale(request)) return;
      setState(() {
        _searchState = PubLoadState.error;
        _searchError = '$error';
        // The last good results stay on screen, so the header follows them
        // back rather than naming the page that just failed.
        _page = _searchPage?.page ?? 1;
      });
      // Ordinary error copy advertises Enter as retry, so return ownership to
      // the query. A menu refresh retains its launcher ownership instead.
      if (!preserveFocusOnEmptyOrError) _searchFocus.requestFocus();
    }
  }

  void _submitSearch() {
    final query = _queryController.text.trim();
    final failedCriteria = _searchState == PubLoadState.error
        ? _requestedCriteria
        : null;
    final retryTopic = failedCriteria?.query == query
        ? failedCriteria?.topic
        : null;
    unawaited(_runSearch(topic: retryTopic));
  }

  void _abandonInFlightSearch() {
    // Opening detail increments generation and abandons the refresh, so
    // do not leave the search pane spinning if the user comes back.
    if ((_searchState == PubLoadState.loading ||
            _searchState == PubLoadState.error) &&
        _searchPage != null) {
      _searchState = PubLoadState.ready;
      _searchError = null;
      _page = _searchPage!.page;
      final criteria = _searchPageCriteria;
      if (criteria != null) {
        _sort = criteria.sort;
        _filter = criteria.filter;
        _requestedCriteria = criteria;
      }
    } else if (_searchState == PubLoadState.loading) {
      _searchState = PubLoadState.idle;
    }
  }

  Future<void> _loadPackage(String name) async {
    final request = ++_generation;
    _invalidateCompletion();
    setState(() {
      _view = PubSearchView.detail;
      _abandonInFlightSearch();
      _detailState = PubLoadState.loading;
      _selectedPackage = name;
      _activeTab = PackageDetailTab.overview;
      _detailScroll.jumpTo(0);
      _package = null;
      _detailError = null;
    });
    try {
      final package = await widget.catalog.loadPackage(name);
      if (_isStale(request)) return;
      setState(() {
        _package = package;
        _detailState = PubLoadState.ready;
      });
    } on Exception catch (error) {
      if (_isStale(request)) return;
      setState(() {
        _detailState = PubLoadState.error;
        _detailError = '$error';
      });
    }
  }

  void _openSearchMenu(_SearchMenu kind) {
    if (_activeMenu == kind) return;
    final previous = _activeMenu;
    if (previous != null) {
      _menuFor(previous).close();
    }
    _menuFor(kind).open();
  }

  void _closeActiveMenu() {
    final kind = _activeMenu;
    if (kind == null) return;
    _menuFor(kind).close();
  }

  void _confirmSort(PackageSort sort) {
    final changed = sort != _sort;
    setState(() => _sort = sort);
    _sortMenu.close();
    if (changed) _refreshForMenu();
  }

  void _confirmFilter(PackageSearchFilter filter) {
    final changed = filter != _filter;
    setState(() => _filter = filter);
    _filterMenu.close();
    if (changed) _refreshForMenu();
  }

  void _handleMenuOpened(_SearchMenu kind) {
    setState(() {
      _activeMenu = kind;
      _autofocusResults = false;
      _menuHighlightedIndex = switch (kind) {
        _SearchMenu.sort => _indexOfOption(_sortOptions, _sort),
        _SearchMenu.filter => _indexOfOption(_filterOptions, _filter),
      };
    });
  }

  void _handleMenuClosed(_SearchMenu kind) {
    if (_activeMenu != kind) return;
    setState(() => _activeMenu = null);
  }

  MenuController _menuFor(_SearchMenu kind) => switch (kind) {
    _SearchMenu.sort => _sortMenu,
    _SearchMenu.filter => _filterMenu,
  };

  int _indexOfOption<T>(List<SelectOption<T>> options, T value) {
    final index = options.indexWhere((option) => option.value == value);
    return index < 0 ? 0 : index;
  }

  String _optionName<T>(List<SelectOption<T>> options, T value) =>
      options[_indexOfOption(options, value)].name;

  void _refreshForMenu() {
    unawaited(
      _runSearch(
        query: _queryController.text,
        topic: _visibleTopic,
        preserveFocusOnEmptyOrError: true,
      ),
    );
  }

  void _nextPage() => _shiftPage(1);

  void _previousPage() => _shiftPage(-1);

  void _shiftPage(int delta) {
    if (_searchState == PubLoadState.loading) return;
    final page = _searchPage;
    if (page == null) return;
    final next = page.page + delta;
    if (next < 1 || (delta > 0 && !page.hasNextPage)) return;
    unawaited(
      _runSearch(
        page: next,
        query: _searchPageCriteria?.query,
        topic: _searchPageCriteria?.topic,
      ),
    );
  }

  void _returnToResults({bool focusSearch = false}) {
    _generation++;
    final focusResults =
        !focusSearch && (_searchPage?.packages.isNotEmpty ?? false);
    setState(() {
      _view = PubSearchView.search;
      _detailState = PubLoadState.idle;
      _package = null;
      _detailError = null;
      _autofocusResults = focusResults;
    });
  }

  void _selectDetailTab(PackageDetailTab tab) {
    if (tab == _activeTab) return;
    setState(() => _activeTab = tab);
    _detailScroll.jumpTo(0);
  }

  void _moveDetailTab(int delta) {
    final count = PackageDetailTab.values.length;
    final index = (_activeTab.index + delta + count) % count;
    _selectDetailTab(PackageDetailTab.values[index]);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!event.isPress) return KeyEventResult.ignored;
    if (_activeMenu != null) {
      if (event.logicalKey == LogicalKeyboardKey.escape ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        _closeActiveMenu();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_view == PubSearchView.detail) {
        _returnToResults();
      } else {
        final onQuit = widget.onQuit;
        if (onQuit != null) {
          onQuit();
        } else {
          TuiApp.exit(context);
        }
      }
      return KeyEventResult.handled;
    }

    if (_view == PubSearchView.detail) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _moveDetailTab(-1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _moveDetailTab(1);
        return KeyEventResult.handled;
      }
      if (event.character case final value?
          when value.length == 1 && '1234'.contains(value)) {
        _selectDetailTab(PackageDetailTab.values[int.parse(value) - 1]);
        return KeyEventResult.handled;
      }
      if (event.character == '/') {
        _returnToResults(focusSearch: true);
        return KeyEventResult.handled;
      }
      if (event.character == 'r' && _detailState == PubLoadState.error) {
        final name = _selectedPackage;
        if (name != null) unawaited(_loadPackage(name));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (!_resultsFocus.hasFocus) return KeyEventResult.ignored;
    if (event.character == '/') {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (_suggestionsVisible) return KeyEventResult.ignored;
    switch (event.character) {
      case 's':
        _openSearchMenu(_SearchMenu.sort);
        return KeyEventResult.handled;
      case 'f':
        _openSearchMenu(_SearchMenu.filter);
        return KeyEventResult.handled;
      case 'n':
        _nextPage();
        return KeyEventResult.handled;
      case 'p':
        _previousPage();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: pubTheme,
    child: FocusScope(
      node: _scopeNode,
      onKeyEvent: _handleKey,
      child: _PubSearchThemedView(state: this),
    ),
  );

  String get _searchHint {
    if (_activeMenu != null) {
      return '↑↓ choose  Enter/click apply  Tab/Esc cancel';
    }
    if (_sortFocus.hasFocus) {
      return 'Enter/Space/click choose sort  Tab filter  Esc quit';
    }
    if (_filterFocus.hasFocus) {
      final next = _searchPage?.packages.isNotEmpty ?? false
          ? 'results'
          : 'search';
      return 'Enter/Space/click choose filter  Tab $next  Esc quit';
    }
    if (_resultsFocus.hasFocus && _suggestionsVisible) {
      return '↑↓ select  Enter/click choose  / search  Esc quit';
    }
    if (_resultsFocus.hasFocus) return _focusedResultHint;
    if (_suggestionsVisible) {
      return 'Enter search   Tab suggestions   Esc quit';
    }
    if (_searchPage != null) {
      return 'Enter search  Tab sort  Esc quit';
    }
    return 'Enter search   Esc quit';
  }

  String get _focusedResultHint {
    final pageHint = _pageCommandHint;
    if (pageHint != null) {
      return [
        '↑↓ select',
        'Enter/click open',
        's/f',
        pageHint,
        '/ query',
        'Esc',
      ].join('  ');
    }
    return '↑↓ select  Enter/click open  s/f pick  / query  Esc';
  }

  String? get _pageCommandHint {
    if (_searchState == PubLoadState.loading) return null;
    final page = _searchPage;
    if (page == null) return null;
    final previous = page.page > 1;
    final next = page.hasNextPage;
    if (previous && next) return 'n/p page';
    if (next) return 'n next';
    if (previous) return 'p prev';
    return null;
  }

  String? get _visibleTopic =>
      _searchState == PubLoadState.loading || _searchState == PubLoadState.error
      ? _requestedCriteria?.topic
      : _searchPageCriteria?.topic;

  bool get _showSearchControls => !_showSuggestions && _searchPage != null;

  Widget _buildSearchView(BuildContext context) {
    final theme = Theme.of(context);
    final topic = _visibleTopic;
    return DemoScaffold(
      title: 'PUB / SEARCH',
      hint: _searchHint,
      child: Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DemoPanel(
              title: 'SEARCH',
              focused: _searchFocus.hasFocus,
              child: Row(
                spacing: 1,
                children: [
                  Expanded(
                    child: TextInput(
                      key: const ValueKey<String>('query'),
                      controller: _queryController,
                      focusNode: _searchFocus,
                      autofocus: _autofocusSearch,
                      placeholder: 'package name or pub.dev search expression',
                      onSubmit: _submitSearch,
                    ),
                  ),
                  if (_completionLoading) const Spinner(),
                ],
              ),
            ),
            if (_showSearchControls) ...[
              const SizedBox(height: 1),
              Row(
                spacing: 3,
                children: [
                  _menuAnchor(
                    kind: _SearchMenu.sort,
                    label: 'Sort',
                    value: _optionName(_sortOptions, _sort),
                    launcherKey: const ValueKey<String>('sort'),
                    title: 'Sort menu',
                    options: _sortOptions,
                    onConfirm: _confirmSort,
                  ),
                  _menuAnchor(
                    kind: _SearchMenu.filter,
                    label: 'Filter',
                    value: _optionName(_filterOptions, _filter),
                    launcherKey: const ValueKey<String>('filter'),
                    title: 'Filter menu',
                    options: _filterOptions,
                    onConfirm: _confirmFilter,
                  ),
                  Expanded(
                    child: switch (topic) {
                      null => const SizedBox(),
                      final value => Text(
                        'TOPIC  $value',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: pubEmphasis),
                      ),
                    },
                  ),
                  Text(
                    'PAGE  $_page',
                    style: TextStyle(color: theme.textMuted),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 1),
            if (_searchState == PubLoadState.idle && !_suggestionsVisible)
              Text(
                'Press Enter to search pub.dev.',
                style: TextStyle(color: theme.textMuted),
              )
            else
              // Stack clips overflowing result rows to the remaining viewport.
              // A Column would paint them through the panel's bottom border.
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      right: 0,
                      child: _buildResults(context),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _menuAnchor<T>({
    required _SearchMenu kind,
    required String label,
    required String value,
    required Key launcherKey,
    required String title,
    required List<SelectOption<T>> options,
    required void Function(T value) onConfirm,
  }) {
    final focusNode = switch (kind) {
      _SearchMenu.sort => _sortFocus,
      _SearchMenu.filter => _filterFocus,
    };
    return MenuAnchor(
      controller: _menuFor(kind),
      childFocusNode: focusNode,
      onOpen: () => _handleMenuOpened(kind),
      onClose: () => _handleMenuClosed(kind),
      menuChildren: [
        _menuPanel(
          title: title,
          child: _menuSelect(options: options, onConfirm: onConfirm),
        ),
      ],
      builder: (context, menu, child) => _menuLauncher(
        key: launcherKey,
        theme: Theme.of(context),
        label: label,
        value: value,
        focusNode: focusNode,
        active: _activeMenu == kind,
        onActivate: () {
          if (menu.isOpen) {
            menu.close();
            return;
          }
          _openSearchMenu(kind);
        },
      ),
    );
  }

  Widget _menuLauncher({
    required ThemeData theme,
    required String label,
    required String value,
    required FocusNode focusNode,
    required bool active,
    required VoidCallback onActivate,
    Key? key,
  }) {
    final focused = focusNode.hasFocus;
    final (color, textColor) = switch ((active, focused)) {
      (true, _) => (theme.selectedBackground, theme.selectedForeground),
      (false, true) => (theme.accent, theme.accentForeground),
      (false, false) => (theme.surfaceVariant, theme.textMuted),
    };
    return Button(
      key: key,
      label: '$label: ${value.toUpperCase()} ${Icons.caretDown}',
      focusNode: focusNode,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      color: color,
      textColor: textColor,
      onPressed: onActivate,
    );
  }

  Widget _buildResults(BuildContext context) {
    final child = _suggestionsVisible
        ? _buildSuggestionList()
        : switch (_searchState) {
            // Idle copy lives in the search column; this switch is only
            // reached while a request is active or a page is on screen.
            PubLoadState.idle => const SizedBox.shrink(),
            PubLoadState.loading => _buildSearchLoading(context),
            PubLoadState.empty => Text(
              'No packages found. Try a broader expression.',
              style: TextStyle(color: Theme.of(context).textMuted),
            ),
            PubLoadState.error => _buildSearchError(context),
            PubLoadState.ready => _buildResultList(context),
          };
    return DemoPanel(
      title: _suggestionsVisible ? 'SUGGESTIONS' : 'RESULTS',
      focused: _activeMenu == null && _resultsFocus.hasFocus,
      child: child,
    );
  }

  Widget _menuPanel({required String title, required Widget child}) => SizedBox(
    width: 48,
    child: DemoPanel(
      title: title,
      focused: _menuFocus.hasFocus,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_searchState == PubLoadState.loading) ...[
            const Row(
              spacing: 1,
              children: [Spinner(), Text('Updating results…')],
            ),
            const SizedBox(height: 1),
          ],
          child,
        ],
      ),
    ),
  );

  Widget _menuSelect<T>({
    required List<SelectOption<T>> options,
    required void Function(T value) onConfirm,
  }) => Select<T>(
    focusNode: _menuFocus,
    autofocus: true,
    selectedIndex: _menuHighlightedIndex,
    height: options.length,
    options: options,
    backgroundColor: Color.transparent,
    onChanged: (index, option) {
      if (index == _menuHighlightedIndex) return;
      setState(() => _menuHighlightedIndex = index);
    },
    onSelect: (index, option) {
      final value = option.value;
      if (value != null) onConfirm(value);
    },
  );

  Widget _buildSearchLoading(BuildContext context) {
    final previous = _searchPage;
    final showResultsProgress = _activeMenu == null;
    final hasPreviousResults = previous != null && previous.packages.isNotEmpty;
    // Keep the last Select mounted so result-scoped menu shortcuts and
    // package activation remain available while paging is suppressed for the
    // pending request.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showResultsProgress) ...[
          const Row(
            spacing: 1,
            children: [Spinner(), Text('Searching pub.dev…')],
          ),
          if (hasPreviousResults) const SizedBox(height: 1),
        ],
        if (hasPreviousResults) _buildResultList(context),
      ],
    );
  }

  Widget _buildSearchError(BuildContext context) {
    final theme = Theme.of(context);
    final previous = _searchPage;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Search unavailable', style: TextStyle(color: theme.danger)),
        Text(_searchError ?? 'Unknown error'),
        Text(
          _searchFocus.hasFocus
              ? 'Edit the query or press Enter to retry.'
              : 'Go to the query to edit or retry.',
          style: TextStyle(color: theme.textMuted),
        ),
        if (previous != null && previous.packages.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text('LAST RESULTS', style: TextStyle(color: theme.textMuted)),
          _buildResultList(context),
        ],
      ],
    );
  }

  Widget _buildSuggestionList() => Select<PubSuggestion>(
    focusNode: _resultsFocus,
    height: _suggestions.length,
    showScrollIndicator: true,
    backgroundColor: Color.transparent,
    options: [
      for (final item in _suggestions)
        SelectOption(
          name: item.name,
          description: item.kind == PubSuggestionKind.topic
              ? '${item.packageCount} pkgs'
              : null,
          value: item,
        ),
    ],
    onSelect: (index, option) {
      final item = option.value;
      if (item == null) return;
      if (item.kind == PubSuggestionKind.topic) {
        unawaited(_runSearch(topic: item.name));
        return;
      }
      unawaited(_loadPackage(item.name));
    },
  );

  Widget _buildResultList(BuildContext context) {
    final theme = Theme.of(context);
    final page = _searchPage!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          [
            '${page.packages.length} PACKAGES',
            if (page.message != null) page.message!,
          ].join('  ·  '),
          style: TextStyle(color: theme.textMuted),
        ),
        const SizedBox(height: 1),
        Select<String>(
          focusNode: _resultsFocus,
          autofocus: _autofocusResults && _activeMenu == null,
          selectedIndex: _selectedIndex,
          height: page.packages.length,
          showScrollIndicator: true,
          backgroundColor: Color.transparent,
          options: [
            for (final package in page.packages)
              SelectOption(name: package, value: package),
          ],
          onChanged: (index, option) {
            if (_selectedIndex == index) return;
            setState(() => _selectedIndex = index);
          },
          onSelect: (index, option) {
            final name = option.value;
            if (name != null) unawaited(_loadPackage(name));
          },
        ),
      ],
    );
  }

  Widget _buildDetailView(BuildContext context) {
    final theme = Theme.of(context);
    if (_detailState == PubLoadState.ready) {
      return PubPackageDetail(
        package: _package!,
        activeTab: _activeTab,
        onTabSelected: _selectDetailTab,
        scrollController: _detailScroll,
        scrollFocusNode: _detailFocus,
      );
    }
    return DemoScaffold(
      title: 'PUB / PACKAGE',
      hint: switch (_detailState) {
        PubLoadState.loading => 'Esc results',
        PubLoadState.error => 'r retry   Esc results',
        _ => null,
      },
      child: switch (_detailState) {
        PubLoadState.loading => _buildDetailStatus([
          Row(
            spacing: 1,
            children: [
              const Spinner(),
              Text('Loading ${_selectedPackage ?? 'package'}…'),
            ],
          ),
        ]),
        PubLoadState.error => _buildDetailStatus([
          Text('Package unavailable', style: TextStyle(color: theme.danger)),
          Text(_detailError ?? 'Unknown error'),
        ]),
        // Unreachable: detail view is only entered through _loadPackage, which
        // sets loading, ready, or error. Dart still requires exhaustiveness.
        _ => const SizedBox.shrink(),
      },
    );
  }

  /// Detail surface shown before [PubPackageDetail] mounts its own scroll
  /// focus, so Escape and retry always have a focused node to route through.
  Widget _buildDetailStatus(List<Widget> children) => Focus(
    focusNode: _detailStatusFocus,
    autofocus: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

/// Introduces a build context below [Theme] for the state-owned view builders.
class _PubSearchThemedView extends StatelessWidget {
  const _PubSearchThemedView({required this.state});

  final _PubSearchAppState state;

  @override
  Widget build(BuildContext context) => state._view == PubSearchView.search
      ? state._buildSearchView(context)
      : state._buildDetailView(context);
}
