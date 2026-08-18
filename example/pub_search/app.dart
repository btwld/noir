import 'dart:async';

import 'package:noir/noir.dart';

import 'catalog.dart';
import 'models.dart';
import 'package_detail.dart';

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

/// Data-source status presented in the search header.
enum PubSearchConnection {
  /// Requests use the live pub.dev API.
  live,

  /// Requests use an injected offline or deterministic catalog.
  offline,
}

/// Search-first pub.dev browser with a separate package detail view.
class PubSearchApp extends StatefulWidget {
  /// Creates the example around an owned [catalog].
  const PubSearchApp({
    required this.catalog,
    this.onQuit,
    this.initialQuery = 'noir',
    this.autoSearch = true,
    this.autofocusSearch = true,
    this.connection = PubSearchConnection.live,
    super.key,
  });

  /// Catalog closed when the app unmounts.
  final PubCatalog catalog;

  /// Optional quit callback used by the executable and tests.
  final VoidCallback? onQuit;

  /// Query placed in the input on first mount.
  final String initialQuery;

  /// Whether to search [initialQuery] after mounting.
  final bool autoSearch;

  /// Whether the query receives initial focus.
  final bool autofocusSearch;

  /// Status shown beside the search title.
  final PubSearchConnection connection;

  @override
  State<PubSearchApp> createState() => _PubSearchAppState();
}

class _PubSearchAppState extends State<PubSearchApp> {
  static const _background = Color(0.025, 0.045, 0.055);
  static const _panel = Color(0.04, 0.075, 0.085);
  static const _teal = Color(0.39, 0.85, 0.78);
  static const _gold = Color(0.95, 0.72, 0.32);
  static const _muted = Color(0.42, 0.51, 0.56);
  static const _border = Color(0.16, 0.28, 0.30);

  final _scopeNode = FocusScopeNode(debugLabel: 'pub search');
  final _searchFocus = FocusNode(debugLabel: 'pub query');
  final _resultsFocus = FocusNode(debugLabel: 'pub results');
  final _detailStatusFocus = FocusNode(debugLabel: 'pub detail status');
  final _detailFocus = FocusNode(debugLabel: 'pub detail');
  final _detailScroll = ScrollController();

  late final TextEditingController _queryController;
  PubSearchView _view = PubSearchView.search;
  PubLoadState _searchState = PubLoadState.idle;
  PubLoadState _detailState = PubLoadState.idle;
  PackageSearchPage? _searchPage;
  PubPackageSnapshot? _package;
  PackageSort _sort = PackageSort.top;
  PackageDetailTab _activeTab = PackageDetailTab.overview;
  String? _selectedPackage;
  String? _error;
  var _selectedIndex = 0;
  var _generation = 0;
  late bool _autofocusSearch;
  var _autofocusResults = false;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _autofocusSearch = widget.autofocusSearch;
    // Both panels paint a focus-colored border from this state's build, and a
    // plain focus move never marks this element dirty on its own.
    _searchFocus.addListener(_handleFocusChanged);
    _resultsFocus.addListener(_handleFocusChanged);
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
    _searchState = PubLoadState.idle;
    _detailState = PubLoadState.idle;
    _searchPage = null;
    _package = null;
    _sort = PackageSort.top;
    _activeTab = PackageDetailTab.overview;
    _selectedPackage = null;
    _selectedIndex = 0;
    _error = null;
    _autofocusSearch = widget.autofocusSearch;
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
    widget.catalog.close();
    _queryController.dispose();
    _scopeNode.dispose();
    _searchFocus.removeListener(_handleFocusChanged);
    _resultsFocus.removeListener(_handleFocusChanged);
    _searchFocus.dispose();
    _resultsFocus.dispose();
    _detailStatusFocus.dispose();
    _detailFocus.dispose();
    _detailScroll.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _runSearch({int page = 1}) async {
    final request = ++_generation;
    final keepResultsFocus = _resultsFocus.hasFocus;
    setState(() {
      _view = PubSearchView.search;
      _searchState = PubLoadState.loading;
      _error = null;
      _autofocusResults = keepResultsFocus;
      _autofocusSearch = !keepResultsFocus;
      if (page == 1) _selectedIndex = 0;
    });
    try {
      final result = await widget.catalog.search(
        _queryController.text,
        page: page,
        sort: _sort,
      );
      if (!mounted || request != _generation) return;
      final isEmpty = result.packages.isEmpty;
      setState(() {
        _searchPage = result;
        _searchState = isEmpty ? PubLoadState.empty : PubLoadState.ready;
        if (isEmpty) {
          _autofocusSearch = true;
          _autofocusResults = false;
        }
        if (_selectedIndex >= result.packages.length) _selectedIndex = 0;
      });
      if (isEmpty) _searchFocus.requestFocus();
    } on Exception catch (error) {
      if (!mounted || request != _generation) return;
      setState(() {
        _searchState = PubLoadState.error;
        _error = '$error';
      });
    }
  }

