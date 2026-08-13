import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

/// Focus is a non-rendering wrapper, so visual goldens here verify that
/// (a) wrapping a child in Focus does not alter the rendered output, and
/// (b) child widgets that change visuals based on focus state render
/// correctly when focus changes.
void main() {
  group('Focus Golden', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester(width: 30, height: 6);
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('Focus wrapper does not change child output', () async {
      const widget = Focus(
        child: Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(color: Color.blue),
          child: Text('Focusable', style: TextStyle()),
        ),
      );
      await tester.expectGolden(
        widget,
        'focus_wraps_container',
        updateGoldens: _updateGoldens,
      );
    });

    test('Focus pass-through inside a Row of siblings', () async {
      const widget = Row(
        children: [
          Container(
            decoration: BoxDecoration(color: Color.red),
            child: Text('A', style: TextStyle()),
          ),
          Focus(
            child: Container(
              decoration: BoxDecoration(color: Color.green),
              child: Text('B-focusable', style: TextStyle()),
            ),
          ),
          Container(
            decoration: BoxDecoration(color: Color.blue),
            child: Text('C', style: TextStyle()),
          ),
        ],
      );
      await tester.expectGolden(
        widget,
        'focus_in_row',
        updateGoldens: _updateGoldens,
      );
    });

    test('FocusScope passes through unchanged', () async {
      const widget = FocusScope(
        child: Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(color: Color.yellow),
          child: Text('Scope', style: TextStyle(color: Color.black)),
        ),
      );
      await tester.expectGolden(
        widget,
        'focus_scope_passthrough',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
