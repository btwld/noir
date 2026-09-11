import 'package:noir/noir.dart';

final _surfaceColor = Color.fromHex('#FAFAFA');
final _materialBlue = Color.fromHex('#1976D2');
final _bodyTextColor = Color.fromHex('#424242');
final _mutedTextColor = Color.fromHex('#616161');

// `runTuiApp` registers the hot-reload extension itself, so Noir's packaged
// runner can rebuild this app after it swaps sources:
//
//     dart run noir:run example/counter.dart
//
// Edit any `build()` below and save to see it repaint.
void main() => runTuiApp(const CounterApp(), enableMouse: true);

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  void _incrementCounter() => setState(() => _count++);

  void _decrementCounter() => setState(() => _count--);

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!event.isPress) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.character == '+' ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _incrementCounter();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.character == '-') {
      _decrementCounter();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _handleKey,
    child: Container(
      color: _surfaceColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 3,
            child: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              color: _materialBlue,
              child: const Text(
                'Noir Counter',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: Align(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'You have pushed the button',
                    style: TextStyle(color: _bodyTextColor),
                  ),
                  Text(
                    'this many times:',
                    style: TextStyle(color: _bodyTextColor),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '$_count',
                    style: TextStyle(
                      color: _materialBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 2, bottom: 1),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Up/+ add | Down/- subtract | Enter/Space | Ctrl+C',
                    style: TextStyle(color: _mutedTextColor),
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
                const SizedBox(width: 1),
                _IncrementButton(
                  key: const ValueKey<String>('increment'),
                  onPressed: _incrementCounter,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _IncrementButton extends StatelessWidget {
  const _IncrementButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  void _handlePointerDown(MouseEvent event) {
    if (event.button == MouseButton.left) {
      onPressed();
    }
  }

  @override
  Widget build(BuildContext context) => PointerListener(
    onPointerDown: _handlePointerDown,
    child: Container(
      width: 7,
      height: 3,
      alignment: Alignment.center,
      color: _materialBlue,
      child: const Text(
        Icons.plus,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
  );
}
