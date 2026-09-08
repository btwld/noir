import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';

import 'models/file_search_model.dart';

const _files = <String>[
  'lib/noir_signals.dart',
  'lib/src/hooks/framework.dart',
  'lib/src/hooks/signals.dart',
  'lib/src/signal_value_builder.dart',
  'example/counter.dart',
  'example/file_search.dart',
  'test/signals/reactivity_test.dart',
];

void main() => runTuiApp(const FileSearchApp(), enableMouse: true);

/// Filters a fixed file list from a text field backed by a Signals model.
class FileSearchApp extends HookWidget {
  /// Creates the search screen.
  const FileSearchApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The hook owns the controller and the model for this mounted slot.
    final controller = useTextEditingController();
    final model = useMemoized(() => FileSearchModel(_files));
    useOnDispose(model.dispose);

    // The field owns text, selection, and caret. This bridges its edits into
    // the model; it is not a two-way binding.
    final visible = useSignalValue(model.visibleFiles);

    return Container(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 1,
        children: [
          TextInput(
            key: const ValueKey<String>('query'),
            controller: controller,
            autofocus: true,
            placeholder: 'Filter files',
            onChanged: (text) => model.query.value = text,
          ),
          // Only this subtree rebuilds when the count changes.
          SignalValueBuilder<int>(
            signal: model.visibleCount,
            builder: (context, count) => Text('$count files'),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final file in visible) Text(file)],
          ),
          const Text('Type to filter · Ctrl+C exits'),
        ],
      ),
    );
  }
}
