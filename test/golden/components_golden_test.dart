import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void _noop() {}

void main() {
  group('Components Golden', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester(width: 34, height: 12);
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('toggles show both states and the disabled variant', () async {
      final widget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(value: false, label: 'unchecked', onChanged: (_) {}),
          Checkbox(value: true, label: 'checked', onChanged: (_) {}),
          const Checkbox(value: true, label: 'disabled'),
          Switch(value: false, label: 'off', onChanged: (_) {}),
          Switch(value: true, label: 'on', onChanged: (_) {}),
          const Switch(value: false, label: 'disabled'),
        ],
      );
      await tester.expectGolden(
        widget,
        'components_toggles',
        updateGoldens: _updateGoldens,
      );
    });

    test('buttons and badges fill behind their labels', () async {
      const widget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Button(label: 'Enabled', onPressed: _noop),
          Button(label: 'Disabled'),
          Row(
            spacing: 1,
            children: [
              Badge(label: 'NEW'),
              Badge(label: 'OK', variant: BadgeVariant.success),
              Badge(label: 'ERR', variant: BadgeVariant.danger),
            ],
          ),
        ],
      );
      await tester.expectGolden(
        widget,
        'components_button_badge',
        updateGoldens: _updateGoldens,
      );
    });

    test('progress bars step through eighth-cell fills', () async {
      const widget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProgressBar(value: 0, width: 16),
          ProgressBar(value: 0.25, width: 16),
          ProgressBar(value: 0.33, width: 16),
          ProgressBar(value: 0.5, width: 16),
          ProgressBar(value: 1, width: 16),
        ],
      );
      await tester.expectGolden(
        widget,
        'components_progress_bar',
        updateGoldens: _updateGoldens,
      );
    });

    test('dividers separate stacked and side-by-side sections', () async {
      const widget = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('above'),
          Divider(),
          Row(
            children: [
              Text('left '),
              SizedBox(height: 2, child: Divider(axis: Axis.vertical)),
              Text(' right'),
            ],
          ),
          Divider(thickness: 2),
          Text('below'),
        ],
      );
      await tester.expectGolden(
        widget,
        'components_divider',
        updateGoldens: _updateGoldens,
      );
    });

    test('a theme recolors every component at once', () async {
      final widget = Theme(
        data: ThemeData.dark.copyWith(
          accent: Color.magenta,
          accentForeground: Color.black,
          border: Color.cyan,
          success: Color.green,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Button(label: 'Themed', onPressed: () {}),
            Checkbox(value: true, label: 'themed', onChanged: (_) {}),
            Switch(value: true, label: 'themed', onChanged: (_) {}),
            const ProgressBar(value: 0.5, width: 12),
            const Badge(label: 'OK', variant: BadgeVariant.success),
          ],
        ),
      );
      await tester.expectGolden(
        widget,
        'components_themed',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
