import 'dart:async';

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

enum _SearchChooser { sort, filter }

const _sortOptions = <SelectOption<PackageSort>>[
  SelectOption(
    name: 'TOP',
    description: 'Pub.dev ranking',
    value: PackageSort.top,
  ),
  SelectOption(
    name: 'TEXT',
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
  final _chooserFocus = FocusNode(debugLabel: 'pub chooser');
  final _detailStatusFocus = FocusNode(debugLabel: 'pub detail status');
  final _detailFocus = FocusNode(debugLabel: 'pub detail');
  final _detailScroll = ScrollController();

  late final TextEditingController _queryController;
  late String _completionText;
  PubSearchView _view = PubSearchView.search;
  late PubLoadState _searchState;
  PubLoadState _detailState = PubLoadState.idle;
  PackageSearchPage? _searchPage;
  PubPackageSnapshot? _package;
  PackageSort _sort = PackageSort.top;
  PackageSearchFilter _filter = PackageSearchFilter.any;
  _SearchChooser? _chooser;
  var _chooserHighlightedIndex = 0;
  _SearchCriteria? _requestedCriteria;
  _SearchCriteria? _searchPageCriteria;
  var _suggestions = const <PubSuggestion>[];
  var _showSuggestions = false;
  Timer? _completionDebounce;
  var _completionLoading = false;
  var _completeGeneration = 0;
  PackageDetailTab _activeTab = PackageDetailTab.overview;
  String? _selectedPackage;
  String? _error;
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
    _searchFocus.addListener(_handleFocusChanged);
    _resultsFocus.addListener(_handleFocusChanged);
    _sortFocus.addListener(_handleFocusChanged);
    _filterFocus.addListener(_handleFocusChanged);
    _chooserFocus.addListener(_handleChooserFocusChanged);
    _detailFocus.addListener(_handleFocusChanged);
    // A queued auto-search is already a request, so the first paint is the
    // searching surface rather than an idle prompt against a prefilled query.
    _searchState = widget.autoSearch ? PubLoadState.loading : PubLoadState.idle;
    if (widget.autoSearch) {
      scheduleMicrotask(() => unawaited(_runSearch()));
    }
  }

  @override
  void didUpdateWidget(PubSearchApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.catalog, widget.catalog)) return;

    _generation++;
    oldWidget.catalog.close();
    _view = PubSearchView.search;
    _searchState = widget.autoSearch ? PubLoadState.loading : PubLoadState.idle;
    _detailState = PubLoadState.idle;
    _searchPage = null;
    _package = null;
    _sort = PackageSort.top;
    _filter = PackageSearchFilter.any;
    _chooser = null;
    _chooserHighlightedIndex = 0;
    _requestedCriteria = null;
    _searchPageCriteria = null;
    _suggestions = const [];
    _showSuggestions = false;
    _invalidateCompletion();
    _activeTab = PackageDetailTab.overview;
    _selectedPackage = null;
    _selectedIndex = 0;
    _page = 1;
    _error = null;
    _autofocusResults = false;
    _detailScroll.jumpTo(0);

    if (widget.autoSearch) {
      final replacement = widget.catalog;
      scheduleMicrotask(() {
        if (!mounted || !identical(widget.catalog, replacement)) return;
        unawaited(_runSearch());
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _invalidateCompletion();
    widget.catalog.close();
    _queryController.removeListener(_handleQueryChanged);
    _queryController.dispose();
    _scopeNode.dispose();
    _searchFocus.removeListener(_handleFocusChanged);
    _resultsFocus.removeListener(_handleFocusChanged);
    _sortFocus.removeListener(_handleFocusChanged);
    _filterFocus.removeListener(_handleFocusChanged);
    _chooserFocus.removeListener(_handleChooserFocusChanged);
    _detailFocus.removeListener(_handleFocusChanged);
    _searchFocus.dispose();
    _resultsFocus.dispose();
    _sortFocus.dispose();
    _filterFocus.dispose();
    _chooserFocus.dispose();
    _detailStatusFocus.dispose();
    _detailFocus.dispose();
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

  void _handleChooserFocusChanged() {
    if (!mounted || _chooserFocus.hasFocus || _chooser == null) return;
    _cancelChooser();
  }

  void _handleQueryChanged() {
    final text = _queryController.text;
    if (text == _completionText) return;
    _completionText = text;
    _scheduleComplete(text);
  }

  void _scheduleComplete(String prefix) {
    _invalidateCompletion();
    final needle = prefix.trim();
    setState(() {});
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
    try {
      final items = await widget.catalog.complete(prefix);
      if (!mounted || request != _completeGeneration) return;
      setState(() {
        _completionLoading = false;
        _suggestions = items;
        _showSuggestions = items.isNotEmpty && _searchFocus.hasFocus;
      });
    } on Exception {
      if (!mounted || request != _completeGeneration) return;
      setState(() {
        _completionLoading = false;
        _suggestions = const [];
        _showSuggestions = false;
      });
    }
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
      _error = null;
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
        _error = '$error';
        // The last good results stay on screen, so the header follows them
        // back rather than naming the page that just failed.
        _page = _searchPage?.page ?? 1;
      });
      // Ordinary error copy advertises Enter as retry, so return ownership to
      // the query. A chooser refresh retains its launcher ownership instead.
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

  Future<void> _loadPackage(String name) async {
    final request = ++_generation;
    _invalidateCompletion();
    setState(() {
      _view = PubSearchView.detail;
      // Opening detail increments generation and abandons the refresh, so
      // do not leave the search pane spinning if the user comes back.
      if ((_searchState == PubLoadState.loading ||
              _searchState == PubLoadState.error) &&
          _searchPage != null) {
        _searchState = PubLoadState.ready;
        _page = _searchPage!.page;
        final criteria = _searchPageCriteria;
        if (criteria != null) {
          _sort = criteria.sort;
          _filter = criteria.filter;
          _requestedCriteria = criteria;
        }
      }
      _detailState = PubLoadState.loading;
      _selectedPackage = name;
      _activeTab = PackageDetailTab.overview;
      _detailScroll.jumpTo(0);
      _package = null;
      _error = null;
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
        _error = '$error';
      });
    }
  }

  void _openChooser(_SearchChooser chooser) {
    if (_chooser == chooser) return;
    setState(() {
      _chooser = chooser;
      _chooserHighlightedIndex = switch (chooser) {
        _SearchChooser.sort => _sort.index,
        _SearchChooser.filter => _filter.index,
      };
    });
  }

  void _cancelChooser() {
    final chooser = _chooser;
    if (chooser == null) return;
    setState(() => _chooser = null);
    final launcher = _chooserLauncherFocus(chooser);
    if (launcher.isAttached) launcher.requestFocus();
  }

  void _confirmSort(PackageSort sort) {
    final changed = sort != _sort;
    setState(() {
      _chooser = null;
      _sort = sort;
    });
    _sortFocus.requestFocus();
    if (changed) _refreshForChooser();
  }

  void _confirmFilter(PackageSearchFilter filter) {
    final changed = filter != _filter;
    setState(() {
      _chooser = null;
      _filter = filter;
    });
    _filterFocus.requestFocus();
    if (changed) _refreshForChooser();
  }

  void _refreshForChooser() {
    unawaited(
      _runSearch(
        query: _queryController.text,
        topic: _visibleTopic,
        preserveFocusOnEmptyOrError: true,
      ),
    );
  }

  FocusNode _chooserLauncherFocus(_SearchChooser chooser) => switch (chooser) {
    _SearchChooser.sort => _sortFocus,
    _SearchChooser.filter => _filterFocus,
  };

  void _nextPage() {
    final page = _searchPage;
    if (page == null || !page.hasNextPage) return;
    unawaited(
      _runSearch(
        page: page.page + 1,
        query: _searchPageCriteria?.query,
        topic: _searchPageCriteria?.topic,
      ),
    );
  }

  void _previousPage() {
    final page = _searchPage;
    if (page == null || page.page <= 1) return;
    unawaited(
      _runSearch(
        page: page.page - 1,
        query: _searchPageCriteria?.query,
        topic: _searchPageCriteria?.topic,
      ),
    );
  }

  void _returnToResults({bool focusSearch = false}) {
    _generation++;
    setState(() {
      _view = PubSearchView.search;
      _detailState = PubLoadState.idle;
      _package = null;
      _error = null;
      _autofocusResults = !focusSearch;
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
    if (_chooser != null) {
      if (event.logicalKey == LogicalKeyboardKey.escape ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        _cancelChooser();
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
    if (_showSuggestions) return KeyEventResult.ignored;
    switch (event.character) {
      case 's':
        _openChooser(_SearchChooser.sort);
        return KeyEventResult.handled;
      case 'f':
        _openChooser(_SearchChooser.filter);
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
    if (_chooser != null) {
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
    if (_resultsFocus.hasFocus && _showSuggestions && _suggestions.isNotEmpty) {
      return '↑↓ select  Enter/click choose  / search  Esc quit';
    }
    if (!_resultsFocus.hasFocus) {
      if (_showSuggestions && _suggestions.isNotEmpty) {
        return 'Enter search   Tab suggestions   Esc quit';
      }
      final hasFocusableResults = _searchPage?.packages.isNotEmpty ?? false;
      if (hasFocusableResults) {
        if (_searchState == PubLoadState.idle) {
          return 'Enter search   Tab results   Esc quit';
        }
        return 'Enter search  Tab sort  Esc quit';
      }
      if (_searchPage != null) {
        return 'Enter search  Tab sort  Esc quit';
      }
      return 'Enter search   Esc quit';
    }
    return _focusedResultHint;
  }

  String get _focusedResultHint {
    final pageHint = _pageCommandHint;
    if (pageHint != null) {
      return [
        '↑↓ select',
        'Enter/click',
        's/f pick',
        pageHint,
        '/ query',
        'Esc',
      ].join('  ');
    }
    return '↑↓ select  Enter/click open  s/f pick  / query  Esc';
  }

  String? get _pageCommandHint {
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
      title: 'PUB / FIND',
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
                  _chooserLauncher(
                    theme: theme,
                    label: 'SORT',
                    value: _sort.name,
                    focusNode: _sortFocus,
                    onActivate: () => _openChooser(_SearchChooser.sort),
                  ),
                  _chooserLauncher(
                    theme: theme,
                    label: 'FILTER',
                    value: _filter.name,
                    focusNode: _filterFocus,
                    onActivate: () => _openChooser(_SearchChooser.filter),
                  ),
                  if (topic != null)
                    Expanded(
                      child: Text(
                        'TOPIC  $topic',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: pubEmphasis),
                      ),
                    )
                  else
                    const Expanded(child: SizedBox()),
                  Text(
                    'PAGE  $_page',
                    style: TextStyle(color: theme.textMuted),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 1),
            if (_searchState == PubLoadState.idle &&
                !(_showSuggestions && _suggestions.isNotEmpty))
              Text(
                'Press Enter to search pub.dev.',
                style: TextStyle(color: theme.textMuted),
              )
            else
              Expanded(child: _buildResults(context)),
          ],
        ),
      ),
    );
  }

  Widget _chooserLauncher({
    required ThemeData theme,
    required String label,
    required String value,
    required FocusNode focusNode,
    required VoidCallback onActivate,
  }) => Row(
    children: [
      Text(label, style: TextStyle(color: theme.textMuted)),
      Button(
        label: '[${value.toUpperCase()} ▾]',
        focusNode: focusNode,
        onPressed: onActivate,
      ),
    ],
  );

  Widget _buildResults(BuildContext context) => DemoPanel(
    title: switch (_chooser) {
      _SearchChooser.sort => 'CHOOSE SORT',
      _SearchChooser.filter => 'CHOOSE FILTER',
      null => _showSuggestions ? 'SUGGESTIONS' : 'RESULTS',
    },
    focused: _chooser == null ? _resultsFocus.hasFocus : _chooserFocus.hasFocus,
    child: _chooser != null
        ? _buildChooser()
        : _showSuggestions && _suggestions.isNotEmpty
        ? _buildSuggestionList()
        : switch (_searchState) {
            PubLoadState.idle => Text(
              'Press Enter to search pub.dev.',
              style: TextStyle(color: Theme.of(context).textMuted),
            ),
            PubLoadState.loading => _buildSearchLoading(context),
            PubLoadState.empty => Text(
              'No packages found. Try a broader expression.',
              style: TextStyle(color: Theme.of(context).textMuted),
            ),
            PubLoadState.error => _buildSearchError(context),
            PubLoadState.ready => _buildResultList(context),
          },
  );

  Widget _buildChooser() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_searchState == PubLoadState.loading) ...[
        const Row(spacing: 1, children: [Spinner(), Text('Updating results…')]),
        const SizedBox(height: 1),
      ],
      Expanded(
        child: switch (_chooser!) {
          _SearchChooser.sort => Select<PackageSort>(
            focusNode: _chooserFocus,
            autofocus: true,
            selectedIndex: _chooserHighlightedIndex,
            options: _sortOptions,
            onChanged: (index, option) {
              if (index == _chooserHighlightedIndex) return;
              setState(() => _chooserHighlightedIndex = index);
            },
            onSelect: (index, option) {
              final value = option.value;
              if (value != null) _confirmSort(value);
            },
          ),
          _SearchChooser.filter => Select<PackageSearchFilter>(
            focusNode: _chooserFocus,
            autofocus: true,
            selectedIndex: _chooserHighlightedIndex,
            height: 4,
            options: _filterOptions,
            onChanged: (index, option) {
              if (index == _chooserHighlightedIndex) return;
              setState(() => _chooserHighlightedIndex = index);
            },
            onSelect: (index, option) {
              final value = option.value;
              if (value != null) _confirmFilter(value);
            },
          ),
        },
      ),
    ],
  );

  Widget _buildSearchLoading(BuildContext context) {
    final previous = _searchPage;
    const searching = Row(
      spacing: 1,
      children: [Spinner(), Text('Searching pub.dev…')],
    );
    if (previous == null || previous.packages.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [searching],
      );
    }
    // Keep the last Select mounted so result-scoped `s`/`n`/`p` still fire
    // while the next page is in flight. Unmounting it dropped those keys.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        searching,
        const SizedBox(height: 1),
        Expanded(child: _buildResultList(context)),
      ],
    );
  }

  Widget _buildSearchError(BuildContext context) {
    final theme = Theme.of(context);
    final previous = _searchPage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Search unavailable', style: TextStyle(color: theme.danger)),
        Text(_error ?? 'Unknown error'),
        Text(
          'Edit the query or press Enter to retry.',
          style: TextStyle(color: theme.textMuted),
        ),
        if (previous != null && previous.packages.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text('LAST RESULTS', style: TextStyle(color: theme.textMuted)),
          Expanded(child: _buildResultList(context)),
        ],
      ],
    );
  }

  Widget _buildSuggestionList() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: Select<PubSuggestion>(
          focusNode: _resultsFocus,
          height: 13,
          showScrollIndicator: true,
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
        ),
      ),
    ],
  );

  Widget _buildResultList(BuildContext context) {
    final theme = Theme.of(context);
    final page = _searchPage!;
    return Column(
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
        Expanded(
          child: Select<String>(
            focusNode: _resultsFocus,
            autofocus: _autofocusResults,
            selectedIndex: _selectedIndex,
            height: 13,
            showScrollIndicator: true,
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
          Text(_error ?? 'Unknown error'),
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
