// Run with: dart run example/autocomplete_demo.dart
// The initial `noi` query demonstrates application-owned debounce and stale
// response protection. Type to replace or refine it, Tab into suggestions,
// use arrows to move, Enter or click to choose, and Escape to clear results or
// exit.

import 'dart:async';

import 'package:noir/noir.dart';

import 'src/shared/demo_scaffold.dart';

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
  var _status = AutocompleteStatus.idle;
  var _suggestions = const <PackageSuggestion>[];
  PackageSuggestion? _selected;

  String get query => _query;
  AutocompleteStatus get status => _status;
  List<PackageSuggestion> get suggestions => _suggestions;
  PackageSuggestion? get selected => _selected;
  bool get panelVisible => _status != AutocompleteStatus.idle;

  void updateQuery(String rawQuery) {
    final query = rawQuery.trim();
    final request = _invalidatePendingRequest();
    _query = query;
    _selected = null;

    if (query.length < 2) {
      _status = AutocompleteStatus.idle;
      _suggestions = const [];
      notifyListeners();
      return;
    }

    _status = AutocompleteStatus.loading;
    _suggestions = const [];
    notifyListeners();
    _debounceTimer = Timer(debounce, () => unawaited(_load(query, request)));
  }

  Future<void> _load(String query, int request) async {
    try {
      final suggestions = await source.suggest(query);
      if (_disposed || request != _generation) return;
      _suggestions = List<PackageSuggestion>.unmodifiable(suggestions);
      _status = suggestions.isEmpty
          ? AutocompleteStatus.empty
          : AutocompleteStatus.ready;
      notifyListeners();
    } on Object {
      if (_disposed || request != _generation) return;
      _suggestions = const [];
      _status = AutocompleteStatus.error;
      notifyListeners();
    }
  }

  PackageSuggestion? choose(PackageSuggestion suggestion) {
    if (!_suggestions.contains(suggestion)) return null;
    _invalidatePendingRequest();
    _query = suggestion.name;
    _selected = suggestion;
    _suggestions = const [];
    _status = AutocompleteStatus.idle;
    notifyListeners();
    return suggestion;
  }

  void hideSuggestions() {
    if (!panelVisible) return;
    _invalidatePendingRequest();
    _suggestions = const [];
    _status = AutocompleteStatus.idle;
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
  late PackageAutocompleteController _controller;

  @override
  void initState() {
    super.initState();
    _createController();
    _queryFocus.addListener(_handleChanged);
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
    _queryController.dispose();
    super.dispose();
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  void _choose(PackageSuggestion option) {
    final suggestion = _controller.choose(option);
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
              child: Panel(
                title: 'Package',
                focused: _queryFocus.hasFocus,
                child: Autocomplete<PackageSuggestion>(
                  key: const ValueKey<String>('package-query'),
                  controller: _queryController,
                  focusNode: _queryFocus,
                  autofocus: true,
                  inputBackgroundColor: Color.transparent,
                  options: _controller.suggestions,
                  status: _controller.status,
                  optionBuilder: _buildSuggestionRow,
                  onChanged: _controller.updateQuery,
                  onSelected: _choose,
                  onDismiss: _controller.hideSuggestions,
                  loadingBuilder: (context) =>
                      const Text(' Searching packages…'),
                  emptyBuilder: (context) =>
                      const Text(' No matching packages.'),
                  errorBuilder: (context) =>
                      const Text(' Suggestions unavailable.'),
                ),
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

  Widget _buildSuggestionRow(
    BuildContext context,
    PackageSuggestion suggestion,
    bool selected,
  ) {
    final theme = Theme.of(context);
    final foreground = selected ? theme.selectedForeground : theme.text;
    final weight = selected ? FontWeight.bold : FontWeight.normal;
    return Container(
      padding: const EdgeInsets.only(left: 2, right: 1),
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
      AutocompleteStatus.loading =>
        'Searching the demo catalog for ${_controller.query}…',
      AutocompleteStatus.error => 'Try editing the query to retry.',
      AutocompleteStatus.empty => 'Try a broader package name.',
      AutocompleteStatus.idle ||
      AutocompleteStatus.ready => 'Choose a package to inspect.',
    }, style: TextStyle(color: theme.textMuted));
  }
}
