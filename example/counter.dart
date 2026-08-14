// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';

final _surfaceColor = Color.fromHex('#FAFAFA');
final _materialBlue = Color.fromHex('#1976D2');
final _darkMaterialBlue = Color.fromHex('#0D47A1');
final _bodyTextColor = Color.fromHex('#424242');
final _mutedTextColor = Color.fromHex('#616161');

const _roundedBorderCharacters = <int>[
  0x256D,
  0x256E,
  0x2570,
  0x256F,
  0x2500,
  0x2502,
  0x252C,
  0x2534,
  0x251C,
  0x2524,
  0x253C,
];

void main() {
  final app = runTuiApp(const CounterApp());
  app.enableMouse();
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
              decoration: BoxDecoration(
                color: _materialBlue,
                border: Border(
                  color: _darkMaterialBlue,
                  sides: const BorderSides(
                    top: false,
                    right: false,
                    left: false,
                  ),
                ),
              ),
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
                _IncrementButton(onPressed: _incrementCounter),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _IncrementButton extends StatelessWidget {
  const _IncrementButton({required this.onPressed});

  final VoidCallback onPressed;

  void _handlePointerDown(MouseEvent event) {
    if (event.button == MouseButton.left) {
      onPressed();
    }
  }

  @override
  Widget build(BuildContext context) => PointerListener(
    onPointerDown: _handlePointerDown,
    child: SizedBox(
      width: 7,
      height: 3,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(
            color: _materialBlue,
            borderChars: _roundedBorderCharacters,
          ),
        ),
        child: Container(
          alignment: Alignment.center,
          color: _materialBlue,
          width: 5,
          height: 1,
          child: const Text(
            '+',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    ),
  );
}
