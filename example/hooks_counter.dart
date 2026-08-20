import 'package:noir/hooks.dart';
import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';

final _counterAccent = Color.fromHex('#7DD3FC');
final _counterTheme = ThemeData.dark.copyWith(
  accent: _counterAccent,
  info: _counterAccent,
);

void main() => runTuiApp(const HooksCounterApp(), enableMouse: true);

class HooksCounterApp extends HookWidget {
  const HooksCounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Hook calls stay at the top level and in the same order on every build.
    // useState owns the notifier and rebuilds this HookWidget when it changes.
    final count = useState<int>(0);

    return Theme(
      data: _counterTheme,
      child: _CounterView(
        count: count.value,
        // Input-driven state belongs in the input callback. useEffect is for
        // synchronizing an external resource and its cleanup, not button work.
        onIncrement: () => count.value++,
      ),
    );
  }
}

class _CounterView extends StatelessWidget {
  const _CounterView({required this.count, required this.onIncrement});

  final int count;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DemoScaffold(
      title: 'Hooks counter',
      hint: 'Enter / Space / click to add one · Ctrl+C exits',
      titleTrailing: const [Badge(label: 'HOOKS', variant: BadgeVariant.info)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 1,
        children: [
          DemoPanel(
            title: 'Current count',
            width: 36,
            child: Text(
              '$count',
              style: TextStyle(
                color: theme.accent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Button(autofocus: true, label: '+ Add one', onPressed: onIncrement),
        ],
      ),
    );
  }
}
