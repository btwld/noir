import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/tui_test_app.dart';

// The Counter copies the Getting started snippet, including its block-bodied
// build method.
// ignore_for_file: prefer_expression_function_bodies

void main() {
  test('getting-started counter cells after one activation', () async {
    final app = createTuiTestApp(const CounterApp(), width: 20, height: 8);
    addTearDown(app.dispose);
    app.pumpFrame();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    app.mockInput.pressEnter();
    app.pumpFrame();
    final lines = app.captureFrame().toLines();
    expect(lines.take(5), ['', ' Count: 1', '', '  + Add one', '']);
  });
}

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
          Button(autofocus: true, label: '+ Add one', onPressed: _increment),
        ],
      ),
    );
  }
}
