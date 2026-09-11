import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('SizedBox Golden', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester(width: 30, height: 10);
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('fixed width and height with colored child', () async {
      const widget = SizedBox(
        width: 12,
        height: 4,
        child: Container(
          decoration: BoxDecoration(color: Color.green),
          child: Text('Fixed', style: TextStyle()),
        ),
      );
      await tester.expectGolden(
        widget,
        'sized_box_12x4',
        updateGoldens: _updateGoldens,
      );
    });

    test('width-only sizing in a Row', () async {
      const widget = Row(
        children: [
          SizedBox(
            width: 10,
            child: Container(
              decoration: BoxDecoration(color: Color.red),
              child: Text('A', style: TextStyle()),
            ),
          ),
          Container(
            decoration: BoxDecoration(color: Color.blue),
            child: Text('B', style: TextStyle()),
          ),
        ],
      );
      await tester.expectGolden(
        widget,
        'sized_box_width_only',
        updateGoldens: _updateGoldens,
      );
    });

    test('SizedBox.shrink collapses to zero', () async {
      const widget = Row(
        children: [
          Container(
            decoration: BoxDecoration(color: Color.red),
            child: Text('L', style: TextStyle()),
          ),
          SizedBox.shrink(),
          Container(
            decoration: BoxDecoration(color: Color.blue),
            child: Text('R', style: TextStyle()),
          ),
        ],
      );
      await tester.expectGolden(
        widget,
        'sized_box_shrink',
        updateGoldens: _updateGoldens,
      );
    });

    test('SizedBox.square sets equal width and height', () async {
      const widget = SizedBox.square(
        dimension: 5,
        child: Container(
          decoration: BoxDecoration(color: Color.yellow),
          child: Text('Sq', style: TextStyle(color: Color.black)),
        ),
      );
      await tester.expectGolden(
        widget,
        'sized_box_square_5',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
