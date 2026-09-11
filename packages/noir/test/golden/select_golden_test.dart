import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('Select Golden', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester(width: 30, height: 10);
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('short list with default highlight on first row', () async {
      const widget = Select<String>(
        height: 4,
        options: [
          SelectOption(name: 'Apple', value: 'apple'),
          SelectOption(name: 'Banana', value: 'banana'),
          SelectOption(name: 'Cherry', value: 'cherry'),
        ],
      );
      await tester.expectGolden(
        widget,
        'select_short_list',
        updateGoldens: _updateGoldens,
      );
    });

    test('options with descriptions', () async {
      const widget = Select<int>(
        height: 4,
        options: [
          SelectOption(name: 'One', description: 'first', value: 1),
          SelectOption(name: 'Two', description: 'second', value: 2),
          SelectOption(name: 'Three', description: 'third', value: 3),
        ],
      );
      await tester.expectGolden(
        widget,
        'select_with_description',
        updateGoldens: _updateGoldens,
      );
    });

    test('long list with scroll indicator at top', () async {
      const widget = Select<int>(
        height: 4,
        showScrollIndicator: true,
        options: [
          SelectOption(name: 'Item 1', value: 1),
          SelectOption(name: 'Item 2', value: 2),
          SelectOption(name: 'Item 3', value: 3),
          SelectOption(name: 'Item 4', value: 4),
          SelectOption(name: 'Item 5', value: 5),
          SelectOption(name: 'Item 6', value: 6),
          SelectOption(name: 'Item 7', value: 7),
        ],
      );
      await tester.expectGolden(
        widget,
        'select_long_list_indicator',
        updateGoldens: _updateGoldens,
      );
    });

    test('highlight on second row', () async {
      const widget = Select<String>(
        height: 4,
        selectedIndex: 1,
        options: [
          SelectOption(name: 'Alpha', value: 'a'),
          SelectOption(name: 'Beta', value: 'b'),
          SelectOption(name: 'Gamma', value: 'c'),
        ],
      );
      await tester.expectGolden(
        widget,
        'select_highlight_second',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
