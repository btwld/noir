import 'dart:async';

import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';

void main() => runTuiApp(const AutocompleteDemoApp(), enableMouse: true);

/// One package-name result owned by an application suggestion source.
final class PackageSuggestion {
  const PackageSuggestion({required this.name, required this.description});

  final String name;
  final String description;
}

/// Application seam for local, remote, or test-backed package suggestions.
abstract interface class PackageSuggestionSource {
  Future<List<PackageSuggestion>> suggest(String query);
}

/// Deterministic source used by the runnable example and headless catalog.
final class DemoPackageSuggestionSource implements PackageSuggestionSource {
  const DemoPackageSuggestionSource();

  static const _catalog = <PackageSuggestion>[
    PackageSuggestion(
      name: 'noir',
      description: 'Reactive terminal UI framework',
    ),
    PackageSuggestion(
      name: 'noir_cli',
      description: 'Command-line tooling for Noir apps',
    ),
    PackageSuggestion(
      name: 'noir_lints',
      description: 'Opinionated analysis rules',
    ),
    PackageSuggestion(
      name: 'noir_test',
      description: 'Test helpers for terminal apps',
    ),
    PackageSuggestion(
      name: 'noir_hooks',
      description: 'Composable widget lifecycle hooks',
    ),
    PackageSuggestion(
      name: 'riverpod',
      description: 'Reactive caching and data binding',
    ),
  ];

  @override
  Future<List<PackageSuggestion>> suggest(String query) => Future.value([
    for (final package in _catalog)
      if (package.name.contains(query.toLowerCase())) package,
  ]);
}

enum PackageSuggestionStatus { idle, loading, ready, empty, error }

/// Owns debounce and request freshness independently from terminal rendering.
final class PackageAutocompleteController extends ChangeNotifier {
  PackageAutocompleteController({
    required this.source,
    this.debounce = const Duration(milliseconds: 180),
  });

  final PackageSuggestionSource source;
  final Duration debounce;

  Timer? _debounceTimer;
  var _generation = 0;
  var _disposed = false;
  var _query = '';
  var _status = PackageSuggestionStatus.idle;
  var _suggestions = const <PackageSuggestion>[];
  var _highlightedIndex = 0;
  PackageSuggestion? _selected;

  String get query => _query;
  PackageSuggestionStatus get status => _status;
  List<PackageSuggestion> get suggestions => _suggestions;
  int get highlightedIndex => _highlightedIndex;
  PackageSuggestion? get selected => _selected;
  bool get panelVisible => _status != PackageSuggestionStatus.idle;

  void updateQuery(String rawQuery) {
    final query = rawQuery.trim();
    final request = _invalidatePendingRequest();
    _query = query;
    _selected = null;
    _highlightedIndex = 0;

    if (query.length < 2) {
      _status = PackageSuggestionStatus.idle;
      _suggestions = const [];
      notifyListeners();
      return;
    }

    _status = PackageSuggestionStatus.loading;
    _suggestions = const [];
    notifyListeners();
    _debounceTimer = Timer(debounce, () => unawaited(_load(query, request)));
  }

  Future<void> _load(String query, int request) async {
    try {
      final suggestions = await source.suggest(query);
      if (_disposed || request != _generation) return;
      _suggestions = List<PackageSuggestion>.unmodifiable(suggestions);
      _highlightedIndex = 0;
      _status = suggestions.isEmpty
          ? PackageSuggestionStatus.empty
          : PackageSuggestionStatus.ready;
      notifyListeners();
    } on Object {
      if (_disposed || request != _generation) return;
      _suggestions = const [];
      _status = PackageSuggestionStatus.error;
      notifyListeners();
    }
  }

  void highlight(int index) {
    if (_suggestions.isEmpty) return;
    final next = index.clamp(0, _suggestions.length - 1);
    if (next == _highlightedIndex) return;
    _highlightedIndex = next;
    notifyListeners();
  }

  PackageSuggestion? choose(int index) {
    if (index < 0 || index >= _suggestions.length) return null;
    final suggestion = _suggestions[index];
    _invalidatePendingRequest();
    _query = suggestion.name;
    _selected = suggestion;
    _highlightedIndex = 0;
    _suggestions = const [];
    _status = PackageSuggestionStatus.idle;
    notifyListeners();
    return suggestion;
  }

  void hideSuggestions() {
    if (!panelVisible) return;
    _invalidatePendingRequest();
    _suggestions = const [];
    _highlightedIndex = 0;
    _status = PackageSuggestionStatus.idle;
    notifyListeners();
  }

  int _invalidatePendingRequest() {
    _debounceTimer?.cancel();
    return ++_generation;
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidatePendingRequest();
    super.dispose();
  }
}

/// An input and borderless suggestion list composed as one attached surface.
class AutocompleteDemoApp extends StatefulWidget {
  const AutocompleteDemoApp({
    super.key,
    this.source,
    this.debounce = const Duration(milliseconds: 180),
  });

  final PackageSuggestionSource? source;
  final Duration debounce;

  @override
  State<AutocompleteDemoApp> createState() => _AutocompleteDemoAppState();
}

