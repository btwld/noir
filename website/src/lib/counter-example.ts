export const expectedCounterBoundary =
  'Expected cell output; colors and the cursor depend on the terminal.';

export const counterAppSource = `import 'package:noir/noir.dart';

void main() => runTuiApp(const CounterApp(), enableMouse: true);

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  void _increment() {
    setState(() {
      _count++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 1,
        children: [
          Text('Count: $_count'),
          Button(
            autofocus: true,
            label: '+ Add one',
            onPressed: _increment,
          ),
        ],
      ),
    );
  }
}`;

export const counterStateSource = `class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  void _increment() {
    setState(() {
      _count++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 1,
        children: [
          Text('Count: $_count'),
          Button(
            autofocus: true,
            label: '+ Add one',
            onPressed: _increment,
          ),
        ],
      ),
    );
  }
}`;

// Container padding 1, Column spacing 1, Button horizontal padding 1.
export const counterFrameAfterIncrement = [
  '',
  ' Count: 1',
  '',
  '  + Add one',
  '',
].join('\n');
