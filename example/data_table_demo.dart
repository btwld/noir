// Run with: dart run example/data_table_demo.dart
//
// Use ↑/↓ (or j/k), PageUp/PageDown, Home/End to move the highlight and Enter
// to open a row. Click a `file` or `state` header to sort by it; clicking the
// same header again reverses the direction. Press q to quit.
//
// Sorting is presentational in DataTable: the table reports the request and
// this demo reorders its own list, which is the only place row order lives.

import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';

typedef _Package = ({String name, int size, String state});

const _packages = <_Package>[
  (name: 'noir', size: 412, state: 'ready'),
  (name: 'characters', size: 38, state: 'ready'),
  (name: 'meta', size: 9, state: 'ready'),
  (name: 'ffi', size: 121, state: 'stale'),
  (name: 'path', size: 44, state: 'ready'),
  (name: 'collection', size: 96, state: 'ready'),
  (name: 'async', size: 77, state: 'stale'),
  (name: 'test', size: 1840, state: 'failed'),
  (name: 'analyzer', size: 5120, state: 'ready'),
  (name: 'source_gen', size: 260, state: 'stale'),
  (name: 'build', size: 310, state: 'ready'),
  (name: 'yaml', size: 52, state: 'ready'),
];

void main() => runTuiApp(const DataTableDemoApp(), enableMouse: true);

class DataTableDemoApp extends StatefulWidget {
  const DataTableDemoApp({super.key});

  @override
  State<DataTableDemoApp> createState() => _DataTableDemoAppState();
}

class _DataTableDemoAppState extends State<DataTableDemoApp> {
  late List<_Package> _rows = List.of(_packages);
  int _selected = 0;
  int? _sortColumn;
  bool _ascending = true;
  String? _opened;

  static const _columns = [
    DataColumn(label: 'package', flex: 2, sortable: true),
    DataColumn(label: 'KiB', width: 7, alignment: Alignment.centerRight),
    DataColumn(label: 'state', sortable: true),
  ];

  KeyEventResult _onAppKey(FocusNode node, KeyEvent event) {
    if (event.isPress && event.character == 'q') {
      TuiApp.exit(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _sort(int column, bool ascending) {
    setState(() {
      _sortColumn = column;
      _ascending = ascending;
      final sorted = List.of(_rows)
        ..sort((left, right) {
          final order = column == 0
              ? left.name.compareTo(right.name)
              : left.state.compareTo(right.state);
          return ascending ? order : -order;
        });
      _rows = sorted;
      _selected = 0;
    });
  }

  Widget _cell(BuildContext context, int row, int column) {
    final package = _rows[row];
    final text = switch (column) {
      0 => package.name,
      1 => '${package.size}',
      _ => package.state,
    };
    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: _stateColor(context, package.state, column)),
    );
  }

  Color _stateColor(BuildContext context, String state, int column) {
    final theme = Theme.of(context);
    if (column != 2) return theme.text;
    return switch (state) {
      'ready' => theme.success,
      'stale' => theme.warning,
      _ => theme.danger,
    };
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: _onAppKey,
    child: DemoScaffold(
      title: 'DataTable demo',
      hint: '↑/↓ to move · Enter to open · click a header to sort · q quits',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataTable(
            autofocus: true,
            columns: _columns,
            rowCount: _rows.length,
            height: 9,
            selectedIndex: _selected,
            sortColumnIndex: _sortColumn,
            sortAscending: _ascending,
            showScrollIndicator: true,
            cellBuilder: _cell,
            onSort: _sort,
            onChanged: (index) => setState(() => _selected = index),
            onSelect: (index) => setState(() => _opened = _rows[index].name),
          ),
          const SizedBox(height: 1),
          Text(
            _opened == null ? 'No row opened yet.' : 'Opened $_opened.',
            style: TextStyle(color: Theme.of(context).success),
          ),
        ],
      ),
    ),
  );
}
