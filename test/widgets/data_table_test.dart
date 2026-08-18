// ignore_for_file: avoid_positional_boolean_parameters
import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';

const _columns = [
  DataColumn(label: 'name', sortable: true),
  DataColumn(label: 'qty', width: 5, alignment: Alignment.centerRight),
  DataColumn(label: 'state', flex: 2),
];

Widget _cell(BuildContext context, int row, int column) => Text(
  switch (column) {
    0 => 'item$row',
    1 => '$row',
    _ => 'ok',
  },
  maxLines: 1,
  softWrap: false,
);

void main() {
  group('DataTable layout', () {
    test('every row breaks its columns at the same terminal columns', () {
      final capture = BufferCapture(width: 24, height: 6);
      try {
        final frame = capture.capture(
          const DataTable(columns: _columns, rowCount: 3, cellBuilder: _cell),
        );
        // The fixed 5-cell qty column is right-aligned, so its digit lands on
        // the same x in the header row's neighbourhood and in every body row.
        final digits = [
          for (var row = 2; row < 5; row++) frame.findText('${row - 2}').first,
        ];
        expect(digits.map((position) => position.x).toSet(), hasLength(1));
      } finally {
        capture.dispose();
      }
    });

    test('a fixed width beats flex and leaves the rest proportional', () {
      final capture = BufferCapture(width: 30, height: 4);
      try {
        final frame = capture.capture(
          const DataTable(
            columns: [
              DataColumn(label: 'a'),
              DataColumn(label: 'bb', width: 4),
              DataColumn(label: 'ccc', flex: 2),
            ],
            rowCount: 1,
            cellBuilder: _cell,
          ),
        );
        // 30 cells minus the fixed 4 leaves 26 split 1:2, so the first flex
        // column takes 9 and the fixed column starts right after it.
        expect(frame.findText('bb').single.x, 9);
        expect(frame.findText('ccc').single.x, 13);
      } finally {
        capture.dispose();
      }
    });

    test('the scroll indicator gutter is reserved in the header too', () {
      final capture = BufferCapture(width: 24, height: 6);
      try {
        Iterable<int> headerAndBodyX(bool indicator) {
          final frame = capture.capture(
            DataTable(
              columns: const [
                DataColumn(label: 'l'),
                DataColumn(label: 'r', alignment: Alignment.centerRight),
              ],
              rowCount: 2,
              height: 5,
              showScrollIndicator: indicator,
              cellBuilder: (context, row, column) =>
                  Text(column == 0 ? 'a' : 'b'),
            ),
          );
          return [frame.findText('r').single.x, frame.findText('b').first.x];
        }

        expect(headerAndBodyX(false).toSet(), hasLength(1));
        expect(headerAndBodyX(true).toSet(), hasLength(1));
      } finally {
        capture.dispose();
      }
    });

    test('the header sits above a separator and the body fills the rest', () {
      final capture = BufferCapture(width: 24, height: 8);
      try {
        final frame = capture.capture(
          const DataTable(
            columns: _columns,
            rowCount: 20,
            height: 6,
            cellBuilder: _cell,
          ),
        );
        expect(frame.findText('name'), hasLength(1));
        // height 6 = header + separator + four body rows.
        expect(frame.findText('item0').single.y, 2);
        expect(frame.findText('item3').single.y, 5);
        expect(frame.findText('item4'), isEmpty);
      } finally {
        capture.dispose();
      }
    });
  });

  group('DataTable body', () {
    test('only the visible rows are built', () {
      final built = <int>[];
      final capture = BufferCapture(width: 24, height: 8);
      try {
        capture.capture(
          DataTable(
            columns: _columns,
            rowCount: 5000,
            height: 6,
            cellBuilder: (context, row, column) {
              if (column == 0) built.add(row);
              return const Text('x');
            },
          ),
        );
        expect(built, [0, 1, 2, 3]);
      } finally {
        capture.dispose();
      }
    });

    test('ArrowDown moves the highlight and Enter confirms it', () async {
      final changes = <int>[];
      final selects = <int>[];
      final driver = KeyDriver(
        DataTable(
          autofocus: true,
          columns: _columns,
          rowCount: 10,
          height: 6,
          selectedIndex: 0,
          cellBuilder: _cell,
          onChanged: changes.add,
          onSelect: selects.add,
        ),
      );
      await driver.ready();

      await driver.sendLogicalKey(LogicalKeyboardKey.arrowDown);
      expect(changes, [1]);
      await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
      expect(selects, [1]);
      driver.dispose();
    });

    test(
      'clicking a body row selects it, offset past header and rule',
      () async {
        final selects = <int>[];
        final driver = KeyDriver(
          DataTable(
            columns: _columns,
            rowCount: 10,
            height: 6,
            selectedIndex: 0,
            cellBuilder: _cell,
            onSelect: selects.add,
          ),
          paintFrames: true,
        );
        await driver.ready();

        // y=2 is the first body row: y=0 is the header, y=1 the separator.
        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.left,
            x: 1,
            y: 3,
          ),
        );
        expect(selects, [1]);
        driver.dispose();
      },
    );

    test('the selected row is painted on selectedBackgroundColor', () {
      final capture = BufferCapture(width: 24, height: 6);
      try {
        final frame = capture.capture(
          const DataTable(
            columns: _columns,
            rowCount: 4,
            height: 5,
            selectedIndex: 1,
            selectedBackgroundColor: Color.magenta,
            cellBuilder: _cell,
          ),
        );
        expect(frame, BufferMatchers.hasBackgroundAt(0, 3, Color.magenta));
        expect(
          frame,
          isNot(BufferMatchers.hasBackgroundAt(0, 2, Color.magenta)),
        );
      } finally {
        capture.dispose();
      }
    });
  });

  group('DataTable sorting', () {
    test('the sorted column carries a direction arrow', () {
      final capture = BufferCapture(width: 24, height: 4);
      try {
        expect(
          capture
              .capture(
                const DataTable(
                  columns: _columns,
                  rowCount: 1,
                  height: 3,
                  sortColumnIndex: 0,
                  cellBuilder: _cell,
                ),
              )
              .findText('name▲'),
          hasLength(1),
        );
        expect(
          capture
              .capture(
                const DataTable(
                  columns: _columns,
                  rowCount: 1,
                  height: 3,
                  sortColumnIndex: 0,
                  sortAscending: false,
                  cellBuilder: _cell,
                ),
              )
              .findText('name▼'),
          hasLength(1),
        );
      } finally {
        capture.dispose();
      }
    });

    test(
      'clicking a sortable header asks for ascending, then reverses',
      () async {
        final requests = <String>[];
        var ascending = true;
        Widget build() => DataTable(
          columns: _columns,
          rowCount: 3,
          height: 5,
          sortColumnIndex: 0,
          sortAscending: ascending,
          cellBuilder: _cell,
          onSort: (column, next) {
            requests.add('$column:$next');
            ascending = next;
          },
        );

        var driver = KeyDriver(build(), paintFrames: true);
        await driver.ready();
        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.left,
            x: 1,
            y: 0,
          ),
        );
        driver.dispose();

        driver = KeyDriver(build(), paintFrames: true);
        await driver.ready();
        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.left,
            x: 1,
            y: 0,
          ),
        );
        driver.dispose();

        expect(requests, ['0:false', '0:true']);
      },
    );

    test('the whole header column is clickable, not just its label', () async {
      final requests = <int>[];
      final driver = KeyDriver(
        DataTable(
          columns: _columns,
          rowCount: 3,
          height: 5,
          cellBuilder: _cell,
          onSort: (column, ascending) => requests.add(column),
        ),
        paintFrames: true,
      );
      await driver.ready();

      // Past the end of the 'name' glyphs but still inside its flex column.
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 12,
          y: 0,
        ),
      );
      expect(requests, [0]);
      driver.dispose();
    });

    test('clicking a header that is not sortable reports nothing', () async {
      final requests = <String>[];
      final driver = KeyDriver(
        DataTable(
          columns: _columns,
          rowCount: 3,
          height: 5,
          cellBuilder: _cell,
          onSort: (column, ascending) => requests.add('$column'),
        ),
        paintFrames: true,
      );
      await driver.ready();

      // The state column starts past the name and qty columns.
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 70,
          y: 0,
        ),
      );
      expect(requests, isEmpty);
      driver.dispose();
    });
  });

  test('the header fill falls back to the theme surface variant', () {
    final capture = BufferCapture(width: 24, height: 4);
    try {
      final frame = capture.capture(
        Theme(
          data: ThemeData.dark.copyWith(surfaceVariant: Color.magenta),
          child: const DataTable(
            columns: _columns,
            rowCount: 1,
            height: 3,
            cellBuilder: _cell,
          ),
        ),
      );
      expect(frame, BufferMatchers.hasBackgroundAt(0, 0, Color.magenta));
    } finally {
      capture.dispose();
    }
  });
}
