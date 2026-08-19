// ignore_for_file: cascade_invocations
// Run with: dart run example/select_demo.dart
//
// Use ↑/↓ (or j/k) to move the highlight, Enter to confirm. Press q to quit.
// Demonstrates Select<T> rendering, focus, keyboard navigation, and the
// onChanged vs onSelect callback split.

import 'dart:io' as io;

import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';

void main() {
  late final TuiApp app;
  void quit() {
    app.dispose();
    io.exit(0);
  }

  app = runTuiApp(SelectDemoApp(onQuit: quit));
  app.enableMouse();
}

class SelectDemoApp extends StatefulWidget {
  const SelectDemoApp({required this.onQuit, super.key});

  final void Function() onQuit;

  @override
  State<SelectDemoApp> createState() => _SelectDemoAppState();
}

class _SelectDemoAppState extends State<SelectDemoApp> {
  String _status = 'Move with ↑/↓ or j/k. Enter to confirm. q to quit.';
  String? _confirmed;
  final _focusNode = FocusNode();

  static const _options = <SelectOption<String>>[
    SelectOption(name: 'Apple', description: 'crunchy', value: 'apple'),
    SelectOption(name: 'Banana', description: 'soft', value: 'banana'),
    SelectOption(name: 'Cherry', description: 'tart', value: 'cherry'),
    SelectOption(name: 'Date', description: 'sweet', value: 'date'),
    SelectOption(name: 'Elderberry', description: 'rare', value: 'elderberry'),
    SelectOption(name: 'Fig', description: 'fancy', value: 'fig'),
  ];

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onAppKey(FocusNode node, KeyEvent event) {
    if (event.isPress && event.character == 'q') {
      widget.onQuit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _onAppKey,
      child: DemoScaffold(
        title: 'Select demo',
        hint: _status,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DemoPanel(
              child: Select<String>(
                focusNode: _focusNode,
                autofocus: true,
                height: 6,
                options: _options,
                showScrollIndicator: true,
                onChanged: (i, opt) =>
                    setState(() => _status = 'Highlight: ${opt.name}'),
                onSelect: (i, opt) => setState(() => _confirmed = opt.value),
              ),
            ),
            const SizedBox(height: 1),
            if (_confirmed != null)
              Text(
                'You picked: $_confirmed',
                style: TextStyle(
                  color: theme.success,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
