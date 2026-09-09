import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';

void main() => runTuiApp(const TaskListApp(), enableMouse: true);

class TaskListApp extends SignalWidget {
  const TaskListApp({super.key});

  @override
  Widget build(BuildContext context) {
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
          const Expanded(child: Text('Your tasks will appear here.')),
          Text('Ctrl+C exits', style: TextStyle(color: theme.textMuted)),
        ],
      ),
    );
  }
}
