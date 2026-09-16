import 'package:noir/noir.dart';

void main() => runTuiApp(const Counter());

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Column(
    spacing: 1,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text('Count: $_count'),
      Button(
        key: const ValueKey<String>('increment'),
        label: '  +  ',
        autofocus: true,
        onPressed: () => setState(() => _count++),
      ),
    ],
  );
}
