import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/golden_testing.dart';

/// Set UPDATE_GOLDENS=1 to regenerate golden files instead of comparing.
final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('Complex Widget Golden Tests', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester(width: 60, height: 20);
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('container with decoration and child', () async {
      const widget = Container(
        padding: EdgeInsets.all(2),
        decoration: BoxDecoration(color: Color.blue),
        child: Text('Styled Container', style: TextStyle()),
      );

      await tester.expectGolden(
        widget,
        'styled_container',
        updateGoldens: _updateGoldens,
      );
    });

    test('complex row layout', () async {
      const widget = Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(padding: EdgeInsets.all(1), child: Text('Left')),
          Container(
            decoration: BoxDecoration(color: Color.yellow),
            child: Text('Center', style: TextStyle(color: Color.black)),
          ),
          Text('Right'),
        ],
      );

      await tester.expectGolden(
        widget,
        'complex_row_layout',
        updateGoldens: _updateGoldens,
      );
    });

    test('complex column layout', () async {
      const widget = Column(
        children: [
          Container(
            width: 40,
            padding: EdgeInsets.all(1),
            decoration: BoxDecoration(color: Color.green),
            child: Text(
              'Header',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Container(
            padding: EdgeInsets.all(2),
            child: Text('Content area with some text'),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [Text('Button 1'), Text('Button 2'), Text('Button 3')],
          ),
        ],
      );

      await tester.expectGolden(
        widget,
        'complex_column_layout',
        updateGoldens: _updateGoldens,
      );
    });

    test('deeply nested widget structure', () async {
      const widget = Container(
        padding: EdgeInsets.all(1),
        decoration: BoxDecoration(color: Color.black),
        child: Column(
          children: [
            Container(
              width: 50,
              padding: EdgeInsets.all(1),
              child: Text(
                'Title',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    decoration: BoxDecoration(color: Color.blue),
                    child: Text('Item 1', style: TextStyle()),
                  ),
                  Container(
                    decoration: BoxDecoration(color: Color.red),
                    child: Text('Item 2', style: TextStyle()),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(1),
              child: Text('Footer', textAlign: TextAlign.center),
            ),
          ],
        ),
      );

      await tester.expectGolden(
        widget,
        'deeply_nested_structure',
        updateGoldens: _updateGoldens,
      );
    });

    test('alignment combinations', () async {
      const widget = Container(
        width: 40,
        height: 10,
        child: Column(
          children: [
            Align(alignment: Alignment.topLeft, child: Text('Top Left')),
            Align(
              child: Container(
                decoration: BoxDecoration(color: Color.yellow),
                child: Text('Center', style: TextStyle(color: Color.black)),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Text('Bottom Right'),
            ),
          ],
        ),
      );

      await tester.expectGolden(
        widget,
        'alignment_combinations',
        updateGoldens: _updateGoldens,
      );
    });

    test('sizing and constraints', () async {
      const widget = Row(
        children: [
          SizedBox(
            width: 15,
            height: 5,
            child: Container(
              decoration: BoxDecoration(color: Color.green),
              child: Text('Fixed', style: TextStyle()),
            ),
          ),
          Container(
            constraints: BoxConstraints(
              minWidth: 10,
              maxWidth: 20,
              minHeight: 1,
              maxHeight: 5,
            ),
            decoration: BoxDecoration(color: Color.blue),
            child: Text('Constrained', style: TextStyle()),
          ),
          Container(width: 12, child: Text('Width 12')),
        ],
      );

      await tester.expectGolden(
        widget,
        'sizing_constraints',
        updateGoldens: _updateGoldens,
      );
    });

    test('layout edge cases', () async {
      const widget = Column(
        children: [
          // Empty container
          Container(
            width: 30,
            height: 2,
            decoration: BoxDecoration(color: Color.white),
          ),
          // Container with only padding
          Container(padding: EdgeInsets.all(2), child: Text('Just Padding')),
          // Row with single child
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Text('Single Child')],
          ),
          // Nested alignment
          Align(
            alignment: Alignment.centerRight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Nested Align'),
            ),
          ),
        ],
      );

      await tester.expectGolden(
        widget,
        'layout_edge_cases',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
