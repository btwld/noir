import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

Widget _row(BuildContext context, int index, bool selected) =>
    Text('${selected ? '>' : ' '} row $index');

void main() {
  group('ListView Golden', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester(width: 20, height: 8);
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('plain list shows the first window', () async {
      const widget = ListView(itemCount: 20, height: 5, itemBuilder: _row);
      await tester.expectGolden(
        widget,
        'list_view_plain',
        updateGoldens: _updateGoldens,
      );
    });

    test('selectable list highlights its selected row', () async {
      const widget = ListView(
        itemCount: 20,
        height: 5,
        selectedIndex: 2,
        itemBuilder: _row,
      );
      await tester.expectGolden(
        widget,
        'list_view_selected',
        updateGoldens: _updateGoldens,
      );
    });

    test('scroll indicator reserves the trailing column', () async {
      const widget = ListView(
        itemCount: 20,
        height: 5,
        showScrollIndicator: true,
        itemBuilder: _row,
      );
      await tester.expectGolden(
        widget,
        'list_view_scroll_indicator',
        updateGoldens: _updateGoldens,
      );
    });

    test('taller rows fit fewer items in the same height', () async {
      const widget = ListView(
        itemCount: 20,
        height: 6,
        itemExtent: 2,
        selectedIndex: 1,
        itemBuilder: _row,
      );
      await tester.expectGolden(
        widget,
        'list_view_item_extent',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
