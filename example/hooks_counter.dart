import 'package:noir/hooks.dart';
import 'package:noir/noir.dart';

final _counterTheme = ThemeData.dark.copyWith(accent: Color.fromHex('#7DD3FC'));

void main() => runTuiApp(const HooksCounterApp(), enableMouse: true);

class HooksCounterApp extends HookWidget {
  const HooksCounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Hook calls stay at the top level and in the same order on every build.
    // useState owns the notifier and rebuilds this HookWidget when it changes.
    final count = useState<int>(0);
    final theme = _counterTheme;

    return Theme(
      data: theme,
      child: Container(
        color: theme.surface,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(2),
        child: Container(
          width: 42,
          decoration: BoxDecoration(
            color: theme.surfaceVariant,
            border: Border.all(color: theme.border, title: ' Hooks counter '),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 1,
            children: [
              Text(
                'Count: ${count.value}',
                style: TextStyle(
                  color: theme.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Button(
                key: const ValueKey<String>('add-one'),
                autofocus: true,
                label: '+ Add one',
                // Input-driven state belongs in the input callback.
                // useEffect is for external resources and their cleanup.
                onPressed: () => count.value++,
              ),
              Text(
                'Enter / Space / click · Ctrl+C exits',
                style: TextStyle(color: theme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
