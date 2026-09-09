import 'package:signals_core/signals_core.dart';

/// A plain Signals model: it knows nothing about Noir or about widgets.
///
/// The owner creates one model, passes it down, and disposes it once. Nothing
/// here observes a widget, so the same model works in a test with no terminal.
class FileSearchModel {
  /// Creates a model over a fixed in-memory file list.
  FileSearchModel(List<String> files) : _files = signal(List<String>.of(files));

  final Signal<List<String>> _files;

  /// The current search term.
  final Signal<String> query = signal('');

  /// Files whose path contains the current term, ignoring case.
  late final Computed<List<String>> visibleFiles = computed(() {
    final term = query.value.toLowerCase();
    return List<String>.unmodifiable(
      _files.value.where((file) => file.toLowerCase().contains(term)),
    );
  });

  /// How many files the current term matches.
  late final Computed<int> visibleCount = computed(
    () => visibleFiles.value.length,
  );

  /// Releases everything this model owns, deepest derivation first.
  void dispose() {
    visibleCount.dispose();
    visibleFiles.dispose();
    query.dispose();
    _files.dispose();
  }
}