class _AutocompleteDemoAppState extends State<AutocompleteDemoApp> {
  final _queryController = TextEditingController(text: 'noi');
  final _queryFocus = FocusNode(debugLabel: 'package-query');
  final _suggestionsFocus = FocusNode(debugLabel: 'package-suggestions');
  late PackageAutocompleteController _controller;

  @override
  void initState() {
    super.initState();
    _createController();
    _queryFocus.addListener(_handleChanged);
    _suggestionsFocus.addListener(_handleChanged);
  }

  void _createController() {
    _controller = PackageAutocompleteController(
      source: widget.source ?? const DemoPackageSuggestionSource(),
      debounce: widget.debounce,
    );
    _controller.updateQuery(_queryController.text);
    _controller.addListener(_handleChanged);
  }

  @override
  void didUpdateWidget(AutocompleteDemoApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.source, widget.source) &&
        oldWidget.debounce == widget.debounce) {
      return;
    }
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    _createController();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    _queryFocus
      ..removeListener(_handleChanged)
      ..dispose();
    _suggestionsFocus
      ..removeListener(_handleChanged)
      ..dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  void _choose(int index) {
    final suggestion = _controller.choose(index);
    if (suggestion == null) return;
    _queryController.text = suggestion.name;
    if (_queryFocus.isAttached) _queryFocus.requestFocus();
  }

  KeyEventResult _dismiss(BuildContext context) {
    if (_controller.panelVisible) {
      _controller.hideSuggestions();
      if (_queryFocus.isAttached) _queryFocus.requestFocus();
      return KeyEventResult.handled;
    }
    TuiApp.exit(context);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        DismissIntent: CallbackAction<DismissIntent>(
          (intent, context) => _dismiss(context),
        ),
      },
      child: DemoScaffold(
        title: 'Package autocomplete',
        hint: 'Type a package name. Tab enters suggestions; Enter chooses.',
        child: Column(
          spacing: 1,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DemoPanel(
                    title: 'Package',
                    focused: _queryFocus.hasFocus,
                    child: TextInput(
                      key: const ValueKey<String>('package-query'),
                      controller: _queryController,
                      focusNode: _queryFocus,
                      autofocus: true,
                      backgroundColor: Color.transparent,
                      onChanged: _controller.updateQuery,
                      onSubmit: () => _choose(_controller.highlightedIndex),
                    ),
                  ),
                  if (_controller.panelVisible)
                    _buildSuggestionSurface(context),
                ],
              ),
            ),
            _buildSummary(context),
            Text(
              'Tab suggestions · Enter choose · Esc clear/exit',
              style: TextStyle(color: Theme.of(context).textMuted),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildSuggestionSurface(BuildContext context) {
    final theme = Theme.of(context);
    final child = switch (_controller.status) {
      PackageSuggestionStatus.loading => const Text('  Searching packages…'),
      PackageSuggestionStatus.empty => const Text('  No matching packages.'),
      PackageSuggestionStatus.error => const Text('  Suggestions unavailable.'),
      PackageSuggestionStatus.ready => ListView(
        key: const ValueKey<String>('package-suggestions'),
        itemCount: _controller.suggestions.length,
        height: _controller.suggestions.length.clamp(1, 5),
        selectedIndex: _controller.highlightedIndex,
        focusNode: _suggestionsFocus,
        backgroundColor: Color.transparent,
        onChanged: _controller.highlight,
        onSelect: _choose,
        itemBuilder: _buildSuggestionRow,
      ),
      PackageSuggestionStatus.idle => const SizedBox.shrink(),
    };

    return Container(color: theme.surfaceVariant, child: child);
  }

  Widget _buildSuggestionRow(BuildContext context, int index, bool selected) {
    final theme = Theme.of(context);
    final suggestion = _controller.suggestions[index];
    final foreground = selected ? theme.selectedForeground : theme.text;
    final weight = selected ? FontWeight.bold : FontWeight.normal;
    return Container(
      padding: const EdgeInsets.only(left: 3, right: 1),
      child: Row(
        spacing: 1,
        children: [
          Text(
            selected ? Icons.chevronRight : ' ',
            style: TextStyle(color: foreground, fontWeight: weight),
          ),
          SizedBox(
            width: 16,
            child: Text(
              suggestion.name,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground, fontWeight: weight),
            ),
          ),
          Expanded(
            child: Text(
              suggestion.description,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: selected ? foreground : theme.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _controller.selected;
    if (selected != null) {
      return Text(
        'Selected  ${selected.name} · ${selected.description}',
        style: TextStyle(color: theme.text),
      );
    }
    return Text(switch (_controller.status) {
      PackageSuggestionStatus.loading =>
        'Searching the demo catalog for ${_controller.query}…',
      PackageSuggestionStatus.error => 'Try editing the query to retry.',
      PackageSuggestionStatus.empty => 'Try a broader package name.',
      PackageSuggestionStatus.idle ||
      PackageSuggestionStatus.ready => 'Choose a package to inspect.',
    }, style: TextStyle(color: theme.textMuted));
  }
}
