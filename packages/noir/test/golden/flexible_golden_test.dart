import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('Flexible Golden', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester(width: 30, height: 8);
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('Expanded siblings split available space evenly', () async {
      const widget = Row(
        children: [
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(color: Color.red),
              child: Text('A', style: TextStyle()),
            ),
          ),
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(color: Color.blue),
              child: Text('B', style: TextStyle()),
            ),
          ),
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(color: Color.green),
              child: Text('C', style: TextStyle()),
            ),
          ),
        ],
      );
      await tester.expectGolden(
        widget,
        'flexible_expanded_even',
        updateGoldens: _updateGoldens,
      );
    });

    test('mixed flex factors 1:2:3 split proportionally', () async {
      const widget = Row(
        children: [
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(color: Color.red),
              child: Text('1', style: TextStyle()),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              height: 3,
              decoration: BoxDecoration(color: Color.blue),
              child: Text('2', style: TextStyle()),
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              height: 3,
              decoration: BoxDecoration(color: Color.green),
              child: Text('3', style: TextStyle()),
            ),
          ),
        ],
      );
      await tester.expectGolden(
        widget,
        'flexible_factors_1_2_3',
        updateGoldens: _updateGoldens,
      );
    });

    test('Flexible (loose fit) shrinks to child size', () async {
      const widget = Row(
        children: [
          SizedBox(
            width: 4,
            child: Container(
              height: 3,
              decoration: BoxDecoration(color: Color.red),
              child: Text('FX', style: TextStyle()),
            ),
          ),
          Flexible(
            child: Container(
              height: 3,
              decoration: BoxDecoration(color: Color.blue),
              child: Text('Lo', style: TextStyle()),
            ),
          ),
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(color: Color.green),
              child: Text('Ex', style: TextStyle()),
            ),
          ),
        ],
      );
      await tester.expectGolden(
        widget,
        'flexible_loose_vs_expanded',
        updateGoldens: _updateGoldens,
      );
    });

    test('Expanded inside Column splits vertical space', () async {
      const widget = SizedBox(
        width: 10,
        height: 6,
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: Color.red),
                child: Text('Top', style: TextStyle()),
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(color: Color.blue),
                child: Text('Bot', style: TextStyle()),
              ),
            ),
          ],
        ),
      );
      await tester.expectGolden(
        widget,
        'flexible_column_1_to_2',
        updateGoldens: _updateGoldens,
      );
    });

    test('odd weighted allocation with fixed integer spacing', () async {
      const widget = SizedBox(
        width: 13,
        height: 3,
        child: Row(
          spacing: 1,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: Color.red),
                child: Text('1'),
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(color: Color.blue),
                child: Text('2'),
              ),
            ),
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(color: Color.green),
                child: Text('3'),
              ),
            ),
          ],
        ),
      );

      await tester.expectGolden(
        widget,
        'flexible_odd_weighted_spacing',
        updateGoldens: _updateGoldens,
      );
    });

    test('integer spaceAround owns odd slack deterministically', () async {
      const widget = SizedBox(
        width: 13,
        height: 3,
        child: Row(
          spacing: 1,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            SizedBox(
              width: 1,
              height: 3,
              child: Container(decoration: BoxDecoration(color: Color.red)),
            ),
            SizedBox(
              width: 1,
              height: 3,
              child: Container(decoration: BoxDecoration(color: Color.blue)),
            ),
            SizedBox(
              width: 1,
              height: 3,
              child: Container(decoration: BoxDecoration(color: Color.green)),
            ),
          ],
        ),
      );

      await tester.expectGolden(
        widget,
        'flexible_integer_space_around',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
