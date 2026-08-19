// Run with: dart run example/listview_demo.dart
//
// Tab moves between the two lists. In the selectable list use ↑/↓ (or j/k),
// PageUp/PageDown, Home/End, and Enter; the plain list scrolls with the same
// keys and with the mouse wheel. Press q to quit.
//
// Both lists hold 500 rows and build only the rows on screen. The counter
// below each list is the running total of row-builder calls since start-up
// (one frame behind, since it is laid out before the list rebuilds), so it
// grows by one window's worth per frame rather than by 500. The focused
// list is the one whose highlight uses the selection accent.

import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';

const _rowCount = 500;

void main() => runTuiApp(const ListViewDemoApp(), enableMouse: true);

class ListViewDemoApp extends StatefulWidget {
  const ListViewDemoApp({super.key});

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
  void initState() {
    super.initState();
    _selectableFocus.addListener(_rebuild);
    _plainFocus.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _selectableFocus
      ..removeListener(_rebuild)
      ..dispose();
    _plainFocus
      ..removeListener(_rebuild)
      ..dispose();
    super.dispose();
  }

  KeyEventResult _onAppKey(FocusNode node, KeyEvent event) {
    if (event.isPress && event.character == 'q') {
      TuiApp.exit(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _selectableRow(BuildContext context, int index, bool selected) {
    _selectableBuilds++;
    final theme = Theme.of(context);
    return Text(
      '${selected ? '▶' : ' '} Item ${index.toString().padLeft(3, '0')}',
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        color: selected ? theme.selectedForeground : theme.text,
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
      style: TextStyle(color: Theme.of(context).textMuted),
    );
  }

  Widget _pane({
    required String label,
    required Widget list,
    required int builds,
    required bool focused,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DemoPanel(
          title: label,
          focused: focused,
          width: 24,
          height: 10,
          child: SizedBox(width: 22, child: list),
        ),
        Text('rows built: $builds', style: TextStyle(color: theme.textMuted)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: _onAppKey,
    child: DemoScaffold(
      title: 'ListView demo',
      hint: 'Tab switches lists · q quits',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: 3,
            children: [
              _pane(
                label: 'selectable',
                focused: _selectableFocus.hasFocus,
                builds: _selectableBuilds,
                list: ListView(
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
              _pane(
                label: 'plain scroll',
                focused: _plainFocus.hasFocus,
                builds: _plainBuilds,
                list: ListView(
                  focusNode: _plainFocus,
                  itemCount: _rowCount,
                  showScrollIndicator: true,
                  itemBuilder: _plainRow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            _confirmed == null
                ? 'Enter or click a row to confirm it.'
                : 'Confirmed item $_confirmed of $_rowCount.',
            style: TextStyle(color: Theme.of(context).success),
          ),
        ],
      ),
    ),
  );
}
