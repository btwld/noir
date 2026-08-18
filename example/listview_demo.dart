// Run with: dart run example/listview_demo.dart
//
// Tab moves between the two lists. In the selectable list use ↑/↓ (or j/k),
// PageUp/PageDown, Home/End, and Enter; the plain list scrolls with the same
// keys and with the mouse wheel. Press q to quit.
//
// Both lists hold 500 rows and build only the rows on screen. The counter
// below each list is the running total of row-builder calls since start-up
// (one frame behind, since it is laid out before the list rebuilds), so it
// grows by one window's worth per frame rather than by 500.

import 'dart:io' as io;

import 'package:noir/noir.dart';

const _rowCount = 500;

void main() {
  late final TuiApp app;
  void quit() {
    app.dispose();
    io.exit(0);
  }

  app = runTuiApp(ListViewDemoApp(onQuit: quit));
  app.enableMouse();
}

class ListViewDemoApp extends StatefulWidget {
  const ListViewDemoApp({required this.onQuit, super.key});

  /// Invoked when the user presses `q` outside a list.
  final void Function() onQuit;

  @override
  State<ListViewDemoApp> createState() => _ListViewDemoAppState();
}

class _ListViewDemoAppState extends State<ListViewDemoApp> {
  final _selectableFocus = FocusNode();
  final _plainFocus = FocusNode();
  int _selected = 0;
  int? _confirmed;
  var _selectableBuilds = 0;
  var _plainBuilds = 0;

  @override
  void dispose() {
    _selectableFocus.dispose();
    _plainFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onAppKey(FocusNode node, KeyEvent event) {
    if (event.isPress && event.character == 'q') {
      widget.onQuit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _selectableRow(BuildContext context, int index, bool selected) {
    _selectableBuilds++;
    return Text(
      '${selected ? '▶' : ' '} Item ${index.toString().padLeft(3, '0')}',
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        color: selected ? Color.white : const Color(0.7, 0.7, 0.7),
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _plainRow(BuildContext context, int index, bool selected) {
    _plainBuilds++;
    return Text(
      'log line ${index.toString().padLeft(3, '0')}',
      maxLines: 1,
      softWrap: false,
      style: const TextStyle(color: Color(0.6, 0.75, 0.6)),
    );
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: _onAppKey,
    child: Container(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ListView demo — Tab switches lists, q quits',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 1),
          Row(
            spacing: 3,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'selectable',
                    style: TextStyle(color: Color(0.5, 0.8, 1)),
                  ),
                  SizedBox(
                    width: 22,
                    child: ListView(
                      focusNode: _selectableFocus,
                      autofocus: true,
                      itemCount: _rowCount,
                      selectedIndex: _selected,
                      showScrollIndicator: true,
                      itemBuilder: _selectableRow,
                      onChanged: (index) => setState(() => _selected = index),
                      onSelect: (index) => setState(() => _confirmed = index),
                    ),
                  ),
                  Text(
                    'rows built: $_selectableBuilds',
                    style: const TextStyle(color: Color(0.55, 0.55, 0.55)),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'plain scroll',
                    style: TextStyle(color: Color(0.5, 0.8, 1)),
                  ),
                  SizedBox(
                    width: 22,
                    child: ListView(
                      focusNode: _plainFocus,
                      itemCount: _rowCount,
                      showScrollIndicator: true,
                      itemBuilder: _plainRow,
                    ),
                  ),
                  Text(
                    'rows built: $_plainBuilds',
                    style: const TextStyle(color: Color(0.55, 0.55, 0.55)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            _confirmed == null
                ? 'Enter or click a row to confirm it.'
                : 'Confirmed item $_confirmed of $_rowCount.',
            style: const TextStyle(color: Color(0.4, 1, 0.4)),
          ),
        ],
      ),
    ),
  );
}
