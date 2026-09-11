import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';

void main() => runTuiApp(const TaskListApp(), enableMouse: true);

class TaskListApp extends SignalWidget {
  const TaskListApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = useSignal(<({int id, String title, bool done})>[
      (id: 0, title: 'Read the hooks guide', done: false),
      (id: 1, title: 'Run the counter example', done: true),
      (id: 2, title: 'Build a Signals app', done: false),
    ]);
    final remaining = useComputed(
      () => tasks.value.where((task) => !task.done).length,
    );
    final theme = Theme.of(context);

    return Container(
      color: theme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 1,
        children: [
          const Text(
            'Task list',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text('${remaining.value} of ${tasks.value.length} remaining'),
          Expanded(
            child: ScrollBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final task in tasks.value) Text(task.title)],
              ),
            ),
          ),
          Text('Ctrl+C exits', style: TextStyle(color: theme.textMuted)),
        ],
      ),
    );
  }
}
