import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('Row/Column Sanity Goldens', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester();
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('row_three_labels buffer', () async {
      final widget = Container(
        color: Color.black,
        child: Row(
          children: const [Text('Left'), Text('Middle'), Text('Right')],
        ),
      );
      await tester.expectGoldenBuffer(
        widget,
        'row_three_labels',
        updateGoldens: _updateGoldens,
      );
    });

    test('column_three_lines buffer', () async {
      final widget = Container(
        color: Color.black,
        child: Column(
          children: const [Text('Line 1'), Text('Line 2'), Text('Line 3')],
        ),
      );
      await tester.expectGoldenBuffer(
        widget,
        'column_three_lines',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
