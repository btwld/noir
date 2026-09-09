import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';

void main() => runTuiApp(const TaskListApp(), enableMouse: true);

/// A task list with hook-owned input and derived Signals state.
class TaskListApp extends SignalWidget {
  /// Creates the task-list screen.
  const TaskListApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Call hooks in the same order on every build. Each owns its lifetime.
    final draft = useTextEditingController();
    final tasks = useSignal(<({int id, String title, bool done})>[
      (id: 0, title: 'Read the hooks guide', done: false),
      (id: 1, title: 'Run the counter example', done: true),
      (id: 2, title: 'Build a Signals app', done: false),
    ]);
    final remaining = useComputed(
      () => tasks.value.where((task) => !task.done).length,
      keys: [tasks],
    );
    final hideCompleted = useState(false);
    final nextId = useRef(3);
    final theme = Theme.of(context);
    final visible = tasks.value
        .where((task) => !hideCompleted.value || !task.done)
        .toList();

    void addTask() {
      final title = draft.text.trim();
      if (title.isEmpty) return;
      // Replace the list so Signals observes the change. IDs survive filtering.
      tasks.value = [
        ...tasks.value,
        (id: nextId.value++, title: title, done: false),
      ];
      draft.clear();
    }

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
          Row(
            spacing: 1,
            children: [
              Expanded(
                child: TextInput(
                  key: const ValueKey<String>('task-draft'),
                  controller: draft,
                  autofocus: true,
                  placeholder: 'New task',
                  onSubmit: addTask,
                ),
              ),
              Button(
                key: const ValueKey<String>('add-task'),
                label: 'Add',
                onPressed: addTask,
              ),
            ],
          ),
          Text('${remaining.value} of ${tasks.value.length} remaining'),
          Checkbox(
            key: const ValueKey<String>('hide-completed'),
            label: 'Hide completed',
            value: hideCompleted.value,
            onChanged: (value) => hideCompleted.value = value,
          ),
          Expanded(
            child: ScrollBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (visible.isEmpty)
                    Text(
                      tasks.value.isEmpty
                          ? 'Add your first task.'
                          : 'All done!',
                    ),
                  for (final task in visible)
                    Checkbox(
                      key: ValueKey<String>('task-${task.id}'),
                      label: task.title,
                      value: task.done,
                      onChanged: (done) {
                        tasks.value = [
                          for (final item in tasks.value)
                            if (item.id == task.id)
                              (id: item.id, title: item.title, done: done)
                            else
                              item,
                        ];
                      },
                    ),
                ],
              ),
            ),
          ),
          Button(
            key: const ValueKey<String>('clear-completed'),
            label: 'Clear completed',
            onPressed: remaining.value == tasks.value.length
                ? null
                : () {
                    tasks.value = [
                      for (final task in tasks.value)
                        if (!task.done) task,
                    ];
                  },
          ),
          Text(
            'Enter adds · Tab moves · Space toggles · Ctrl+C exits',
            style: TextStyle(color: theme.textMuted),
          ),
        ],
      ),
    );
  }
}
