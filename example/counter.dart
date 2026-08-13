// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';

void main() {
  final app = runTuiApp(const CounterApp());
  // Lets a hot-reload driver rebuild this app after it swaps sources:
  //
  //     dart run scripts/hot_reload_driver.dart example/counter.dart
  //
  // Edit any `build()` below and save to see it repaint. Registering costs
  // nothing when no driver is attached.
  registerHotReloadExtension(app);
}

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!event.isPress) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.character == '+') {
      setState(() => _count++);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.character == '-') {
      setState(() => _count--);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _handleKey,
    child: Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: Color.rgb(0.05, 0.05, 0.12),
        border: Border.all(color: const Color(0.2, 0.25, 0.35)),
      ),
      child: Column(
        spacing: 1,
        children: [
          const Text('Counter Demo', style: TextStyle(color: Color.green)),
          Text('Count: $_count'),
          const Text('Up/+ increment | Down/- decrement'),
          const Text('Ctrl+C exit'),
        ],
      ),
    ),
  );
}
