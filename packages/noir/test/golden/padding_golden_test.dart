import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('Padding Golden', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester(width: 30, height: 10);
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('symmetric all-sides padding inside a colored container', () async {
      const widget = Container(
        width: 20,
        height: 6,
        decoration: BoxDecoration(color: Color.blue),
        child: Padding(
          padding: EdgeInsets.all(2),
          child: Container(
            decoration: BoxDecoration(color: Color.yellow),
            child: Text('Hi', style: TextStyle(color: Color.black)),
          ),
        ),
      );
      await tester.expectGolden(
        widget,
        'padding_all_2',
        updateGoldens: _updateGoldens,
      );
    });

    test('asymmetric horizontal/vertical padding', () async {
      const widget = Container(
        width: 20,
        height: 6,
        decoration: BoxDecoration(color: Color.blue),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Container(
            decoration: BoxDecoration(color: Color.yellow),
            child: Text('Asym', style: TextStyle(color: Color.black)),
          ),
        ),
      );
      await tester.expectGolden(
        widget,
        'padding_symmetric_h4_v1',
        updateGoldens: _updateGoldens,
      );
    });

    test('per-side padding values', () async {
      const widget = Container(
        width: 20,
        height: 6,
        decoration: BoxDecoration(color: Color.blue),
        child: Padding(
          padding: EdgeInsets.only(left: 1, right: 5, bottom: 2),
          child: Container(
            decoration: BoxDecoration(color: Color.yellow),
            child: Text('LTRB', style: TextStyle(color: Color.black)),
          ),
        ),
      );
      await tester.expectGolden(
        widget,
        'padding_ltrb_1_0_5_2',
        updateGoldens: _updateGoldens,
      );
    });

    test('nested padding compounds', () async {
      const widget = Container(
        width: 20,
        height: 6,
        decoration: BoxDecoration(color: Color.blue),
        child: Padding(
          padding: EdgeInsets.all(1),
          child: Padding(
            padding: EdgeInsets.all(1),
            child: Container(
              decoration: BoxDecoration(color: Color.yellow),
              child: Text('Nest', style: TextStyle(color: Color.black)),
            ),
          ),
        ),
      );
      await tester.expectGolden(
        widget,
        'padding_nested_1_plus_1',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
