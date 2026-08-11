// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';

void main() {
  runTuiApp(const CounterApp());
}

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});
  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(1),
    decoration: BoxDecoration(
      color: Color.rgb(0.05, 0.05, 0.12),
      border: Border.all(),
    ),
    child: Column(
      spacing: 1,
      children: [
        const Text('Counter Demo', style: TextStyle(color: Color.green)),
        Text('Count: $_count'),
        const Text('(Press Ctrl+C to exit)'),
      ],
    ),
  );

  @override
  void initState() {
    super.initState();
    // Auto-increment once shortly after mount to demonstrate setState-driven
    // rebuilds.
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      setState(() => _count++);
    });
  }
}
