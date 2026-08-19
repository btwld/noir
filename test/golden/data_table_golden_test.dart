import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

const _rows = [
  ('parser.dart', 128, 'ok'),
  ('render.dart', 4096, 'busy'),
  ('theme.dart', 12, 'ok'),
  ('driver.dart', 640, 'failed'),
  ('buffer.dart', 33, 'ok'),
];

const _columns = [
  DataColumn(label: 'file', flex: 2, sortable: true),
  DataColumn(label: 'bytes', width: 7, alignment: Alignment.centerRight),
  DataColumn(label: 'state', sortable: true),
];

Widget _cell(BuildContext context, int row, int column) => Text(
  switch (column) {
    0 => _rows[row].$1,
    1 => '${_rows[row].$2}',
    _ => _rows[row].$3,
  },
  maxLines: 1,
  softWrap: false,
  overflow: TextOverflow.ellipsis,
);

void main() {
  group('DataTable Golden', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester(width: 32, height: 8);
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('header and aligned body columns', () async {
      const widget = DataTable(
        columns: _columns,
        rowCount: 5,
        height: 7,
        cellBuilder: _cell,
      );
      await tester.expectGolden(
        widget,
        'data_table_plain',
        updateGoldens: _updateGoldens,
      );
    });

    test('a sorted column and a highlighted row', () async {
      const widget = DataTable(
        columns: _columns,
        rowCount: 5,
        height: 7,
        selectedIndex: 2,
        sortColumnIndex: 1,
        sortAscending: false,
        cellBuilder: _cell,
      );
      await tester.expectGolden(
        widget,
        'data_table_sorted_selected',
        updateGoldens: _updateGoldens,
      );
    });

    test('a short body window keeps the scroll indicator', () async {
      const widget = DataTable(
        columns: _columns,
        rowCount: 5,
        height: 4,
        showScrollIndicator: true,
        cellBuilder: _cell,
      );
      await tester.expectGolden(
        widget,
        'data_table_windowed',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
