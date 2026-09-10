// Run with: dart run example/scrollbox_demo.dart
//
// Use ↑/↓ to scroll one line, PgUp/PgDn for a page, Home/End for ends.
// Press q to quit.

import 'package:noir/noir.dart';

import 'src/shared/demo_scaffold.dart';

void main() => runTuiApp(const ScrollDemoApp(), enableMouse: true);

class ScrollDemoApp extends StatefulWidget {
  const ScrollDemoApp({super.key});

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
      TuiApp.exit(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _quitOnQ,
      child: DemoScaffold(
        title: 'ScrollBox demo',
        hint: '↑/↓ PgUp/PgDn Home/End to scroll. q to quit.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Panel(
              title: 'Lines',
              width: 42,
              height: 10,
              child: SizedBox(
                width: 40,
                height: 8,
                child: ScrollBox(
                  key: const ValueKey<String>('content'),
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
              style: TextStyle(color: theme.info),
            ),
          ],
        ),
      ),
    );
  }
}