  Future<void> _loadPackage(String name) async {
    final request = ++_generation;
    setState(() {
      _view = PubSearchView.detail;
      _detailState = PubLoadState.loading;
      _selectedPackage = name;
      _activeTab = PackageDetailTab.overview;
      _detailScroll.jumpTo(0);
      _package = null;
      _error = null;
    });
    try {
      final package = await widget.catalog.loadPackage(name);
      if (!mounted || request != _generation) return;
      setState(() {
        _package = package;
        _detailState = PubLoadState.ready;
      });
    } on Exception catch (error) {
      if (!mounted || request != _generation) return;
      setState(() {
        _detailState = PubLoadState.error;
        _error = '$error';
      });
    }
  }

  void _cycleSort() {
    final next = (_sort.index + 1) % PackageSort.values.length;
    setState(() => _sort = PackageSort.values[next]);
    unawaited(_runSearch());
  }

  void _nextPage() {
    final page = _searchPage;
    if (page == null || !page.hasNextPage) return;
    unawaited(_runSearch(page: page.page + 1));
  }

  void _previousPage() {
    final page = _searchPage;
    if (page == null || page.page <= 1) return;
    unawaited(_runSearch(page: page.page - 1));
  }

  void _returnToResults({bool focusSearch = false}) {
    _generation++;
    setState(() {
      _view = PubSearchView.search;
      _detailState = PubLoadState.idle;
      _package = null;
      _error = null;
      _autofocusSearch = focusSearch;
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
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_view == PubSearchView.detail) {
        _returnToResults();
      } else {
        widget.onQuit?.call();
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
    switch (event.character) {
      case 's':
        _cycleSort();
        return KeyEventResult.handled;
      case 'n':
        _nextPage();
        return KeyEventResult.handled;
      case 'p':
        _previousPage();
        return KeyEventResult.handled;
      case '/':
        _searchFocus.requestFocus();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    node: _scopeNode,
    onKeyEvent: _handleKey,
    child: _view == PubSearchView.search
        ? _buildSearchView()
        : _buildDetailView(),
  );

  Widget _buildSearchView() => Container(
    color: _background,
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'PUB / FIND',
              style: TextStyle(color: _teal, fontWeight: FontWeight.bold),
            ),
            const Expanded(child: SizedBox()),
            Text(
              widget.connection == PubSearchConnection.live
                  ? '● LIVE PUB.DEV'
                  : '○ OFFLINE DATA',
              style: TextStyle(
                color: widget.connection == PubSearchConnection.live
                    ? _teal
                    : _muted,
              ),
            ),
          ],
        ),
        const Text(
          'Search the Dart package ecosystem without leaving the terminal.',
          style: TextStyle(color: _muted),
        ),
        const Text(
          'Examples  riverpod   sdk:flutter   topic:terminal',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 1),
        Container(
          decoration: BoxDecoration(
            color: _panel,
            border: Border.all(color: _searchFocus.hasFocus ? _teal : _border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('QUERY', style: TextStyle(color: _muted)),
              TextInput(
                controller: _queryController,
                focusNode: _searchFocus,
                autofocus: _autofocusSearch,
                placeholder: 'package name or pub.dev search expression',
                cursorColor: _gold,
                onSubmit: () => unawaited(_runSearch()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 1),
        Row(
          children: [
            Text(
              'SORT  ${_sort.name.toUpperCase()}',
              style: const TextStyle(color: _gold),
            ),
            const Expanded(child: SizedBox()),
            Text(
              'PAGE  ${_searchPage?.page ?? 1}',
              style: const TextStyle(color: _muted),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Expanded(child: _buildResults()),
        const SizedBox(height: 1),
        const Text(
          'Enter search / inspect   Tab focus   ↑↓ choose   s sort   n/p page   Esc quit',
          style: TextStyle(color: _muted),
        ),
      ],
    ),
  );

  Widget _buildResults() => Container(
    decoration: BoxDecoration(
      color: _panel,
      border: Border.all(color: _resultsFocus.hasFocus ? _teal : _border),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
    child: switch (_searchState) {
      PubLoadState.idle => const Text(
        'Type a query and press Enter.',
        style: TextStyle(color: _muted),
      ),
      PubLoadState.loading => const Text(
        'Searching pub.dev…',
        style: TextStyle(color: _gold),
      ),
      PubLoadState.empty => const Text(
        'No packages found. Try a broader expression.',
        style: TextStyle(color: _muted),
      ),
      PubLoadState.error => _buildSearchError(),
      PubLoadState.ready => _buildResultList(),
    },
  );

  Widget _buildSearchError() {
    final previous = _searchPage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Search unavailable', style: TextStyle(color: Color.red)),
        Text(_error ?? 'Unknown error'),
        const Text(
          'Edit the query or press Enter to retry.',
          style: TextStyle(color: _muted),
        ),
        if (previous != null && previous.packages.isNotEmpty) ...[
          const SizedBox(height: 1),
          const Text('LAST RESULTS', style: TextStyle(color: _muted)),
          Expanded(child: _buildResultList()),
        ],
      ],
    );
  }

  Widget _buildResultList() {
    final page = _searchPage!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${page.packages.length} PACKAGES',
          style: const TextStyle(color: _muted),
        ),
        const SizedBox(height: 1),
        Select<String>(
          focusNode: _resultsFocus,
          autofocus: _autofocusResults,
          selectedIndex: _selectedIndex,
          height: 13,
          showScrollIndicator: true,
          backgroundColor: _panel,
          selectedBackgroundColor: const Color(0.08, 0.23, 0.22),
          selectedTextColor: _teal,
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

  Widget _buildDetailView() {
    if (_detailState == PubLoadState.ready) {
      return PubPackageDetail(
        package: _package!,
        activeTab: _activeTab,
        scrollController: _detailScroll,
        scrollFocusNode: _detailFocus,
      );
    }
    return Container(
      color: _background,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: switch (_detailState) {
        PubLoadState.loading => Focus(
          focusNode: _detailStatusFocus,
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PUB / PACKAGE', style: TextStyle(color: _teal)),
              const SizedBox(height: 1),
              Text('Loading ${_selectedPackage ?? 'package'}…'),
            ],
          ),
        ),
        PubLoadState.error => Focus(
          focusNode: _detailStatusFocus,
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Package unavailable',
                style: TextStyle(color: Color.red),
              ),
              const SizedBox(height: 1),
              Text(_error ?? 'Unknown error'),
              const SizedBox(height: 1),
              const Text(
                'r retry   Esc results',
                style: TextStyle(color: _muted),
              ),
            ],
          ),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}
