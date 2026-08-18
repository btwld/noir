// ignore_for_file: cascade_invocations
// Run with: dart run example/scrollbox_demo.dart
//
// Use ↑/↓ to scroll one line, PgUp/PgDn for a page, Home/End for ends.
// Press q to quit.

import 'dart:io' as io;

import 'package:noir/noir.dart';

void main() {
  late final TuiApp app;
  void quit() {
    app.dispose();
    io.exit(0);
  }

  app = runTuiApp(ScrollDemoApp(onQuit: quit));
  app.enableMouse();
}

class ScrollDemoApp extends StatefulWidget {
  const ScrollDemoApp({required this.onQuit, super.key});

  final void Function() onQuit;

  @override
  State<ScrollDemoApp> createState() => _ScrollDemoAppState();
}

class _ScrollDemoAppState extends State<ScrollDemoApp> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  KeyEventResult _quitOnQ(FocusNode node, KeyEvent event) {
    if (event.isPress && event.character == 'q') {
      widget.onQuit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: _quitOnQ,
    child: Container(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ScrollBox demo',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            '↑/↓ PgUp/PgDn Home/End to scroll. q to quit.',
            style: TextStyle(color: Color(0.7, 0.7, 0.7)),
          ),
          const SizedBox(height: 1),
          SizedBox(
            width: 40,
            height: 10,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0.4, 0.4, 0.6)),
              ),
              child: ScrollBox(
                controller: _scrollController,
                autofocus: true,
                onScroll: (offset) => setState(() {}),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List<Widget>.generate(
                    40,
                    (i) => Text('Line ${i + 1} — long-list content row'),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            'offset: ${_scrollController.offset.toStringAsFixed(0)} '
            '/ max: ${_scrollController.maxScrollExtent.toStringAsFixed(0)}',
            style: const TextStyle(color: Color(0.7, 0.9, 1)),
          ),
        ],
      ),
    ),
  );
}
