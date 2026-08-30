import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/components_demo.dart';
import '../helpers/golden_testing.dart';
import '../helpers/tui_test_app.dart';

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

    test('panels show default focused and alternate-palette states', () async {
      await tester.expectGoldenMulti(
        {
          'default': const Panel(
            title: 'Panel',
            width: 26,
            child: Text('Default chrome'),
          ),
          'focused': const Panel(
            title: 'Panel',
            focused: true,
            width: 26,
            child: Text('Focused chrome'),
          ),
          'alternate': const Theme(
            data: ThemeData(
              surfaceVariant: Color.blue,
              border: Color.green,
              accent: Color.magenta,
            ),
            child: Panel(
              title: 'Panel',
              focused: true,
              width: 26,
              child: Text('Alternate palette'),
            ),
          ),
        },
        'components_panel_states',
        updateGoldens: _updateGoldens,
      );
    });

    test('modal content inherits default and alternate palettes', () async {
      const alternate = ThemeData(
        surface: Color(0.12, 0.06, 0.08),
        surfaceVariant: Color(0.18, 0.09, 0.11),
        text: Color(0.98, 0.9, 0.84),
        textMuted: Color(0.72, 0.58, 0.55),
        border: Color(0.42, 0.22, 0.24),
        accent: Color(1, 0.55, 0.35),
        accentForeground: Color(0.14, 0.05, 0.02),
      );
      for (final entry in const <String, ThemeData>{
        'default': ThemeData.dark,
        'alternate': alternate,
      }.entries) {
        final controller = ModalController();
        final app = createTuiTestApp(
          Theme(
            data: entry.value,
            child: Modal(
              controller: controller,
              modalBuilder: (context) => const Panel(
                title: 'Modal',
                width: 30,
                focused: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Behavior without built-in chrome'),
                    Row(
                      spacing: 1,
                      children: [
                        Button(label: 'Cancel', onPressed: _noop),
                        Button(label: 'Confirm', onPressed: _noop),
                      ],
                    ),
                  ],
                ),
              ),
              child: const Panel(
                title: 'Base',
                child: Text('Background remains visible'),
              ),
            ),
          ),
          width: 34,
          height: 12,
        );
        try {
          await _settle(app);
          controller.open();
          await _settle(app);
          await tester.expectCapturedGolden(
            app.captureFrame(),
            'components_modal_${entry.key}',
            updateGoldens: _updateGoldens,
          );
        } finally {
          app.dispose();
        }
      }
    });

    test(
      'component sheet shows data widgets across sizes and palettes',
      () async {
        for (final size in const [
          (label: '64x18', width: 64, height: 18),
          (label: '80x24', width: 80, height: 24),
          (label: '100x30', width: 100, height: 30),
        ]) {
          for (final alternate in const [false, true]) {
            final app = createTuiTestApp(
              const ComponentsDemoApp(),
              width: size.width,
              height: size.height,
            );
            try {
              await _settle(app);
              app.mockInput
                ..pressShiftTab()
                ..pressArrow(ArrowDirection.right)
                ..pressArrow(ArrowDirection.right)
                ..pressArrow(ArrowDirection.right);
              await _settle(app);
              if (alternate) {
                app.mockInput.pressCtrl('t');
                await _settle(app);
              }

              await tester.expectCapturedGolden(
                app.captureFrame(),
                'components_data_${alternate ? 'alternate' : 'default'}_'
                '${size.label}',
                updateGoldens: _updateGoldens,
              );
            } finally {
              app.dispose();
            }
          }
        }
      },
    );
  });
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
